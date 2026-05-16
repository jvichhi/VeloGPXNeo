//
//  PlanState.swift
//  VeloGPX
//
//  F-C2 (May 16 2026): PlanWaypoint gains intentKind and dwellMinutes.
//  WaypointStopKind mirrors IntentStopKind but lives here with no
//  FoundationModels dependency, keeping this file Watch-safe.
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

// MARK: - WaypointStopKind
//
// Mirror of IntentStopKind (RidePlanIntent+Generable.swift).
// Defined here independently so PlanState.swift has zero FoundationModels
// dependency and can remain in the Watch target if needed in future.
// PlanAssistantEngine maps IntentStopKind → WaypointStopKind on write.

enum WaypointStopKind {
    case cafe
    case park
    case town
    case service
    case other
}

// MARK: - Supporting Types

struct PlanWaypoint: Identifiable, Equatable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String?
    /// Set by PlanAssistantEngine for AI-planned stops. Nil for manually dropped pins.
    var intentKind: WaypointStopKind?
    /// Dwell time in minutes at this stop. Nil for manually dropped pins.
    var dwellMinutes: Int?

    init(
        coordinate: CLLocationCoordinate2D,
        name: String? = nil,
        intentKind: WaypointStopKind? = nil,
        dwellMinutes: Int? = nil
    ) {
        self.id = UUID()
        self.coordinate = coordinate
        self.name = name
        self.intentKind = intentKind
        self.dwellMinutes = dwellMinutes
    }

    static func == (lhs: PlanWaypoint, rhs: PlanWaypoint) -> Bool {
        lhs.id == rhs.id
    }
}

struct PlanSegment: Identifiable {
    let id: UUID
    let fromWaypointID: UUID
    let toWaypointID: UUID
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let elevationGain: Double
    let isLoop: Bool

    init(
        fromWaypointID: UUID,
        toWaypointID: UUID,
        coordinates: [CLLocationCoordinate2D],
        distance: CLLocationDistance,
        elevationGain: Double = 0,
        isLoop: Bool = false
    ) {
        self.id = UUID()
        self.fromWaypointID = fromWaypointID
        self.toWaypointID = toWaypointID
        self.coordinates = coordinates
        self.distance = distance
        self.elevationGain = elevationGain
        self.isLoop = isLoop
    }
}

// MARK: - PlanState

final class PlanState: ObservableObject {

    @Published var waypoints: [PlanWaypoint] = []
    @Published var segments: [PlanSegment] = []
    @Published var isLoopClosed: Bool = false
    @Published var isRouting: Bool = false
    @Published var routingError: String? = nil

    // MARK: Derived

    var fullPolyline: [CLLocationCoordinate2D] {
        segments.flatMap { $0.coordinates }
    }

    var loopPolyline: [CLLocationCoordinate2D] {
        segments.first(where: { $0.isLoop })?.coordinates ?? []
    }

    var routePolyline: [CLLocationCoordinate2D] {
        segments.filter { !$0.isLoop }.flatMap { $0.coordinates }
    }

    var totalDistance: CLLocationDistance {
        segments.reduce(0) { $0 + $1.distance }
    }

    var totalElevationGain: Double {
        segments.reduce(0) { $0 + $1.elevationGain }
    }

    var isRideable: Bool {
        waypoints.count >= 2 && segments.contains(where: { !$0.isLoop })
    }

    var canCloseLoop: Bool {
        waypoints.count >= 2
    }

    // MARK: Waypoint Mutation

    @MainActor
    func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        waypoints.append(PlanWaypoint(coordinate: coordinate))
    }

    @MainActor
    func removeWaypoint(id: UUID) {
        waypoints.removeAll { $0.id == id }
        segments.removeAll { $0.fromWaypointID == id || $0.toWaypointID == id }
        if isLoopClosed {
            segments.removeAll { $0.isLoop }
            if waypoints.count < 2 { isLoopClosed = false }
        }
    }

    @MainActor
    func moveWaypoint(fromOffsets: IndexSet, toOffset: Int) {
        waypoints.move(fromOffsets: fromOffsets, toOffset: toOffset)
        segments.removeAll()
    }

    @MainActor
    func toggleLoop() {
        guard canCloseLoop else { return }
        if isLoopClosed {
            segments.removeAll { $0.isLoop }
            isLoopClosed = false
        } else {
            isLoopClosed = true
        }
    }

    @MainActor
    func clearAll() {
        waypoints.removeAll()
        segments.removeAll()
        isLoopClosed = false
        isRouting = false
        routingError = nil
    }

    /// Reconstruct waypoints from an existing RouteModel.
    /// WaypointPoint.coordinate and TrackPoint.coordinate are typed as the
    /// app's own `Coordinate` struct — use .clCoordinate to get CLLocationCoordinate2D.
    @MainActor
    func loadFrom(route: RouteModel) {
        clearAll()
        if !route.waypoints.isEmpty {
            waypoints = route.waypoints.map {
                PlanWaypoint(coordinate: $0.coordinate.clCoordinate, name: $0.name)
            }
        } else {
            waypoints = sampleTrack(route.trackPoints, maxInterval: 200)
                .map { PlanWaypoint(coordinate: $0.coordinate.clCoordinate) }
        }
    }

    // MARK: Segment Write-back

    @MainActor
    func upsertSegment(_ segment: PlanSegment) {
        if let idx = segments.firstIndex(where: {
            $0.fromWaypointID == segment.fromWaypointID &&
            $0.toWaypointID   == segment.toWaypointID
        }) {
            segments[idx] = segment
        } else {
            if let fromIdx = waypoints.firstIndex(where: { $0.id == segment.fromWaypointID }) {
                if segment.isLoop {
                    segments.removeAll { $0.isLoop }
                    segments.append(segment)
                } else {
                    let insertAt = segments.lastIndex(where: { seg in
                        guard !seg.isLoop,
                              let idx = waypoints.firstIndex(where: { $0.id == seg.fromWaypointID })
                        else { return false }
                        return idx < fromIdx
                    }).map { $0 + 1 } ?? (segments.firstIndex(where: { $0.isLoop }) ?? segments.endIndex)
                    segments.insert(segment, at: insertAt)
                }
            } else {
                segments.append(segment)
            }
        }
    }

    @MainActor
    func pruneOrphanedSegments() {
        let ids = Set(waypoints.map { $0.id })
        segments.removeAll { !ids.contains($0.fromWaypointID) || !ids.contains($0.toWaypointID) }
    }

    // MARK: Build RouteModel

    func buildRouteModel(name: String) -> RouteModel {
        let trackPoints: [TrackPoint] = segments
            .flatMap { $0.coordinates }
            .map { TrackPoint(coordinate: $0) }
        let waypointPoints: [WaypointPoint] = waypoints
            .map { WaypointPoint(coordinate: $0.coordinate, name: $0.name) }
        return RouteModel(
            name: name,
            sourceFormat: .planned,
            trackPoints: trackPoints,
            waypoints: waypointPoints
        )
    }

    static func autoName() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return "Planned Route - " + df.string(from: Date())
    }

    // MARK: - Private Helpers

    /// Reduce a dense track to at most one point per `maxInterval` metres.
    private func sampleTrack(_ points: [TrackPoint], maxInterval: CLLocationDistance) -> [TrackPoint] {
        guard !points.isEmpty else { return [] }
        var result: [TrackPoint] = [points[0]]
        var lastLoc = CLLocation(
            latitude:  points[0].coordinate.clCoordinate.latitude,
            longitude: points[0].coordinate.clCoordinate.longitude
        )
        for pt in points.dropFirst() {
            let cl = pt.coordinate.clCoordinate
            let loc = CLLocation(latitude: cl.latitude, longitude: cl.longitude)
            if loc.distance(from: lastLoc) >= maxInterval {
                result.append(pt)
                lastLoc = loc
            }
        }
        // Always include the final point
        if let last = points.last, result.last?.coordinate != last.coordinate {
            result.append(last)
        }
        return result
    }
}
