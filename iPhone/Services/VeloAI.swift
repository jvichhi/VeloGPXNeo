// VeloAI.swift
// VeloGPXNeo — iPhone target ONLY. Never add to Watch target.
//
// PURPOSE:
// Central gateway for all on-device AI functionality in VeloGPX.
// This file owns two things:
//   1. The availability check — is the on-device model ready on this device?
//   2. The AppStorage key — the user's "Enable AI Features" toggle in Settings.
//
// All AI service files (RouteNameSuggester, RideSummaryGenerator, POIRankingEngine,
// and the upcoming PlanAssistantEngine) gate their work behind:
//   guard VeloAI.isAvailable && aiEnabled else { return }
// where `aiEnabled` is read from @AppStorage(VeloAI.enabledKey).
//
// WHY nonisolated on isAvailable:
// SwiftUI .task {} blocks and async functions can run on actors other than MainActor.
// If `isAvailable` were a regular static var, Swift 6 strict concurrency would warn
// (or error) when it's called from a non-isolated context, because the compiler can't
// prove it's safe to read across actor boundaries. Marking it `nonisolated` tells the
// compiler: "this is safe to call from any actor; it does no actor-bound work."
// SystemLanguageModel.default.availability is itself nonisolated and thread-safe.
//
// FRAMEWORK SETUP (Xcode — cannot be done via git):
// Add FoundationModels.framework to the iPhone target:
//   Xcode → iPhone target → Build Phases → Link Binary With Libraries → + → FoundationModels.framework
// DO NOT add it to the Watch target — FoundationModels is iPhone-only.
//
// iOS 26+ NOTE:
// We do NOT use @available(iOS 26, *) here or on any AI service file.
// The project's deployment target is iOS 26 minimum, so that annotation is redundant
// and adds noise. If the deployment target ever changes, revisit this.
// See PROJECT.md: "Do not add @available(iOS 26, *) scaffolding 'just in case'."
//
// DEPRECATED PATTERNS TO AVOID:
// ❌ session.stream(from:onPartial:) — removed in iOS 26 beta. Don't use.
// ❌ LanguageModel() custom init — use SystemLanguageModel.default only.
// ❌ Storing LanguageModelSession as a long-lived property — sessions are lightweight;
//    create one per request in an async context and let it deallocate.
// ✅ session.respond(to: prompt) — plain String in, plain String out.
// ✅ session.generate(from: schema) — @Generable structured output (Sprint 3).

import FoundationModels

/// Central AI gateway for VeloGPX.
///
/// Provides the single source of truth for:
/// - Whether on-device AI is available on this device/OS combination.
/// - The AppStorage key for the user-facing "Enable AI Features" toggle.
///
/// Usage pattern in any AI-gated view or service:
/// ```swift
/// @AppStorage(VeloAI.enabledKey) private var aiEnabled = true
/// guard VeloAI.isAvailable && aiEnabled else { return }
/// ```
enum VeloAI {

    // MARK: - Availability

    /// `true` when the on-device `SystemLanguageModel` is ready to accept sessions.
    ///
    /// Reads `SystemLanguageModel.default.availability`. The possible states are:
    /// - `.available` — model downloaded and ready. We return `true`.
    /// - `.downloading` — model in progress. Return `false`; show a "Downloading..." UI if desired.
    /// - `.unavailable` — device doesn't support on-device AI (older hardware).
    ///
    /// `nonisolated` is required because this property is called from `.task {}` blocks
    /// and async contexts that may run on any actor. Without `nonisolated`, Swift 6
    /// strict concurrency will flag the cross-actor read.
    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Settings Key

    /// The `@AppStorage` key for the user-facing "Enable AI Features" toggle in SettingsView.
    ///
    /// Every AI-gated view reads this via:
    /// ```swift
    /// @AppStorage(VeloAI.enabledKey) private var aiEnabled = true
    /// ```
    /// Default is `true` — AI features are on by default when available.
    /// The toggle is only shown in Settings when `isAvailable` is also `true`.
    static let enabledKey = "veloai_enabled"

    // MARK: - Session Factory

    /// Creates a fresh `LanguageModelSession` for the system on-device model.
    ///
    /// Sessions are lightweight — create one per request, use it, then let it deallocate.
    /// Do NOT cache or store a session across requests or as a long-lived property;
    /// context accumulates in the session and it cannot be cleared without creating a new one.
    ///
    /// `nonisolated` because this is called from async services that may run off-MainActor.
    ///
    /// - Returns: A configured session ready for `.respond(to:)` or `.generate(from:)` calls.
    /// - Note: Always check `isAvailable` before calling this. Calling when unavailable will throw.
    nonisolated static func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel.default)
    }
}
