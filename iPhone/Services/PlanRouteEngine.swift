//
//  PlanRouteEngine.swift
//  VeloGPX
//
//  Chains CyclingRouteService calls between consecutive PlanWaypoints.
//  Dirty-segment detection avoids recomputing unchanged pairs.
//
//  CONCURRENCY NOTE (fix, May 16 2026):
//  MKDirections throttles aggressively beyond ~3 concurrent per-app requests.
//  The previous withTaskGroup fired all segments simultaneously, causing
//  excess requests to fail silently — those failures were replaced with
//  straight-line stubs, producing the phantom 208 km straight-line routes.
//
//  Fix: a single withTaskGroup with a sliding-window cap of 2 concurrent
//  MKDirections requests. As each task completes the next pair is enqueued,
//  keeping exactly 2 in-flight at all times. This is the standard Apple
//  pattern for rate-limited batched network work and does NOT cause Swift 6
//  build errors — all mutation stays isolated; tasks return values only.
//
//  FALLBACK REMOVED:
//  computeSegment now returns PlanSegment? (nil on failure) instead of
//  silently substituting a straight-line stub. Failures are counted on
//  PlanState.routingFailureCount so the UI can surface a warning banner.
//

import Foundation
import CoreLocation
import MapKit

@MainActor
final class PlanRouteEngine {

    // Cancels any in-flight routing task before starting a new one.
    private var currentTask: Task<Void, Never>?

    // MARK: - Public API

    func refreshSegments(in state: PlanState, affectedWaypointIndices: [Int]) async {
        currentTask?.cancel()
        currentTask = Task {
            state.pruneOrphanedSegments()
            let pairs = dirtyPairs(
                for: affectedWaypointIndices,
                waypoints: state.waypoints,
                existingSegments: state.segments,
                isLoop: state.isLoopClosed
            )
            await computeAndApply(pairs: pairs, state: state)
        }
        await currentTask?.value
    }

    func recomputeAll(in state: PlanState) async {
        currentTask?.cancel()
        currentTask = Task {
            state.segments.removeAll()
            let pairs = allPairs(waypoints: state.waypoints, isLoop: state.isLoopClosed)
            await computeAndApply(pairs: pairs, state: state)
        }
        await currentTask?.value
    }

    func refreshLoopSegment(in state: PlanState) async {
        currentTask?.cancel()
        currentTask = Task {
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
        await currentTask?.value
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

    /// Executes routing for each pair with a sliding-window concurrency cap of 2.
    ///
    /// Why a cap instead of full parallelism:
    ///   MKDirections throttles at ~3 concurrent requests per app. Firing all
    ///   segments simultaneously caused excess requests to throw, which the old
    ///   code silently replaced with straight-line stubs.
    ///
    /// Why not a plain serial `for` loop:
    ///   A bare `for pair in pairs { await ... }` doesn't respect task cancellation
    ///   between iterations — the loop would block until every segment resolved
    ///   even after the user changed the plan. The task group approach lets us
    ///   call group.cancelAll() the moment Task.isCancelled is detected.
    ///
    /// Swift 6 safety: all mutation is isolated — tasks return values only,
    /// state is written on @MainActor inside the main loop. No data races.
    ///
    /// F-C3: after routing completes, matchTargetDistance extends loops that are
    /// too short relative to the user's requested distance.
    private func computeAndApply(pairs: [SegmentPair], state: PlanState) async {
        guard !pairs.isEmpty else { return }
        state.isRouting = true
        state.routingFailureCount = 0
        defer { state.isRouting = false }

        await withTaskGroup(of: PlanSegment?.self) { group in
            var inFlight = 0
            var iterator = pairs.makeIterator()

            // Seed the first 2 tasks (or fewer if pairs.count < 2)
            while inFlight < 2, let pair = iterator.next() {
                let (from, to, isLoop) = (pair.from, pair.to, pair.isLoop)
                group.addTask {
                    await Self.computeSegment(from: from, to: to, isLoop: isLoop)
                }
                inFlight += 1
            }

            // As each task finishes, apply its result and schedule the next pair
            for await segment in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let seg = segment {
                    state.upsertSegment(seg)
                } else {
                    // nil = MKDirections threw for this segment; count for UI warning
                    state.routingFailureCount += 1
                }
                inFlight -= 1

                if let pair = iterator.next() {
                    let (from, to, isLoop) = (pair.from, pair.to, pair.isLoop)
                    group.addTask {
                        await Self.computeSegment(from: from, to: to, isLoop: isLoop)
                    }
                    inFlight += 1
                }
            }
        }

        guard !Task.isCancelled else { return }
        await matchTargetDistance(in: state)
    }

    // MARK: - Distance Matching (F-C3)

    /// If the user requested a target distance, check whether the routed result
    /// is within ±15 %. For loops that are too short, extend by pushing a new
    /// waypoint perpendicular to the loop-closing segment.
    ///
    /// Max 2 extension attempts — each adds one waypoint and re-routes two
    /// segments. If still off after 2 attempts, sets `distanceWarning`.
    private func matchTargetDistance(in state: PlanState) async {
        let target = state.targetDistanceKm
        guard target > 0 else { return }

        for _ in 1...2 {
            let actualKm = state.totalDistance / 1000
            let ratio = actualKm / target

            if ratio >= 0.85 && ratio <= 1.15 {
                state.distanceWarning = nil
                return
            }

            if ratio > 1.15 {
                state.distanceWarning = String(
                    format: "Route is %.1f km (target was %.0f km)",
                    actualKm, target
                )
                return
            }

            // Too short — extend if loop
            guard state.isLoopClosed,
                  let first = state.waypoints.first,
                  let last = state.waypoints.last,
                  first.id != last.id
            else {
                state.distanceWarning = "Add more waypoints to reach \(Int(target)) km."
                return
            }

            let shortfall = (target * 1000) - state.totalDistance
            let pushDistance = min(shortfall / 2, 20_000)  // cap at 20 km per attempt

            let fromCoord = last.coordinate
            let toCoord = first.coordinate
            let mid = fromCoord.midpoint(to: toCoord)
            let b = fromCoord.bearing(to: toCoord)
            let perpBearing = (b + 90).truncatingRemainder(dividingBy: 360)

            let newCoord = mid.destination(bearing: perpBearing, distance: pushDistance)
            let newWP = PlanWaypoint(coordinate: newCoord)

            // Remove old loop segment, append new waypoint
            state.segments.removeAll { $0.isLoop }
            state.waypoints.append(newWP)

            // Route Wn → newWP (non-loop, nonisolated static calls)
            if let seg1 = await Self.computeSegment(from: last, to: newWP, isLoop: false) {
                state.upsertSegment(seg1)
            } else {
                state.routingFailureCount += 1
            }

            // Route newWP → W1 (loop)
            if let seg2 = await Self.computeSegment(from: newWP, to: first, isLoop: true) {
                state.upsertSegment(seg2)
            } else {
                state.routingFailureCount += 1
            }
        }

        // Final check after max attempts
        let finalKm = state.totalDistance / 1000
        let finalRatio = finalKm / target
        if finalRatio < 0.85 || finalRatio > 1.15 {
            state.distanceWarning = String(
                format: "Route is %.1f km (target was %.0f km)",
                finalKm, target
            )
        } else {
            state.distanceWarning = nil
        }
    }

    /// Returns a routed PlanSegment, or nil if MKDirections failed.
    /// Returning nil (instead of a straight-line stub) ensures failures
    /// are visible in the UI rather than silently inflating the total distance.
    private static func computeSegment(
        from: PlanWaypoint,
        to: PlanWaypoint,
        isLoop: Bool
    ) async -> PlanSegment? {
        // Pass raw lat/lon Doubles — calculateRoute no longer accepts CLLocationCoordinate2D
        // directly, since CLLocationCoordinate2D.init is @MainActor on iOS 26+.
        let fLat = from.coordinate.latitude,  fLon = from.coordinate.longitude
        let tLat = to.coordinate.latitude,    tLon = to.coordinate.longitude

        do {
            let result = try await CyclingRouteService.shared.calculateRoute(
                from: fLat, fLon,
                to:   tLat, tLon
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
            // Return nil — no silent straight-line fallback.
            // computeAndApply increments routingFailureCount so the view can warn the user.
            return nil
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

private extension CLLocationCoordinate2D {
    func planDistance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
