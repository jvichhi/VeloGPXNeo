//
//  RideSessionStore+Spurs.swift
//  VeloGPX
//
//  Computes POISpur values for every visible POI.
//  Called from RideView on each location update and whenever nextPOI changes.
//
//  F-2e: Spur inbound line now originates from nearest route track point → POI,
//        not from the rider's live position → POI. Eliminates the rubber-band wiggle.
//  F-2f: Proximity gate — spurs only rendered when ≤500 m along-route from the
//        POI's track snap point. Approach alert in RideSessionStore stays at 200 m.

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

            // Find the nearest track point to the POI within a window around the rider
            var snapIdx  = riderIdx
            var snapDist = poiCoord.distance(to: trackPoints[riderIdx].coordinate.clCoordinate)
            let searchRange = max(0, riderIdx - 20)...min(trackPoints.count - 1, riderIdx + 40)
            for i in searchRange {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < snapDist { snapDist = d; snapIdx = i }
            }

            // F-2f: Only render spur if POI snap point is ≤500 m along-route ahead of rider
            guard snapIdx >= riderIdx else { return nil }  // POI already passed
            let alongRoute = trackArcDistance(from: riderIdx, to: snapIdx, points: trackPoints)
            guard alongRoute <= 500 else { return nil }

            let snapCoord = trackPoints[snapIdx].coordinate.clCoordinate
            let isNext    = poi.id == rideState.nextPOI?.id

            // F-2e: inbound originates from route snap point, not rider position
            return POISpur(
                id:       poi.id,
                inbound:  [snapCoord, poiCoord],   // static route-anchored line
                outbound: [poiCoord, snapCoord],   // return leg (unchanged geometry)
                isNext:   isNext
            )
        }
    }
}
