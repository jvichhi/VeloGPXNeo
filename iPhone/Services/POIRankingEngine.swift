//
//  POIRankingEngine.swift
//  VeloGPX
//
//  F-A3 — POI Relevance Ranking.
//  Ranks a list of `POIModel` items by predicted relevance to the current
//  ride context using an on-device FoundationModels session.
//
//  Usage:
//    let ranked = await POIRankingEngine.shared.rank(pois, context: context)
//
//  Note: @available(iOS 26,*) removed from the actor — deployment target is iOS 26 (PROJECT.md).
//

import Foundation
import FoundationModels

// MARK: - Ride Context

/// Snapshot of the current ride state passed to the ranking engine.
struct RideContext {
    /// Overall route difficulty label.
    var difficulty: String          // e.g. "moderate", "hard"
    /// Total elevation gain on the full route (metres).
    var elevationGain: Double
    /// Distance covered so far in the current ride (metres).
    var distanceSoFar: Double
    /// Current time-of-day bucket for food/rest relevance.
    var timeOfDay: TimeOfDay
    /// How many rides the user has on record (used for confidence gate).
    var historyCount: Int

    enum TimeOfDay: String {
        case morning, midday, afternoon, evening

        static var current: TimeOfDay {
            let h = Calendar.current.component(.hour, from: Date())
            switch h {
            case 5..<12:  return .morning
            case 12..<14: return .midday
            case 14..<18: return .afternoon
            default:      return .evening
            }
        }
    }
}

// MARK: - Ranked POI

/// A `POIModel` paired with a relevance score and a human-readable reason.
struct RankedPOI: Identifiable {
    let poi: POIModel
    /// Relevance score 0.0–1.0 (higher = more relevant).
    let score: Double
    /// One short sentence explaining why this POI is suggested.
    let reason: String

    var id: UUID { poi.id }
}

// MARK: - Engine

actor POIRankingEngine {

    static let shared = POIRankingEngine()

    // MARK: - Public API

    /// Ranks `pois` by relevance to `context` and returns them sorted
    /// highest-score first, each wrapped in a `RankedPOI`.
    ///
    /// Falls back to distance-sorted order if the model fails.
    func rank(_ pois: [POIModel], context: RideContext) async -> [RankedPOI] {
        guard !pois.isEmpty else { return [] }

        do {
            return try await rankWithModel(pois, context: context)
        } catch {
            // Silent fallback — keep distance order, neutral reason
            return pois.map { RankedPOI(poi: $0, score: 0.5, reason: "Nearby stop") }
        }
    }

    // MARK: - Private

    private func rankWithModel(_ pois: [POIModel],
                               context: RideContext) async throws -> [RankedPOI] {
        let poiList = pois.enumerated().map { i, p in
            "\(i). \(p.name) (\(p.category.rawValue))"
        }.joined(separator: "\n")

        let prompt = """
        You are ranking cycling POIs by relevance for a rider.
        Ride context:
        - Difficulty: \(context.difficulty)
        - Elevation gain: \(Int(context.elevationGain)) m
        - Distance so far: \(String(format: "%.1f", context.distanceSoFar / 1000)) km
        - Time of day: \(context.timeOfDay.rawValue)

        POIs (index. name category):
        \(poiList)

        For each POI output one line:
        <index>|<score 0.0-1.0>|<one short reason, max 8 words>
        Output all \(pois.count) lines. No extra text.
        """

        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)

        // Parse model output
        var ranked: [RankedPOI] = []
        for line in response.content.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let idx   = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let score = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                  idx >= 0, idx < pois.count
            else { continue }
            let reason = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            ranked.append(RankedPOI(poi: pois[idx], score: score, reason: reason))
        }

        // If parsing yielded fewer results than expected, fill missing with neutral
        if ranked.count < pois.count {
            let rankedIDs = Set(ranked.map { $0.poi.id })
            let missing = pois.filter { !rankedIDs.contains($0.id) }
            ranked += missing.map { RankedPOI(poi: $0, score: 0.5, reason: "Nearby stop") }
        }

        return ranked.sorted { $0.score > $1.score }
    }
}
