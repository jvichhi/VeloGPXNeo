//
//  POISpur.swift
//  VeloGPX
//
//  A pair of dashed polylines rendered on the map for each POI:
//    • inbound  — nearest route snap point → POI (green dashed when resolved)
//    • outbound — POI → re-entry point ahead on GPX track (red dashed when resolved)
//
//  When isPending == true both arrays hold a straight-line fallback and the
//  map layer renders them thin and grey while CyclingRouteService computes
//  the real road-snapped geometry.
//
//  Produced by RideSessionStore+Spurs and consumed by RideView.

import Foundation
import CoreLocation

struct POISpur: Identifiable {
    /// Matches the source POI so RideView can key ForEach without extra lookup.
    let id: UUID

    /// Road-snapped (or straight-line fallback) from route snap point → POI.
    let inbound: [CLLocationCoordinate2D]

    /// Road-snapped (or straight-line fallback) from POI → re-entry point ahead on track.
    let outbound: [CLLocationCoordinate2D]

    /// True when this spur belongs to rideState.nextPOI.
    let isNext: Bool

    /// True while CyclingRouteService is still computing; map renders a thin grey placeholder.
    let isPending: Bool

    /// Routed distance (m) from snap point to POI — 0 while pending.
    let inboundDistance: CLLocationDistance

    /// Routed distance (m) from POI back to re-entry track point — 0 while pending.
    let outboundDistance: CLLocationDistance
}
