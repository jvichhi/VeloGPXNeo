import Foundation
import FoundationModels

/// F-A1 — Generates a shareable, social-media-ready ride summary using
/// Apple Intelligence (FoundationModels) entirely on-device.
///
/// Output length target: 2–3 sentences, emoji welcome.
///
/// API note: `LanguageModelSession.streamResponse` only supports `@Generable`
/// structured types — there is no plain-String streaming overload.
/// We use `respond(to:)` for a single complete response instead.
struct RideSummaryGenerator {

    // MARK: - Public API

    /// Returns the complete generated summary string.
    /// Throws `VeloAIError` or `LanguageModelSession.GenerationError`.
    func generate(from summary: RideSummary) async throws -> String {
        let session = try VeloAI.makeSession(instructions: systemInstruction)
        let prompt  = buildPrompt(from: summary)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw VeloAIError.emptyResponse }
        return text
    }

    // MARK: - Prompt

    private let systemInstruction = """
        You are a cycling coach who writes punchy, encouraging ride summaries.
        Write 2–3 sentences only. No bullet points. Use emojis sparingly.
        Mention the distance and one other standout stat.
        Keep it conversational and shareable on Strava or Instagram.
        """

    private func buildPrompt(from s: RideSummary) -> String {
        var parts: [String] = []
        parts.append("Ride: \(s.routeName)")
        parts.append("Date: \(s.startDate.formatted(date: .abbreviated, time: .omitted))")
        parts.append("Distance: \(String(format: "%.2f", s.distanceKm)) km")
        parts.append("Moving time: \(s.movingTime.hhmm)\(s.movingTime.unit)")
        parts.append("Avg speed: \(String(format: "%.1f", s.avgSpeedKmh)) km/h")
        parts.append("Max speed: \(String(format: "%.1f", s.maxSpeedKmh)) km/h")
        parts.append("Elevation gain: \(String(format: "%.0f", s.elevationGain)) m")
        if !s.pois.isEmpty {
            let names = s.pois.prefix(3).map(\.name).joined(separator: ", ")
            parts.append("Stops: \(names)")
        }
        return parts.joined(separator: "\n")
    }
}
