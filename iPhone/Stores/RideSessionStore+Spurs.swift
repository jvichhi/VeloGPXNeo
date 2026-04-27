//
//  RideSessionStore+Spurs.swift
//  VeloGPX
//
//  Computes POISpur values for every visible POI.
//  Called from RideView on each location update and whenever nextPOI changes.

import Foundation
import CoreLocation

extension RideSessionStore {

    /// Build one POISpur per POI that is within 2 km of the rider.
    /// Returns an empty array when no route or no POIs are active.
    func computeSpurs() async -> [POISpur] {
        guard
            let route,
            let currentCoord = rideState.currentCoordinate?.clCoordinate,
            !pois.isEmpty
        else { return [] }

        let trackPoints = route.trackPoints
        guard trackPoints.count > 1 else { return [] }

        return pois.compactMap { poi in
            let poiCoord = poi.coordinate.clCoordinate

            // Only show spurs for POIs within 2 km
            let dist = currentCoord.distance(to: poiCoord)
            guard dist < 2000 else { return nil }

            // Find the nearest track point to snap the outbound leg back to the route
            var nearestCoord = trackPoints[nearestTrackIndex].coordinate.clCoordinate
            var nearestDist  = poiCoord.distance(to: nearestCoord)
            let searchRange  = max(0, nearestTrackIndex - 20)...min(trackPoints.count - 1, nearestTrackIndex + 40)
            for i in searchRange {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < nearestDist { nearestDist = d; nearestCoord = trackPoints[i].coordinate.clCoordinate }
            }

            let isNext = poi.id == rideState.nextPOI?.id

            return POISpur(
                id: poi.id,
                inbound:  [currentCoord, poiCoord],
                outbound: [poiCoord, nearestCoord],
                isNext:   isNext
            )
        }
    }
}
