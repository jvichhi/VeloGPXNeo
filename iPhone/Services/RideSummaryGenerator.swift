//
//  RideSummaryGenerator.swift
//  VeloGPX
//
//  F-A1 — On-device ride summary generation.
//  Creates a short, shareable natural-language description of a completed ride.
//  Streams the response so the UI can show text appearing word by word.
//

import Foundation
import FoundationModels

struct RideSummaryGenerator {

    /// Streams a 2–3 sentence ride summary, yielding partial strings as they arrive.
    /// Caller should replace displayed text with each yielded value.
    ///
    /// - Parameters:
    ///   - summary: The completed `RideSummary` to describe.
    ///   - onChunk: Called on the main actor with each partial response string.
    func stream(
        from summary: RideSummary,
        onChunk: @MainActor @escaping (String) -> Void
    ) async throws {
        let session = LanguageModelSession()
        let prompt = buildPrompt(from: summary)
        let stream = session.streamResponse(to: prompt)
        for try await partial in stream {
            await onChunk(partial.content)
        }
    }

    // MARK: - Prompt

    private func buildPrompt(from summary: RideSummary) -> String {
        let distKm   = String(format: "%.1f", summary.distanceKm)
        let gainM    = Int(summary.elevationGain)
        let lossM    = Int(summary.elevationLoss)
        let moving   = summary.movingTime.formatted
        let maxSpeed = String(format: "%.1f", summary.maxSpeedKmh)
        let date     = summary.startDate.formatted(date: .long, time: .omitted)

        var poiLine = ""
        let poiNames = summary.pois.prefix(4).map(\.name)
        if !poiNames.isEmpty {
            poiLine = "Notable stops: \(poiNames.joined(separator: ", "))."
        }

        return """
        Write a 2–3 sentence summary for a cycling ride, suitable for sharing on social media or Strava.
        Route name: \(summary.routeName)
        Date: \(date)
        Distance: \(distKm) km
        Elevation gain: \(gainM) m | Loss: \(lossM) m
        Moving time: \(moving)
        Max speed: \(maxSpeed) km/h
        \(poiLine)
        Tone: enthusiastic but factual. Mention the route name and at least one specific stat.
        No hashtags. No emojis. No markdown. Plain sentences only.
        """
    }
}

// MARK: - TimeInterval formatting helper

private extension TimeInterval {
    /// e.g. "1h 23m" or "47m"
    var formatted: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
