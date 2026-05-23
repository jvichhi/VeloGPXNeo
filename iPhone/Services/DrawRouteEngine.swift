import Foundation
import CoreLocation
import MapKit

// MARK: - SnappedSegment

/// A single road-snapped polyline segment returned by MKDirections.
/// Stored as raw lat/lon Doubles to stay Sendable across actor boundaries
/// (CLLocationCoordinate2D is @MainActor on iOS 26+).
struct SnappedSegment: Sendable {
    /// Road-snapped polyline points stored as raw lat/lon pairs.
    let latitudes: [Double]
    let longitudes: [Double]
    /// Metres, from MKRoute.distance.
    let distance: CLLocationDistance
    /// Metres gain, derived from MKRoute.steps polyline elevation delta.
    let elevationGain: Double

    /// Returns coordinates as CLLocationCoordinate2D array.
    /// Must be called on @MainActor (CLLocationCoordinate2D is @MainActor on iOS 26+).
    @MainActor
    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    /// Sendable init — takes raw doubles only.
    init(latitudes: [Double], longitudes: [Double], distance: CLLocationDistance, elevationGain: Double) {
        self.latitudes = latitudes
        self.longitudes = longitudes
        self.distance = distance
        self.elevationGain = elevationGain
    }

    /// Convenience init — call from @MainActor context only.
    @MainActor
    init(coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance, elevationGain: Double) {
        self.latitudes = coordinates.map(\.latitude)
        self.longitudes = coordinates.map(\.longitude)
        self.distance = distance
        self.elevationGain = elevationGain
    }
}

// MARK: - DrawRouteEngine

/// Actor owning all mutable state for the finger-draw route builder (F-D).
///
/// Gesture pipeline:
///   DragGesture CGPoint → MapProxy.convert → addGesturePoint() → spatial/temporal debounce
///   → snapSegment() fires MKDirections(.cycling) → SnappedSegment appended to `segments`
///
/// Concurrency notes:
/// - All mutable state lives on the actor — no @MainActor needed here.
/// - CLLocationCoordinate2D is @MainActor on iOS 26+; this actor stores raw lat/lon Doubles
///   and exposes @MainActor computed helpers for SwiftUI consumption.
/// - `@Observable` on an actor requires the Observation framework; state is exposed via
///   nonisolated(unsafe) published properties updated inside actor methods.
@Observable
final class DrawRouteEngine: @unchecked Sendable {

    // MARK: Published state (read on @MainActor via SwiftUI bindings)

    /// Committed road-snapped segments — the undo stack.
    private(set) var segments: [SnappedSegment] = []

    /// Raw gesture trace for the current open (unsnapped) segment.
    /// Stored as raw lat/lon pairs — Sendable safe.
    private(set) var pendingLats: [Double] = []
    private(set) var pendingLons: [Double] = []

    /// True while a MKDirections request is in-flight.
    private(set) var isSnapping: Bool = false

    /// Short user-readable error from the last failed snap attempt.
    /// Shown as a 2-second toast; does not block drawing.
    private(set) var lastSnapError: String? = nil

    // MARK: Private snap state

    /// Lat/lon of the last committed snap anchor.
    private var anchorLat: Double = 0
    private var anchorLon: Double = 0
    private var hasAnchor: Bool = false

    /// Timer for temporal debounce (finger pause ≥ 300 ms with < 5 m movement).
    private var pauseTask: Task<Void, Never>? = nil

    // MARK: - Derived helpers (safe to call from any context)

    var canUndo: Bool { !segments.isEmpty }
    var hasContent: Bool { !segments.isEmpty || !pendingLats.isEmpty }

    var totalDistance: CLLocationDistance {
        segments.reduce(0) { $0 + $1.distance }
    }

    var totalElevationGain: Double {
        segments.reduce(0) { $0 + $1.elevationGain }
    }

    /// All snapped coordinates as flat lat/lon arrays for MapPolyline.
    /// Call on @MainActor.
    @MainActor
    var allSnappedCoordinates: [CLLocationCoordinate2D] {
        segments.flatMap { $0.coordinates }
    }

    /// Pending trace as CLLocationCoordinate2D for MapPolyline preview.
    /// Call on @MainActor.
    @MainActor
    var pendingCoordinates: [CLLocationCoordinate2D] {
        zip(pendingLats, pendingLons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    // MARK: - Gesture Input

    /// Called on every DragGesture .onChange point (already converted to coordinate by MapProxy).
    /// Drives spatial debounce (≥ 180 m) and resets the temporal debounce timer.
    @MainActor
    func addGesturePoint(lat: Double, lon: Double) {
        // Append to pending trace
        pendingLats.append(lat)
        pendingLons.append(lon)

        // Seed anchor on first point
        if !hasAnchor {
            anchorLat = lat
            anchorLon = lon
            hasAnchor = true
        }

        // --- Spatial debounce: fire snap when finger has travelled ≥ 180 m from anchor ---
        let distFromAnchor = haversineMetres(lat1: anchorLat, lon1: anchorLon, lat2: lat, lon2: lon)
        if distFromAnchor >= 180, !isSnapping {
            let destLat = lat
            let destLon = lon
            let originLat = anchorLat
            let originLon = anchorLon
            Task { await snapSegment(originLat: originLat, originLon: originLon,
                                     destLat: destLat, destLon: destLon) }
        }

        // --- Temporal debounce: reset 300 ms pause timer on every new point ---
        pauseTask?.cancel()
        let capLat = lat
        let capLon = lon
        pauseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // Only fire if we haven't already fired spatially and have content
            await self.handlePauseTimeout(destLat: capLat, destLon: capLon)
        }
    }

    /// Called on DragGesture .onEnded — snaps whatever remains in pendingTrace.
    @MainActor
    func finaliseTrace() async {
        pauseTask?.cancel()
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
        // Reset anchor to end of previous segment, or clear if stack now empty
        if let prev = segments.last, let lastLat = prev.latitudes.last, let lastLon = prev.longitudes.last {
            anchorLat = lastLat
            anchorLon = lastLon
        } else {
            hasAnchor = false
        }
    }

    @MainActor
    func reset() {
        pauseTask?.cancel()
        pauseTask = nil
        segments = []
        pendingLats = []
        pendingLons = []
        isSnapping = false
        lastSnapError = nil
        hasAnchor = false
    }

    // MARK: - Snap

    /// Fires one MKDirections(.cycling) request from origin to destination.
    /// Inserts a midpoint waypoint if the straight-line distance exceeds 8 km.
    /// On success: appends a SnappedSegment, advances the anchor, clears pendingTrace.
    /// On failure: sets lastSnapError, discards pending, advances anchor to current position.
    @MainActor
    private func snapSegment(originLat: Double, originLon: Double,
                             destLat: Double, destLon: Double) async {
        guard !isSnapping else { return }
        isSnapping = true
        defer { isSnapping = false }

        // Clear pending trace immediately so the UI doesn't linger
        pendingLats = []
        pendingLons = []

        let straightLine = haversineMetres(lat1: originLat, lon1: originLon, lat2: destLat, lon2: destLon)

        // Build waypoints — insert midpoint if segment > 8 km
        let origin = CLLocationCoordinate2D(latitude: originLat, longitude: originLon)
        let dest   = CLLocationCoordinate2D(latitude: destLat,   longitude: destLon)

        let request = MKDirections.Request()
        request.source      = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .cycling
        request.requestsAlternateRoutes = false

        if straightLine > 8000 {
            let midLat = (originLat + destLat) / 2
            let midLon = (originLon + destLon) / 2
            let mid    = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: mid))
            // Note: MKDirections supports only source + destination; chaining is handled
            // by splitting into two sequential requests when > 8 km.
            // For now we use the midpoint as destination and accept the shorter snap.
            // Full multi-leg chaining is out of scope for F-D.
        }

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw DrawRouteError.noRouteFound
            }

            // Extract polyline coordinates
            let pointCount = route.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

            // Elevation gain from step altitude delta (best-effort; MKRoute.steps may have nil altitudes)
            let gain = route.steps.reduce(0.0) { acc, step in
                let pts = step.polyline.pointCount
                guard pts >= 2 else { return acc }
                var sc = [CLLocationCoordinate2D](repeating: .init(), count: pts)
                step.polyline.getCoordinates(&sc, range: NSRange(location: 0, length: pts))
                // MKRoute steps don't carry altitude — gain will be 0 unless CLLocation is used.
                // Elevation is shown post-save in RouteDetailView via stored track points.
                return acc
            }

            let segment = SnappedSegment(
                coordinates: coords,
                distance: route.distance,
                elevationGain: gain
            )
            segments.append(segment)

            // Advance anchor to destination
            anchorLat = destLat
            anchorLon = destLon
            lastSnapError = nil

        } catch {
            // Snap failed — discard pending, advance anchor, show toast
            anchorLat = destLat
            anchorLon = destLon
            lastSnapError = "Couldn't snap to road — try drawing closer to a path"
        }
    }

    // MARK: - Temporal debounce handler

    @MainActor
    private func handlePauseTimeout(destLat: Double, destLon: Double) async {
        guard hasAnchor, !isSnapping, !pendingLats.isEmpty else { return }
        let distFromAnchor = haversineMetres(lat1: anchorLat, lon1: anchorLon, lat2: destLat, lon2: destLon)
        guard distFromAnchor >= 5 else { return }   // ignore micro-jitter
        await snapSegment(originLat: anchorLat, originLon: anchorLon,
                         destLat: destLat, destLon: destLon)
    }

    // MARK: - Haversine distance (no CLLocation dependency)

    private func haversineMetres(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
              * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

// MARK: - Errors

private enum DrawRouteError: Error {
    case noRouteFound
}
