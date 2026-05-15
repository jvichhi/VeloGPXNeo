//
//  RideSummaryGenerator.swift
//  VeloGPX
//
//  F-A1 — Ride Summary Generation.
//  Generates a short, shareable natural-language ride summary from a
//  completed `RideSummary` using an on-device FoundationModels session.
//
//  Note: @available(iOS 26,*) removed — deployment target is iOS 26 (PROJECT.md).
//

import Foundation
import FoundationModels

struct RideSummaryGenerator {

    // MARK: - Public API

    /// Generates a 2–3 sentence ride summary suitable for sharing.
    /// Throws if the language model session fails.
    func generate(from summary: RideSummary) async throws -> String {
        let distKm  = String(format: "%.1f", summary.totalDistance / 1000)
        let gainM   = Int(summary.elevationGain)
        let elapsed = formatDuration(summary.elapsedTime)
        let pois    = summary.pois.prefix(3).map { $0.name }.joined(separator: ", ")

        let prompt = """
        Write a 2–3 sentence summary for a cycling ride.
        Route: \(summary.routeName)
        Distance: \(distKm) km | Elevation gain: \(gainM) m | Time: \(elapsed)
        Notable stops: \(pois.isEmpty ? "none" : pois)
        Tone: enthusiastic but factual. No hashtags. No emojis.
        """

        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
