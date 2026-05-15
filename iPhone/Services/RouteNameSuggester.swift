//
//  RouteNameSuggester.swift
//  VeloGPX
//
//  F-A2 — On-device route name suggestions.
//  Reverse-geocodes key points along the route (via the existing
//  ReverseGeocodingService), then uses FoundationModels to generate
//  3 short, evocative human-readable route names.
//

import Foundation
import FoundationModels
import CoreLocation

// MARK: - Generable output contract

@Generable
struct RouteNameSuggestions {
    @Guide(description: "Exactly 3 short, evocative cycling route names. Each 3–6 words. No numbering, no punctuation at end.")
    var names: [String]
}

// MARK: - Suggester

struct RouteNameSuggester {

    /// Returns up to 3 suggested names for the given route.
    /// Uses `ReverseGeocodingService.shared` (MK-3, already implemented).
    func suggest(for route: RouteModel) async throws -> [String] {
        let points = sampledCoordinates(from: route)

        // Resolve start + midpoint place names in parallel
        async let startName  = ReverseGeocodingService.shared.reverseGeocode(
            CLLocationCoordinate2D(latitude:  points.first?.latitude  ?? 0,
                                   longitude: points.first?.longitude ?? 0))
        async let midName    = ReverseGeocodingService.shared.reverseGeocode(
            CLLocationCoordinate2D(latitude:  points[points.count / 2].latitude,
                                   longitude: points[points.count / 2].longitude))

        let (start, mid) = try await (startName, midName)

        let session = LanguageModelSession()
        let prompt  = buildPrompt(
            startArea: start ?? "unknown area",
            midArea:   mid   ?? "unknown area",
            route:     route
        )

        let result = try await session.respond(to: prompt, generating: RouteNameSuggestions.self)
        return result.content.names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    /// Returns 5 evenly spaced coordinates from the route's track points.
    private func sampledCoordinates(from route: RouteModel) -> [Coordinate] {
        let pts = route.trackPoints.map(\.coordinate)
        guard pts.count >= 5 else { return pts }
        let step = pts.count / 4
        return stride(from: 0, through: pts.count - 1, by: step).map { pts[$0] }
    }

    private func buildPrompt(startArea: String, midArea: String, route: RouteModel) -> String {
        let distKm = String(format: "%.0f", route.totalDistance / 1000)
        let gainM  = Int(route.elevationGain)
        let isLoop = route.trackPoints.count > 1 &&
            distanceBetween(route.trackPoints.first!.coordinate,
                            route.trackPoints.last!.coordinate) < 500

        return """
        Suggest 3 short, evocative names for a cycling route.
        Start area: \(startArea)
        Midpoint area: \(midArea)
        Distance: \(distKm) km | Elevation gain: \(gainM) m
        \(isLoop ? "This is a loop route." : "")
        Style: use specific place names where possible; add descriptors like Loop, Circuit, Climb, Traverse if apt.
        Each name must be 3–6 words. No numbering. No punctuation at end.
        """
    }

    private func distanceBetween(_ a: Coordinate, _ b: Coordinate) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}
