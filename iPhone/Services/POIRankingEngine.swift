import Foundation
import MapKit
import FoundationModels

// MARK: - Input types

/// Context about the current ride used to rank POIs.
struct RideContext: Sendable {
    let routeName:         String
    let difficulty:        String
    let elevationGainM:    Double
    let distanceTotalKm:   Double
    let distanceSoFarKm:   Double
    let timeOfDay:         String
    let topPastCategories: [String]
}

/// One ranked result returned to the caller.
struct RankedPOIResult: Sendable {
    let poi: MKMapItem
    let reason: String
}

// MARK: - Engine

/// F-A3 — Uses on-device AI to rank and annotate POI search results by
/// contextual relevance to the current ride.
///
/// Falls back to the original order on any error.
actor POIRankingEngine {

    static let shared = POIRankingEngine()
    private init() {}

    // MARK: - Public API

    func rank(_ items: [MKMapItem], context: RideContext) async -> [RankedPOIResult] {
        guard VeloAI.isAvailable, !items.isEmpty else {
            return items.map { RankedPOIResult(poi: $0, reason: "") }
        }
        do {
            return try await runRanking(items, context: context)
        } catch {
            return items.map { RankedPOIResult(poi: $0, reason: "") }
        }
    }

    // MARK: - Internal

    private func runRanking(_ items: [MKMapItem], context: RideContext) async throws -> [RankedPOIResult] {
        let session = try VeloAI.makeSession(instructions: systemInstruction)
        let prompt  = buildPrompt(items: items, context: context)
        let response = try await session.respond(to: prompt)
        return parseResponse(response.content, originalItems: items)
    }

    private let systemInstruction = """
        You are a cycling-route assistant helping rank Points of Interest (POIs).
        Given a list of POIs and ride context, return them ranked best-first.
        For each POI, output one line: INDEX|REASON
        INDEX is the 1-based position from the input list.
        REASON is a short phrase (≤8 words) explaining its relevance for a cyclist.
        Output exactly one line per POI. No extra text.
        """

    private func buildPrompt(items: [MKMapItem], context: RideContext) -> String {
        var lines: [String] = []
        lines.append("Ride context:")
        lines.append("  Route: \(context.routeName)")
        lines.append("  Distance: \(String(format: "%.1f", context.distanceTotalKm)) km, \(context.difficulty) ride")
        lines.append("  Elevation gain: \(String(format: "%.0f", context.elevationGainM)) m")
        lines.append("  Progress: \(String(format: "%.1f", context.distanceSoFarKm)) km covered")
        lines.append("  Time of day: \(context.timeOfDay)")
        if !context.topPastCategories.isEmpty {
            lines.append("  Rider prefers: \(context.topPastCategories.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("POIs to rank:")
        for (i, item) in items.enumerated() {
            var desc = "\(i + 1). \(item.name ?? "Unknown")"
            if let cat = item.pointOfInterestCategory {
                desc += " [\(cat.rawValue)]"
            }
            lines.append(desc)
        }
        return lines.joined(separator: "\n")
    }

    private func parseResponse(_ raw: String, originalItems: [MKMapItem]) -> [RankedPOIResult] {
        var ranked: [RankedPOIResult] = []
        var usedIndices = Set<Int>()
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 2,
                  let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  index >= 1, index <= originalItems.count else { continue }
            let itemIndex = index - 1
            guard !usedIndices.contains(itemIndex) else { continue }
            usedIndices.insert(itemIndex)
            let reason = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            ranked.append(RankedPOIResult(poi: originalItems[itemIndex], reason: reason))
        }
        for (i, item) in originalItems.enumerated() where !usedIndices.contains(i) {
            ranked.append(RankedPOIResult(poi: item, reason: ""))
        }
        return ranked
    }
}
