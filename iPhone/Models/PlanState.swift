//
//  PlanState.swift
//  VeloGPX
//
//  Observable model for the Plan tab. Holds ordered waypoints and
//  the road-snapped segments computed between them.
//
//  @MainActor is intentionally NOT on the class - it conflicts with
//  ObservableObject's objectWillChange publisher in some toolchain versions.
//  All mutating methods are individually @MainActor isolated.
//

import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Supporting Types

struct PlanWaypoint: Identifiable, Equatable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    /// Reverse-geocoded street/place label; nil until resolved.
    var name: String?

    init(coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.id = UUID()
        self.coordinate = coordinate
        self.name = name
    }

    static func == (lhs: PlanWaypoint, rhs: PlanWaypoint) -> Bool {
        lhs.id == rhs.id
    }
}

struct PlanSegment: Identifiable {
    let id: UUID
    /// ID of the origin `PlanWaypoint`.
    let fromWaypointID: UUID
    /// ID of the destination `PlanWaypoint`.
    let toWaypointID: UUID
    /// Road-snapped coordinate array returned by MapKit.
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let elevationGain: Double
    /// `true` for the synthetic close-loop leg (last -> first waypoint).
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

    // MARK: Published

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
        let wp = PlanWaypoint(coordinate: coordinate)
        waypoints.append(wp)
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

    // MARK: Segment Write-back (called by PlanRouteEngine)

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

        let waypointPoints: [WaypointPoint] = waypoints.map {
            WaypointPoint(coordinate: $0.coordinate, name: $0.name)
        }

        return RouteModel(
            name: name,
            sourceFormat: .planned,
            trackPoints: trackPoints,
            waypoints: waypointPoints
        )
    }

    // MARK: Auto-name helper

    static func autoName() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return "Planned Route \u{2014} " + df.string(from: Date())
    }
}
