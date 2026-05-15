import Foundation
import FoundationModels

/// F-A1 — Streams a shareable, social-media-ready ride summary using
/// Apple Intelligence (FoundationModels) entirely on-device.
///
/// Output length target: 2–3 sentences, emoji welcome.
struct RideSummaryGenerator {

    // MARK: - Public API

    /// Streams partial text back to `onPartial` as tokens arrive.
    /// Throws `VeloAIError` or `LanguageModelSession.GenerationError`.
    func stream(
        from summary: RideSummary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        let session = try VeloAI.makeSession(instructions: systemInstruction)
        let prompt  = buildPrompt(from: summary)

        var accumulated = ""
        let stream = session.streamResponse(to: prompt)
        for try await partial in stream {
            accumulated += partial
            let copy = accumulated
            await MainActor.run { onPartial(copy) }
        }

        if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VeloAIError.emptyResponse
        }
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
