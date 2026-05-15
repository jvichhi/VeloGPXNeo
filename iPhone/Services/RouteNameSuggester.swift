// RouteNameSuggester.swift
// VeloGPXNeo — iPhone target ONLY. Never add to Watch target.
//
// PURPOSE:
// Given a RouteModel, produces 3 short, human-friendly route name suggestions
// using on-device FoundationModels (SystemLanguageModel). These suggestions are
// displayed as tappable pills in RouteRenameSheet (RouteLibraryView.swift).
//
// FLOW:
//   RouteRenameSheet
//     └─ .task { await fetchSuggestions() }
//           └─ RouteNameSuggester().suggest(for: route)
//                 ├─ geocodeStartName()      ← MKReverseGeocodingRequest (NOT CLGeocoder)
//                 ├─ buildPrompt()           ← assembles context string
//                 └─ session.respond(to:)    ← plain String → parse 3 lines
//
// WHY MKReverseGeocodingRequest, NOT CLGeocoder:
// CLGeocoder is deprecated on iOS 18+ (PROJECT.md rule MK-3).
// MKReverseGeocodingRequest is the MapKit-native replacement introduced in iOS 18.
// It uses structured concurrency (async/await) with no completion handler.
// API: guard let request = MKReverseGeocodingRequest(location: CLLocation) (failable init)
//      try await request.mapItems → [MKMapItem]
//
// iOS 26 ADDRESS API:
// mapItem.placemark is deprecated in iOS 26. Use the new address APIs instead:
//   mapItem.addressRepresentations?.cityName        → "Montréal" (preferred)
//   mapItem.addressRepresentations?.cityWithContext  → "Montréal, QC"
//   mapItem.address?.shortAddress                   → "Montréal, QC"
//   mapItem.name                                    → last resort (may be street address)
//   mapItem.address?.fullAddress                    → full formatted address string
// Note: MKAddress does NOT have subLocality or locality — those were CLPlacemark properties.
//
// WHY session.respond(to:) and NOT session.generate(from:):
// respond(to:) takes a plain String prompt and returns a plain String.
// generate(from:) takes a @Generable schema and returns a structured type.
// We want plain text names (not structured data), so respond(to:) is correct here.
//
// DEPRECATIONS TO AVOID:
// ❌ CLGeocoder — deprecated iOS 18+
// ❌ mapItem.placemark — deprecated iOS 26, use .address and .addressRepresentations
// ❌ session.stream(from:onPartial:) — removed in iOS 26 beta
// ✅ guard let request = MKReverseGeocodingRequest(location:) — failable init
// ✅ try await request.mapItems — async throws on unwrapped request
// ✅ mapItem.addressRepresentations?.cityName — iOS 26 API
// ✅ session.respond(to: prompt) — correct for plain String output

import Foundation
import MapKit
import FoundationModels

/// Generates 3 short, human-friendly name suggestions for a cycling route
/// using the on-device `SystemLanguageModel`.
///
/// Always check `VeloAI.isAvailable` before instantiating this type.
/// This type is not an `actor` — it is a plain `struct` with no mutable state.
/// Each `suggest(for:)` call is self-contained; parallel calls are safe.
struct RouteNameSuggester {

    // MARK: - Public API

    /// Generates 3 route name suggestions for the given route.
    ///
    /// - Parameter route: The route to name. Uses `trackPoints`, `totalDistance`,
    ///   `elevationGain`, and `sourceFormat` for context.
    /// - Returns: An array of exactly 3 (or fewer, if the model returns fewer) name strings.
    /// - Throws: `LanguageModelError` if the session fails, or any error from geocoding.
    func suggest(for route: RouteModel) async throws -> [String] {
        let locationName = await geocodeStartName(for: route)
        let prompt = buildPrompt(route: route, locationName: locationName)
        let session = VeloAI.makeSession()
        let response = try await session.respond(to: prompt)
        return parseNames(from: response.content)
    }

    // MARK: - Private Helpers

    /// Reverse-geocodes the first trackpoint of the route to get a human-readable location name.
    ///
    /// Uses `MKReverseGeocodingRequest` (iOS 18+ API).
    /// Priority chain for location name (all iOS 26 non-deprecated):
    ///   1. addressRepresentations?.cityName        — clean city name, best for route names
    ///   2. addressRepresentations?.cityWithContext  — "City, Region" fallback
    ///   3. address?.shortAddress                   — "City, Region" via MKAddress
    ///   4. name                                    — last resort, may be a street address
    private func geocodeStartName(for route: RouteModel) async -> String? {
        guard let first = route.trackPoints.first else { return nil }

        let location = CLLocation(
            latitude: first.coordinate.latitude,
            longitude: first.coordinate.longitude
        )

        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let mapItem = try? await request.mapItems.first else { return nil }

        return mapItem.addressRepresentations?.cityName
            ?? mapItem.addressRepresentations?.cityWithContext
            ?? mapItem.address?.shortAddress
            ?? mapItem.name
    }

    /// Builds the prompt string sent to the language model.
    private func buildPrompt(route: RouteModel, locationName: String?) -> String {
        let distKm     = String(format: "%.1f", route.totalDistance / 1000)
        let elevGain   = String(format: "%.0f", route.elevationGain)
        let formatHint = route.sourceFormat == .planned ? "planned route" : "imported GPX route"

        var context = "Cycling \(formatHint), \(distKm) km, \(elevGain) m elevation gain"
        if let place = locationName {
            context += ", starting near \(place)"
        }

        return """
        You are a cycling route naming assistant.
        Generate exactly 3 short, evocative names for this cycling route.
        Rules:
        - One name per line, no numbering, no bullet points, no extra text.
        - Each name should be 2–5 words.
        - Names should feel natural to a cyclist (e.g., "River Valley Loop", "Morning Climb", "Ridgeline Out-and-Back").
        Route: \(context)
        """
    }

    /// Parses the model's plain-text response into an array of name strings.
    private func parseNames(from response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line -> String in
                line.replacingOccurrences(
                    of: #"^\d+[.)\s]+"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }
}
