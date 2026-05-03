//
//  RideSessionStore+Spurs.swift
//  VeloGPX
//
//  Computes POISpur values for every visible POI.
//  Called from RideView on each location update and whenever nextPOI changes.
//
//  F-2e: Spur inbound line originates from nearest route track point → POI,
//        not from the rider's live position → POI.
//  F-2f: Proximity gate — spurs only rendered when ≤500 m along-route from
//        the POI's track snap point. Approach alert stays at 200 m.
//  Fix:  Snap search window widened to riderIdx+80 (≈800 m at typical
//        10 m/pt GPX density) so it safely covers the 500 m gate.
//        Previous window of riderIdx±40 (≈400 m) was narrower than the
//        gate, making POIs 400–500 m ahead invisible to computeSpurs().

import Foundation
import CoreLocation

extension RideSessionStore {

    /// Build one POISpur per POI that is within 500 m along-route of the rider.
    /// Returns an empty array when no route or no POIs are active.
    func computeSpurs() async -> [POISpur] {
        guard
            let route,
            rideState.currentCoordinate != nil,
            !pois.isEmpty
        else { return [] }

        let trackPoints = route.trackPoints
        guard trackPoints.count > 1 else { return [] }

        let riderIdx = nearestTrackIndex

        return pois.compactMap { poi in
            let poiCoord = poi.coordinate.clCoordinate

            // Snap search window: riderIdx to riderIdx+80.
            // 80 points × ~10 m/pt = ~800 m lookahead, safely beyond the
            // 500 m proximity gate so no POI inside the gate is missed.
            var snapIdx  = riderIdx
            var snapDist = poiCoord.distance(to: trackPoints[riderIdx].coordinate.clCoordinate)
            let windowEnd = min(trackPoints.count - 1, riderIdx + 80)
            let searchRange = riderIdx...windowEnd
            for i in searchRange {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < snapDist { snapDist = d; snapIdx = i }
            }

            // F-2f: Only render spur if POI snap point is ≤500 m along-route ahead of rider.
            guard snapIdx >= riderIdx else { return nil }  // POI already passed
            let alongRoute = trackArcDistance(from: riderIdx, to: snapIdx, points: trackPoints)
            guard alongRoute <= 500 else { return nil }

            let snapCoord = trackPoints[snapIdx].coordinate.clCoordinate
            let isNext    = poi.id == rideState.nextPOI?.id

            // F-2e: inbound originates from route snap point, not rider position.
            return POISpur(
                id:       poi.id,
                inbound:  [snapCoord, poiCoord],
                outbound: [poiCoord, snapCoord],
                isNext:   isNext
            )
        }
    }
}
