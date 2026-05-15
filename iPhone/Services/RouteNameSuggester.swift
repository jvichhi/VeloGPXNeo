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
// API: MKReverseGeocodingRequest(coordinate:) → await req.response → .placemark.locality
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
// ✅ MKReverseGeocodingRequest(coordinate: coord) + await req.response
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
        // This enriches the prompt so the model can produce geographically relevant names.
        // Uses MKReverseGeocodingRequest — the iOS 18+ replacement for deprecated CLGeocoder.
        let locationName = await geocodeStartName(for: route)

        // Step 2: Build the prompt string.
        // The prompt is tightly scoped: "3 short cycling route names, one per line, no numbering."
        // Tight scoping prevents the model from producing explanations, disclaimers, or markdown.
        let prompt = buildPrompt(route: route, locationName: locationName)

        // Step 3: Create a fresh session and call respond(to:).
        // Sessions are lightweight — create one per request, don't cache them.
        // respond(to:) returns a plain String (the model's full response).
        let session = VeloAI.makeSession()
        let response = try await session.respond(to: prompt)

        // Step 4: Parse the response into individual name strings.
        // The model is instructed to return one name per line with no numbering.
        // We split on newlines, trim whitespace, and take up to 3 non-empty results.
        return parseNames(from: response.content)
    }

    // MARK: - Private Helpers

    /// Reverse-geocodes the first trackpoint of the route to get a human-readable location name.
    ///
    /// Uses `MKReverseGeocodingRequest` (iOS 18+ API, required by PROJECT.md).
    /// Falls back to `nil` gracefully — the prompt still works without a location name,
    /// it just produces slightly more generic suggestions.
    ///
    /// - Parameter route: The route whose start coordinate to geocode.
    /// - Returns: A locality/neighbourhood string, or `nil` if geocoding fails or the route is empty.
    private func geocodeStartName(for route: RouteModel) async -> String? {
        // Guard: route must have at least one trackpoint to geocode.
        guard let first = route.trackPoints.first else { return nil }

        let coord = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)

        // MKReverseGeocodingRequest — iOS 18+ structured-concurrency geocoding.
        // Returns MKReverseGeocodingResponse with a .placemark property.
        // .locality = city name (e.g., "Montreal")
        // .subLocality = neighbourhood (e.g., "Plateau-Mont-Royal") — more specific, prefer it.
        let request = MKReverseGeocodingRequest(coordinate: coord)
        guard let result = try? await request.response else { return nil }
        return result.placemark.subLocality ?? result.placemark.locality
    }

    /// Builds the prompt string sent to the language model.
    ///
    /// Prompt design principles:
    /// - Be explicit about format ("one per line", "no numbering") to avoid markdown/lists.
    /// - Include concrete numeric context (distance, elevation) so the model can produce
    ///   names that reflect ride character ("Epic Climb" vs. "Evening Spin").
    /// - Keep the prompt short — on-device models have context window limits and
    ///   shorter prompts produce faster, more focused responses.
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
    ///
    /// The model is instructed to return one name per line with no numbering.
    /// This parser is defensive: it trims whitespace, filters blank lines,
    /// and strips any accidental leading numbers ("1. ", "1) ").
    private func parseNames(from response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Strip accidental numbering like "1. " or "1) "
            .map { line -> String in
                let stripped = line.replacingOccurrences(
                    of: #"^\d+[.)\s]+"#,
                    with: "",
                    options: .regularExpression
                )
                return stripped
            }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }
    }
}
