//
//  RouteNameSuggester.swift
//  VeloGPX
//
//  F-A2 — Smart Route Naming.
//  Deployment target: iOS 26. No @available guards needed.
//  CLGeocoder replaced with MKReverseGeocodingRequest.
//  Locality from MKAddress.shortAddress (only fields: shortAddress, fullAddress).
//

import Foundation
import FoundationModels
import CoreLocation
import MapKit

struct RouteNameSuggester {

    // MARK: - Public API

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

        return response.content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Private helpers

    private func sampledPoints(from route: RouteModel) -> [Coordinate] {
        let count = route.trackPoints.count
        guard count > 0 else { return [] }
        let step = max(1, count / 5)
        return stride(from: 0, to: count, by: step).map { route.trackPoints[$0].coordinate }
    }

    /// Reverse-geocodes a Coordinate using MKReverseGeocodingRequest.
    /// MKAddress only exposes shortAddress and fullAddress — no locality/subLocality members.
    private func geocodeName(_ coord: Coordinate?) async -> String? {
        guard let coord else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let items = try? await request.mapItems,
              let first = items.first else { return nil }
        // Prefer the item name (e.g. neighbourhood/district); fall back to short address
        return first.name ?? first.address?.shortAddress
    }
}
