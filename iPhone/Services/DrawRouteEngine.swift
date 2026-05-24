//
//  DrawRouteEngine.swift
//  VeloGPX
//
//  F-D: Draw Route engine.
//  CHANGED (Sprint 5 · F-D5 overhaul):
//    - Removed spatial debounce (180 m) and temporal debounce (300 ms).
//    - Snap now fires ONLY on gesture lift (.onEnded) via finaliseStroke().
//      This eliminates mid-stroke zigzag detours (see screenshot 3 analysis).
//    - finaliseTrace() renamed → finaliseStroke() for clarity; same semantics.
//    - pauseTask / handlePauseTimeout removed entirely.

import Foundation
import CoreLocation
import MapKit

// MARK: - SnappedSegment

/// A single road-snapped polyline segment returned by MKDirections.
/// Stored as raw lat/lon Doubles to stay Sendable across actor boundaries
/// (CLLocationCoordinate2D is @MainActor on iOS 26+).
struct SnappedSegment: Sendable {
    let latitudes: [Double]
    let longitudes: [Double]
    let distance: CLLocationDistance
    let elevationGain: Double

    @MainActor
    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    init(latitudes: [Double], longitudes: [Double], distance: CLLocationDistance, elevationGain: Double) {
        self.latitudes = latitudes
        self.longitudes = longitudes
        self.distance = distance
        self.elevationGain = elevationGain
    }

    @MainActor
    init(coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance, elevationGain: Double) {
        self.latitudes = coordinates.map(\.latitude)
        self.longitudes = coordinates.map(\.longitude)
        self.distance = distance
        self.elevationGain = elevationGain
    }
}

// MARK: - DrawRouteEngine

/// Observable engine for the finger-draw route builder (F-D).
///
/// Gesture pipeline (snap-on-lift model — matches Strava UX):
///   DragGesture .onChange  → addGesturePoint()   — accumulates pendingLats/pendingLons ONLY
///   DragGesture .onEnded   → finaliseStroke()     — snaps full pending trace as one MKDirections call
///   Done button            → finaliseStroke()     — flushes any open stroke before commit
///
/// Concurrency:
///   CLLocationCoordinate2D is @MainActor on iOS 26+ — never stored in Sendable types.
///   All mutating entry points are @MainActor.
@Observable
final class DrawRouteEngine: @unchecked Sendable {

    // MARK: Published state

    private(set) var segments: [SnappedSegment] = []
    private(set) var pendingLats: [Double] = []
    private(set) var pendingLons: [Double] = []
    private(set) var isSnapping: Bool = false
    private(set) var lastSnapError: String? = nil

    // MARK: Private anchor state

    private var anchorLat: Double = 0
    private var anchorLon: Double = 0
    private var hasAnchor: Bool = false

    // MARK: - Derived helpers

    var canUndo: Bool { !segments.isEmpty }
    var hasContent: Bool { !segments.isEmpty || !pendingLats.isEmpty }

    var totalDistance: CLLocationDistance {
        segments.reduce(0) { $0 + $1.distance }
    }

    var totalElevationGain: Double {
        segments.reduce(0) { $0 + $1.elevationGain }
    }

    @MainActor
    var allSnappedCoordinates: [CLLocationCoordinate2D] {
        segments.flatMap { $0.coordinates }
    }

    @MainActor
    var pendingCoordinates: [CLLocationCoordinate2D] {
        zip(pendingLats, pendingLons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    // MARK: - Gesture Input

    /// Called on every DragGesture .onChange point (coordinate already converted by MapProxy).
    /// ONLY accumulates the pending trace — no snap fires mid-stroke.
    @MainActor
    func addGesturePoint(lat: Double, lon: Double) {
        pendingLats.append(lat)
        pendingLons.append(lon)
        if !hasAnchor {
            anchorLat = lat
            anchorLon = lon
            hasAnchor = true
        }
    }

    /// Called on DragGesture .onEnded — snaps the full pending stroke as one segment.
    /// Also called by the Done button to flush any open stroke.
    @MainActor
    func finaliseStroke() async {
        guard hasAnchor, !pendingLats.isEmpty else { return }
        guard let destLat = pendingLats.last, let destLon = pendingLons.last else { return }
        guard !isSnapping else { return }
        await snapSegment(originLat: anchorLat, originLon: anchorLon,
                          destLat: destLat, destLon: destLon)
    }

    // MARK: - Undo / Reset

    @MainActor
    func undoLastSegment() {
        guard !segments.isEmpty else { return }
        segments.removeLast()
        if let prev = segments.last, let lastLat = prev.latitudes.last, let lastLon = prev.longitudes.last {
            anchorLat = lastLat
            anchorLon = lastLon
        } else {
            hasAnchor = false
        }
    }

    @MainActor
    func reset() {
        segments = []
        pendingLats = []
        pendingLons = []
        isSnapping = false
        lastSnapError = nil
        hasAnchor = false
    }

    @MainActor
    func clearSnapError() {
        lastSnapError = nil
    }

    // MARK: - Compatibility alias

    /// Deprecated — kept so DrawRouteView compiles during step-by-step migration.
    /// Will be removed when DrawRouteView is replaced by inline draw mode in PlanView.
    @MainActor
    func finaliseTrace() async {
        await finaliseStroke()
    }

    // MARK: - Snap

    /// Fires one MKDirections(.cycling) request origin→destination.
    /// Inserts a midpoint waypoint when the straight-line distance exceeds 8 km.
    @MainActor
    private func snapSegment(originLat: Double, originLon: Double,
                              destLat: Double, destLon: Double) async {
        guard !isSnapping else { return }
        isSnapping = true
        defer { isSnapping = false }

        // Clear pending trace so UI doesn't linger
        pendingLats = []
        pendingLons = []

        let straightLine = haversineMetres(lat1: originLat, lon1: originLon, lat2: destLat, lon2: destLon)

        let originLocation = CLLocation(latitude: originLat, longitude: originLon)
        let destLocation   = CLLocation(latitude: destLat,   longitude: destLon)

        let request = MKDirections.Request()
        request.source                  = MKMapItem(location: originLocation, address: nil)
        request.destination             = MKMapItem(location: destLocation,   address: nil)
        request.transportType           = .cycling
        request.requestsAlternateRoutes = false

        if straightLine > 8000 {
            let midLat = (originLat + destLat) / 2
            let midLon = (originLon + destLon) / 2
            let midLocation = CLLocation(latitude: midLat, longitude: midLon)
            request.destination = MKMapItem(location: midLocation, address: nil)
        }

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw DrawRouteError.noRouteFound
            }

            let pointCount = route.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

            let segment = SnappedSegment(coordinates: coords, distance: route.distance, elevationGain: 0)
            segments.append(segment)

            anchorLat = destLat
            anchorLon = destLon
            lastSnapError = nil

        } catch {
            lastSnapError = "Couldn't snap to road — try drawing closer to a path"
            anchorLat = destLat
            anchorLon = destLon
        }
    }

    // MARK: - Haversine

    private func haversineMetres(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2)
            + cos(lat1 * .pi/180) * cos(lat2 * .pi/180) * sin(dLon/2)*sin(dLon/2)
        return R * 2 * atan2(sqrt(a), sqrt(1-a))
    }
}

// MARK: - DrawRouteError

enum DrawRouteError: Error, Equatable {
    case noRouteFound
}
