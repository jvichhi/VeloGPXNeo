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
// API: MKReverseGeocodingRequest(location: CLLocation) is a failable init returning
// MKReverseGeocodingRequest? — always guard/if-let before calling .mapItems.
// .mapItems is async throws — returns [MKMapItem].
//
// WHY session.respond(to:) and NOT session.generate(from:):
// respond(to:) takes a plain String prompt and returns a plain String.
// generate(from:) takes a @Generable schema and returns a structured type.
// We want plain text names (not structured data), so respond(to:) is correct here.
// Sprint 3's PlanAssistantEngine will use generate(from:) for RidePlanIntent.
//
// DEPRECATIONS TO AVOID:
// ❌ CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in ... }
//    — completion-handler style, deprecated iOS 18+. Never use.
// ❌ CLGeocoder().reverseGeocodeLocation(_:) async — still CLGeocoder, still deprecated.
// ✅ guard let request = MKReverseGeocodingRequest(location: CLLocation) — failable init
// ✅ try await request.mapItems.first — async throws, unwrapped request
// ❌ session.stream(from:onPartial:) — removed in iOS 26 beta.
// ✅ session.respond(to: prompt) — correct for plain String output.
//
// ERROR HANDLING:
// suggest(for:) throws. The caller (RouteRenameSheet.fetchSuggestions) catches and
// sets suggestionState = .failed("..."). The user can tap Retry.
// FoundationModels throws LanguageModelError on model unavailability, prompt rejection,
// or safety filtering. We propagate the error without wrapping so the caller can inspect.

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
        // Step 1: Geocode the route's start coordinate to get a location name.
        // Uses MKReverseGeocodingRequest — the iOS 18+ replacement for deprecated CLGeocoder.
        let locationName = await geocodeStartName(for: route)

        // Step 2: Build the prompt string.
        let prompt = buildPrompt(route: route, locationName: locationName)

        // Step 3: Create a fresh session and call respond(to:).
        let session = VeloAI.makeSession()
        let response = try await session.respond(to: prompt)

        // Step 4: Parse the response into individual name strings.
        return parseNames(from: response.content)
    }

    // MARK: - Private Helpers

    /// Reverse-geocodes the first trackpoint of the route to get a human-readable location name.
    ///
    /// Uses `MKReverseGeocodingRequest` (iOS 18+ API, required by PROJECT.md).
    /// NOTE: MKReverseGeocodingRequest(location:) is a failable initialiser — it returns
    /// MKReverseGeocodingRequest? and must be unwrapped before calling .mapItems.
    /// Falls back to `nil` gracefully on empty route or geocoding failure.
    private func geocodeStartName(for route: RouteModel) async -> String? {
        guard let first = route.trackPoints.first else { return nil }

        let location = CLLocation(
            latitude: first.coordinate.latitude,
            longitude: first.coordinate.longitude
        )

        // MKReverseGeocodingRequest(location:) is failable — guard-unwrap before use.
        // .mapItems is async throws — returns [MKMapItem].
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let mapItem = try? await request.mapItems.first else { return nil }
        return mapItem.placemark.subLocality ?? mapItem.placemark.locality
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
