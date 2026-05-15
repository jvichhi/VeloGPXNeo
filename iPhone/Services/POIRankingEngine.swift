// POIRankingEngine.swift
// VeloGPXNeo — iPhone target ONLY. Never add to Watch target.
//
// PURPOSE:
// Ranks a list of POIs by contextual relevance to the current ride, using a
// multi-signal scoring algorithm powered by the on-device SystemLanguageModel.
// Used by POIDiscoverySheet's "Suggested" sort mode (F-A3).
//
// DESIGN — WHY AN ACTOR:
// POIRankingEngine is declared as an `actor` rather than a struct or class.
// Reasoning:
//   - ranking() is async (it calls FoundationModels).
//   - Multiple POI sheet rebuilds could theoretically trigger concurrent ranking calls.
//   - The `actor` guarantees that only one ranking() call runs at a time on the
//     engine's executor, preventing duplicate model sessions and race conditions.
//   - If you refactor this to a struct in future, make sure all call sites
//     are already serialised (e.g., inside a single .task {} block).
//
// SCORING ALGORITHM:
// Each POI receives a score (higher = more relevant) based on:
//   1. Distance from route (closer = higher base score)
//   2. Ride difficulty context (elevation gain → cafes score higher on hard rides;
//      scenic overlooks score higher on moderate rides)
//   3. Category fit (restrooms/water always rank highly; shops less so mid-ride)
//   4. Time of day (cafes rank highest in morning; restaurants in afternoon/evening)
// The AI is used to generate a human-readable "reason" string per POI
// (e.g., "Good rest stop — 2 km ahead, mostly downhill"), NOT for the numeric
// scoring itself (which is deterministic). This keeps ranking fast and predictable
// while the reason text adds value in the UI.
//
// WHY WE DON'T USE @available(iOS 26, *):
// The project deployment target is iOS 26. That annotation is redundant.
// See PROJECT.md: "Do not add @available(iOS 26, *) scaffolding 'just in case'."
// The `actor` keyword and the FoundationModels calls are both iOS 26 APIs and
// are always available at our minimum deployment target.
//
// DEPRECATED PATTERNS TO AVOID:
// ❌ CLGeocoder — use MKReverseGeocodingRequest (iOS 18+)
// ❌ session.stream(from:onPartial:) — removed in iOS 26 beta
// ❌ Holding a LanguageModelSession as a stored property — sessions accumulate context
// ✅ session.respond(to:) for plain String output
// ✅ Create a fresh session per ranking() call

import Foundation
import CoreLocation
import FoundationModels

/// Context-aware POI ranking engine.
///
/// Call `ranking(pois:context:)` to get a sorted, annotated list of POIs
/// with AI-generated relevance reasons.
///
/// `actor` isolation ensures concurrent calls are serialised — only one
/// FoundationModels session runs at a time on this engine's executor.
actor POIRankingEngine {

    // MARK: - Public API

    /// Ranks the given POIs by contextual relevance to the current ride context.
    ///
    /// - Parameters:
    ///   - pois: The unordered list of POIs to rank.
    ///   - context: Ride context (distance covered, elevation gain, current time, etc.).
    ///              Used to determine what kinds of stops are most relevant right now.
    /// - Returns: The same POIs sorted by descending relevance score, each annotated
    ///   with a human-readable `reason` string from the model.
    func ranking(pois: [POIModel], context: RideContext) async throws -> [RankedPOI] {
        guard !pois.isEmpty else { return [] }

        // Step 1: Compute deterministic scores for all POIs.
        // This does NOT call the model — it's a fast, predictable algorithm.
        // The model is only called in Step 2 to generate reason strings.
        let scored = pois.map { poi in
            ScoredPOI(poi: poi, score: computeScore(for: poi, context: context))
        }.sorted { $0.score > $1.score }

        // Step 2: Generate reason strings for the top N POIs using the model.
        // We only generate reasons for the top 5 — users rarely scroll past that.
        // Generating reasons for all POIs would be slow and wasteful.
        let topN = Array(scored.prefix(5))
        let reasons = try await generateReasons(for: topN, context: context)

        // Step 3: Assemble the final RankedPOI list.
        // POIs beyond top 5 get a generic reason based on their category.
        return scored.enumerated().map { idx, sp in
            let reason = idx < reasons.count
                ? reasons[idx]
                : genericReason(for: sp.poi)
            return RankedPOI(poi: sp.poi, score: sp.score, reason: reason)
        }
    }

    // MARK: - Scoring

    /// Computes a deterministic relevance score for a POI given the current ride context.
    ///
    /// Score is a Float in [0, 1]. Higher = more relevant.
    /// Factors and weights:
    ///   - Distance from nearest route point: up to 0.40 (closer = higher)
    ///   - Category fit for current ride phase: up to 0.30
    ///   - Time-of-day fit: up to 0.20
    ///   - Elevation context: up to 0.10 (hard climbs → rest stops rank higher)
    private func computeScore(for poi: POIModel, context: RideContext) -> Float {
        var score: Float = 0

        // --- Distance score (0–0.40) ---
        // Linear decay: 0 m away = 0.40, 2000 m away = 0.0. Clipped at 2 km.
        if let dist = poi.distanceFromRoute {
            let proximity = max(0, 1 - Float(dist) / 2000)
            score += proximity * 0.40
        }

        // --- Category fit (0–0.30) ---
        // Cafes/water/restrooms are always high priority mid-ride.
        // Food/restaurants score higher when > 70% of planned distance is done.
        score += categoryFitScore(for: poi, context: context) * 0.30

        // --- Time-of-day fit (0–0.20) ---
        // Cafes peak in the morning (6–10am). Restaurants peak in the afternoon (12–2pm, 6–8pm).
        // Scenic viewpoints are always relevant but peak on weekend mornings.
        score += timeOfDayScore(for: poi, context: context) * 0.20

        // --- Elevation context (0–0.10) ---
        // On rides with > 500 m gain, rest/water stops rank higher.
        if context.totalElevationGain > 500 {
            let isRestStop = poi.category == .cafe || poi.category == .water
            score += isRestStop ? 0.10 : 0.05
        }

        return min(score, 1.0)
    }

    private func categoryFitScore(for poi: POIModel, context: RideContext) -> Float {
        switch poi.category {
        case .water, .restroom:  return 1.0  // Always high priority
        case .cafe:              return context.completionRatio < 0.7 ? 0.9 : 0.6
        case .restaurant:        return context.completionRatio > 0.7 ? 0.9 : 0.4
        case .bikeshop:          return 0.7  // Useful any time
        case .scenic:            return 0.6
        default:                 return 0.3
        }
    }

    private func timeOfDayScore(for poi: POIModel, context: RideContext) -> Float {
        let hour = Calendar.current.component(.hour, from: context.currentTime)
        switch poi.category {
        case .cafe:
            // Peak: 6am–10am (morning ride coffee)
            return (6...10).contains(hour) ? 1.0 : 0.4
        case .restaurant:
            // Peak: 12pm–2pm or 6pm–8pm (lunch/dinner stops)
            return ((12...14).contains(hour) || (18...20).contains(hour)) ? 1.0 : 0.3
        case .scenic:
            // Weekend mornings are best for scenic stops
            let isWeekend = [1, 7].contains(Calendar.current.component(.weekday, from: context.currentTime))
            return (isWeekend && (7...11).contains(hour)) ? 1.0 : 0.6
        default:
            return 0.5  // Neutral for categories without strong time preference
        }
    }

    // MARK: - AI Reason Generation

    /// Uses the language model to generate a short, human-readable reason string
    /// for each of the top-scored POIs.
    ///
    /// Each reason is 8–12 words describing why this POI is a good stop right now
    /// (e.g., "Good rest stop — 1.2 km ahead, mostly flat").
    private func generateReasons(for pois: [ScoredPOI], context: RideContext) async throws -> [String] {
        guard !pois.isEmpty else { return [] }

        // Build a single prompt covering all top POIs.
        // One session call for N reasons is faster than N separate session calls.
        let prompt = buildReasonsPrompt(pois: pois, context: context)

        // Fresh session per ranking call — do not hold sessions between calls.
        let session = VeloAI.makeSession()
        let response = try await session.respond(to: prompt)

        // Parse: one reason per line, matching the order of the input POIs.
        return response.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(pois.count)
            .map { String($0) }
    }

    private func buildReasonsPrompt(pois: [ScoredPOI], context: RideContext) -> String {
        let distCovered = String(format: "%.1f", context.distanceCovered / 1000)
        let elevGain    = String(format: "%.0f", context.totalElevationGain)

        let poiLines = pois.enumerated().map { idx, sp in
            let distStr = sp.poi.distanceFromRoute.map { String(format: "%.0f m away", $0) } ?? "nearby"
            return "\(idx + 1). \(sp.poi.name) (\(sp.poi.category.rawValue), \(distStr))"
        }.joined(separator: "\n")

        return """
        You are a cycling coach suggesting rest stops during a ride.
        For each POI below, write one short reason (8-12 words) why it's a good stop right now.
        Rules: one reason per line, no numbering, no extra text.
        Current ride: \(distCovered) km covered, \(elevGain) m elevation gained.
        POIs:
        \(poiLines)
        """
    }

    /// Returns a generic reason string for a POI when the model wasn't asked about it.
    private func genericReason(for poi: POIModel) -> String {
        switch poi.category {
        case .water:      return "Water stop along your route."
        case .restroom:   return "Restroom available nearby."
        case .cafe:       return "Cafe stop — good for a quick break."
        case .restaurant: return "Restaurant for a longer stop."
        case .scenic:     return "Scenic viewpoint worth a pause."
        case .bikeshop:   return "Bike shop nearby if you need anything."
        default:          return "Point of interest along your route."
        }
    }

    // MARK: - Supporting Types

    /// Internal scored POI before reason generation.
    private struct ScoredPOI {
        let poi: POIModel
        let score: Float
    }
}

// MARK: - Supporting Types

/// A POI with a relevance score and AI-generated reason, ready for display.
struct RankedPOI {
    let poi: POIModel
    /// Relevance score in [0, 1]. Higher = more relevant to current ride context.
    let score: Float
    /// Short human-readable reason why this POI is relevant right now.
    /// Displayed as a subtitle under the POI name in POIDiscoverySheet.
    let reason: String
}

/// Ride context passed to `POIRankingEngine.ranking(pois:context:)`.
/// Captures the current state of the ride for scoring purposes.
struct RideContext {
    /// How far the rider has travelled so far, in metres.
    let distanceCovered: Double
    /// Total elevation gain so far, in metres.
    let totalElevationGain: Double
    /// Ratio of distance covered to total planned distance (0.0–1.0).
    /// Used to determine if we're early, mid, or late in the ride.
    let completionRatio: Double
    /// Current wall-clock time. Used for time-of-day scoring.
    let currentTime: Date
}
