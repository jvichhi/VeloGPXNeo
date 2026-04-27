//
//  POISpur.swift
//  VeloGPX
//
//  A pair of dashed polylines rendered on the map for each POI:
//    • inbound  — rider's current location → POI (green dashed)
//    • outbound — POI → nearest point back on the GPX track (red dashed)
//
//  Produced by RideSessionStore.computeSpurs() and consumed by RideView.

import Foundation
import CoreLocation

struct POISpur: Identifiable {
    /// Matches the source POI so RideView can key ForEach without extra lookup.
    let id: UUID
    /// Straight line from rider position to the POI.
    let inbound: [CLLocationCoordinate2D]
    /// Straight line from POI back to the nearest track coordinate.
    let outbound: [CLLocationCoordinate2D]
    /// True when this spur belongs to rideState.nextPOI.
    let isNext: Bool
}
