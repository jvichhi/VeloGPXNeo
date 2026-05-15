// RideSummaryGenerator.swift
// VeloGPXNeo — iPhone target ONLY. Never add to Watch target.
//
// PURPOSE:
// Generates a short, natural-language summary of a completed ride using the
// on-device SystemLanguageModel (FoundationModels framework, iOS 26).
// The summary is displayed in RideSummaryView and can be edited before sharing.
// Once generated (and optionally edited), it is persisted via RideHistoryStore.saveCaption(id:caption:).
//
// FLOW:
//   RideSummaryView
//     └─ Button("Generate Summary")
//           └─ RideSummaryGenerator().generate(from: summary)
//                 ├─ buildPrompt(summary:)   ← formats ride stats into a prompt
//                 └─ session.respond(to:)    ← returns a plain String summary
//
// WHY respond(to:) and NOT generate(from:) / stream:
// respond(to:) takes a plain String prompt and returns a plain String response.
// This is correct for a narrative text output like a ride summary.
// generate(from:) is for @Generable structured output (Sprint 3 — RidePlanIntent).
// stream(from:onPartial:) was removed in iOS 26 beta — never use it.
//
// SESSION LIFECYCLE:
// LanguageModelSession instances are lightweight. Create one per generate() call
// and let it deallocate when the async function returns. Never store a session
// as a @State, @StateObject, or stored property on an actor — sessions accumulate
// context internally and there is no way to clear them without creating a new one.
//
// ACTOR ISOLATION:
// This is a plain struct (no actor isolation). The caller (RideSummaryView) runs
// generate() inside a .task {} or Task { } block on the MainActor, but the
// FoundationModels calls themselves are nonisolated and run on the cooperative
// thread pool. This is correct — no @MainActor annotation needed here.
//
// PERSISTENCE:
// The generated caption is NOT persisted here. RideSummaryView is responsible for
// calling RideHistoryStore.saveCaption(id: summary.id, caption: text) after the
// user optionally edits the text. This keeps the generator stateless and testable.
//
// ERROR HANDLING:
// generate(from:) throws. Callers should catch LanguageModelError and surface a
// retry UI. Common failure modes:
//   - .modelUnavailable — device doesn't support on-device AI
//   - .generationFailed — safety filtering or prompt rejection
//   - network errors don't apply (this is fully on-device)

import Foundation
import FoundationModels

/// Generates a natural-language summary for a completed ride using the
/// on-device `SystemLanguageModel`.
///
/// Stateless — safe to instantiate per request and discard.
/// Always check `VeloAI.isAvailable` before calling `generate(from:)`.
struct RideSummaryGenerator {

    // MARK: - Public API

    /// Generates a short narrative summary of the given ride.
    ///
    /// The summary is 2–3 sentences in a friendly, first-person tone
    /// suitable for sharing on social media or saving as a ride note.
    ///
    /// - Parameter summary: The completed ride's stats (distance, duration, elevation, etc.).
    /// - Returns: A plain String summary. Typically 30–60 words.
    /// - Throws: `LanguageModelError` if the model session fails.
    func generate(from summary: RideSummary) async throws -> String {
        // Build the prompt from the ride's stats.
        // The prompt includes all numeric context so the model produces specific,
        // not generic, summaries ("You crushed 42 km" not "You had a great ride").
        let prompt = buildPrompt(summary: summary)

        // Create a fresh session. Sessions are cheap — one per request is correct.
        // Do NOT reuse sessions across calls; accumulated context causes drift.
        let session = VeloAI.makeSession()

        // respond(to:) returns the full model response as a String.
        // This is a suspending call — it will await the on-device model.
        // Typical latency on supported hardware: 1–3 seconds.
        let response = try await session.respond(to: prompt)

        // Trim any leading/trailing whitespace the model might add.
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    /// Constructs the prompt string sent to the language model.
    ///
    /// Prompt design principles:
    /// - Be explicit about length ("2-3 sentences") and tone ("friendly, first-person").
    /// - Provide concrete numbers. The model produces better output with real data
    ///   than with vague descriptions.
    /// - Constrain the output format to avoid markdown, bullet points, or headings.
    /// - Keep the prompt under ~200 tokens for fast on-device inference.
    private func buildPrompt(summary: RideSummary) -> String {
        let distKm    = String(format: "%.1f", summary.totalDistance / 1000)
        let durationM = Int(summary.elapsedTime / 60)
        let elevGain  = String(format: "%.0f", summary.elevationGain)
        let avgSpeed  = String(format: "%.1f", summary.avgSpeedKmh * 3.6) // m/s → km/h

        // Format duration as "1h 23m" or "45m" depending on length.
        let hours = durationM / 60
        let mins  = durationM % 60
        let durationStr = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"

        return """
        You are a friendly cycling coach writing a brief ride recap.
        Write a 2-3 sentence summary of this ride in a friendly, first-person tone.
        Do not use bullet points, markdown, or headings — plain text only.
        Ride stats:
        - Distance: \(distKm) km
        - Duration: \(durationStr)
        - Elevation gain: \(elevGain) m
        - Average speed: \(avgSpeed) km/h
        """
    }
}
