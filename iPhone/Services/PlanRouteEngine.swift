//
//  PlanRouteEngine.swift
//  VeloGPX
//
//  Chains CyclingRouteService calls between consecutive PlanWaypoints.
//  Dirty-segment detection avoids recomputing unchanged pairs.
//  A failed segment falls back to a straight-line stub so planning
//  is never blocked by a routing error.
//

import Foundation
import CoreLocation
import MapKit

@MainActor
final class PlanRouteEngine {

    // MARK: - Public API

    func refreshSegments(in state: PlanState, affectedWaypointIndices: [Int]) async {
        state.pruneOrphanedSegments()
        let pairs = dirtyPairs(
            for: affectedWaypointIndices,
            waypoints: state.waypoints,
            existingSegments: state.segments,
            isLoop: state.isLoopClosed
        )
        await computeAndApply(pairs: pairs, state: state)
    }

    func recomputeAll(in state: PlanState) async {
        state.segments.removeAll()
        let pairs = allPairs(waypoints: state.waypoints, isLoop: state.isLoopClosed)
        await computeAndApply(pairs: pairs, state: state)
    }

    func refreshLoopSegment(in state: PlanState) async {
        if state.isLoopClosed,
           let first = state.waypoints.first,
           let last  = state.waypoints.last,
           first.id != last.id {
            await computeAndApply(
                pairs: [(from: last, to: first, isLoop: true)],
                state: state
            )
        } else {
            state.segments.removeAll { $0.isLoop }
        }
    }

    // MARK: - Pair Building

    private typealias SegmentPair = (from: PlanWaypoint, to: PlanWaypoint, isLoop: Bool)

    private func allPairs(waypoints: [PlanWaypoint], isLoop: Bool) -> [SegmentPair] {
        guard waypoints.count >= 2 else { return [] }
        var pairs: [SegmentPair] = zip(waypoints, waypoints.dropFirst())
            .map { (from: $0, to: $1, isLoop: false) }
        if isLoop, let first = waypoints.first, let last = waypoints.last, first.id != last.id {
            pairs.append((from: last, to: first, isLoop: true))
        }
        return pairs
    }

    private func dirtyPairs(
        for affectedIndices: [Int],
        waypoints: [PlanWaypoint],
        existingSegments: [PlanSegment],
        isLoop: Bool
    ) -> [SegmentPair] {
        guard waypoints.count >= 2 else { return [] }
        let existingKeys = Set(existingSegments.map { "\($0.fromWaypointID)-\($0.toWaypointID)" })

        var dirty: [SegmentPair] = []
        for idx in affectedIndices {
            if idx < waypoints.count - 1 {
                let pair: SegmentPair = (from: waypoints[idx], to: waypoints[idx + 1], isLoop: false)
                if !existingKeys.contains("\(pair.from.id)-\(pair.to.id)") { dirty.append(pair) }
            }
            if idx > 0 {
                let pair: SegmentPair = (from: waypoints[idx - 1], to: waypoints[idx], isLoop: false)
                if !existingKeys.contains("\(pair.from.id)-\(pair.to.id)") { dirty.append(pair) }
            }
        }
        if isLoop, let first = waypoints.first, let last = waypoints.last, first.id != last.id {
            let key = "\(last.id)-\(first.id)"
            if !existingKeys.contains(key) {
                dirty.append((from: last, to: first, isLoop: true))
            }
        }
        return dirty
    }

    // MARK: - Computation

    private func computeAndApply(pairs: [SegmentPair], state: PlanState) async {
        guard !pairs.isEmpty else { return }
        state.isRouting = true
        defer { state.isRouting = false }

        await withTaskGroup(of: PlanSegment?.self) { group in
            for pair in pairs {
                group.addTask {
                    await Self.computeSegment(from: pair.from, to: pair.to, isLoop: pair.isLoop)
                }
            }
            for await segment in group {
                guard let seg = segment else { continue }
                await MainActor.run { state.upsertSegment(seg) }
            }
        }
    }

    private static func computeSegment(
        from: PlanWaypoint,
        to: PlanWaypoint,
        isLoop: Bool
    ) async -> PlanSegment {
        do {
            let result = try await CyclingRouteService.shared.calculateRoute(
                from: from.coordinate,
                to: to.coordinate
            )
            let coords = Self.extractCoordinates(from: result.route.polyline)
            return PlanSegment(
                fromWaypointID: from.id,
                toWaypointID: to.id,
                coordinates: coords,
                distance: result.route.distance,
                elevationGain: 0,
                isLoop: isLoop
            )
        } catch {
            // Straight-line fallback so the user is never blocked.
            let dist = from.coordinate.planDistance(to: to.coordinate)
            return PlanSegment(
                fromWaypointID: from.id,
                toWaypointID: to.id,
                coordinates: [from.coordinate, to.coordinate],
                distance: dist,
                elevationGain: 0,
                isLoop: isLoop
            )
        }
    }

    private static func extractCoordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }
}

// MARK: - CLLocationCoordinate2D plan-local helper
// Named planDistance to avoid collision with any app-wide distance(to:) extension.

private extension CLLocationCoordinate2D {
    func planDistance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
