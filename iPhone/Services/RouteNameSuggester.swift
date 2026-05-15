//
//  RouteNameSuggester.swift
//  VeloGPX
//
//  F-A2 — Smart Route Naming.
//  Suggests three short, evocative cycling route names using an on-device
//  FoundationModels session seeded with reverse-geocoded place names from
//  the route's start and midpoint.
//
//  Note: @available(iOS 26,*) removed — deployment target is iOS 26 (PROJECT.md).
//  Note: CLGeocoder replaced with MKReverseGeocodingRequest (iOS 18+ API, PROJECT.md rule).
//

import Foundation
import FoundationModels
import CoreLocation
import MapKit

struct RouteNameSuggester {

    // MARK: - Public API

    /// Returns up to 3 suggested route names for `route`.
    /// Throws if the language model session fails.
    func suggest(for route: RouteModel) async throws -> [String] {
        let points = sampledPoints(from: route)

        let startName  = await geocodeName(points.first)
        let middleName = await geocodeName(points.count > 1 ? points[points.count / 2] : nil)

        let distKm = String(format: "%.0f", route.totalDistance / 1000)
        let gainM  = Int(route.elevationGain)

        let prompt = """
        Suggest 3 short, evocative names for a cycling route.
        Start area: \(startName ?? "unknown")
        Midpoint area: \(middleName ?? "unknown")
        Distance: \(distKm) km | Elevation gain: \(gainM) m
        Style: specific place names, use words like loop/circuit/climb/ridge if applicable.
        Length: 3 to 6 words max per name. No numbering. No punctuation at end.
        Return exactly 3 names, one per line.
        """

        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)

        let names = response.content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(names.prefix(3))
    }

    // MARK: - Private helpers

    /// Returns up to 5 evenly-spaced coordinates from the route's track points.
    private func sampledPoints(from route: RouteModel) -> [Coordinate] {
        let count = route.trackPoints.count
        guard count > 0 else { return [] }
        let step = max(1, count / 5)
        return stride(from: 0, to: count, by: step).map { route.trackPoints[$0].coordinate }
    }

    /// Reverse-geocodes a `Coordinate` to a locality/subLocality string using
    /// MKReverseGeocodingRequest (CLGeocoder is deprecated on iOS 18+).
    /// Returns `nil` silently on failure — names degrade gracefully.
    private func geocodeName(_ coord: Coordinate?) async -> String? {
        guard let coord else { return nil }
        let clCoord = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        let request = MKReverseGeocodingRequest(coordinate: clCoord)
        guard let result = try? await request.response else { return nil }
        return result.placemark.locality ?? result.placemark.subLocality
    }
}
