//
//  POIRankingEngine.swift
//  VeloGPX
//
//  F-A3 — On-device POI relevance ranking.
//  Given a list of POIs and the current ride context, returns them sorted
//  by predicted relevance with a short reason string for each.
//
//  Uses a plain text prompt (not @Generable) because the model is classifying
//  and ordering *existing* objects — structured generation is for creating new
//  typed values, not ranking input data.
//

import Foundation
import FoundationModels
import MapKit

// MARK: - Ride context

/// Snapshot of the current ride state passed to the ranking engine.
struct RideContext {
    let routeName:        String
    let difficulty:       String      // "easy" | "moderate" | "hard" | "epic"
    let elevationGainM:   Double
    let distanceTotalKm:  Double
    let distanceSoFarKm:  Double      // 0 if pre-ride
    let timeOfDay:        String      // "morning" | "afternoon" | "evening"
    let topPastCategories: [String]   // up to 3 category names from ride history
}

// MARK: - Ranked result

struct RankedPOIResult {
    let poi:    MKMapItem
    let reason: String
}

// MARK: - Engine

actor POIRankingEngine {

    static let shared = POIRankingEngine()
    private init() {}

    /// Ranks `pois` by relevance to `context`.
    /// Caps input at 15 items to stay within the 4096-token context window.
    /// Returns ranked results with reasons; falls back to original order on error.
    func rank(_ pois: [MKMapItem], context: RideContext) async -> [RankedPOIResult] {
        let capped = Array(pois.prefix(15))
        guard !capped.isEmpty else { return [] }

        do {
            return try await runRanking(capped, context: context)
        } catch {
            // Graceful fallback — return unranked with empty reasons
            return capped.map { RankedPOIResult(poi: $0, reason: "") }
        }
    }

    // MARK: - Private

    private func runRanking(_ pois: [MKMapItem], context: RideContext) async throws -> [RankedPOIResult] {
        let poiLines = pois.enumerated().map { i, item in
            "\(i + 1). \(item.name ?? "Unknown") — \(item.pointOfInterestCategory?.rawValue ?? "place")"
        }.joined(separator: "\n")

        let prompt = """
        You are helping a cyclist choose which stops are most relevant for their ride.
        Rank the following POIs from most to least relevant. Return ONLY the ranked list.
        For each line use format: <rank>. <original name> | <one short reason (max 6 words)>

        Ride context:
        - Route: \(context.routeName)
        - Difficulty: \(context.difficulty)
        - Elevation gain: \(Int(context.elevationGainM)) m
        - Total distance: \(String(format: "%.0f", context.distanceTotalKm)) km
        - Distance ridden so far: \(String(format: "%.0f", context.distanceSoFarKm)) km
        - Time of day: \(context.timeOfDay)
        - Rider's frequent past stop types: \(context.topPastCategories.joined(separator: ", "))

        POIs to rank:
        \(poiLines)
        """

        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return parseRankedResponse(response.content, original: pois)
    }

    /// Parses lines like "1. Café Névé | Good stop for climbing route"
    /// and returns results in ranked order, matched back to original MKMapItem.
    private func parseRankedResponse(_ text: String, original pois: [MKMapItem]) -> [RankedPOIResult] {
        let lines = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var ordered: [RankedPOIResult] = []

        for line in lines {
            // Strip leading "1. ", "2. " etc.
            let stripped = line.replacingOccurrences(of: #"^\d+\.\s*"#, with: "",
                                                       options: .regularExpression)
            let parts = stripped.split(separator: "|", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let namePart = parts.first else { continue }
            let reason = parts.count > 1 ? parts[1] : ""

            // Match by name (case-insensitive prefix)
            if let match = pois.first(where: {
                ($0.name ?? "").lowercased().hasPrefix(namePart.lowercased().prefix(12))
            }) {
                // Avoid duplicates
                if !ordered.contains(where: { $0.poi === match }) {
                    ordered.append(RankedPOIResult(poi: match, reason: reason))
                }
            }
        }

        // Append any unmatched POIs at the end (safety net)
        for poi in pois where !ordered.contains(where: { $0.poi === poi }) {
            ordered.append(RankedPOIResult(poi: poi, reason: ""))
        }

        return ordered
    }
}
