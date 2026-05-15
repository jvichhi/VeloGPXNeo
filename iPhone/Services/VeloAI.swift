import Foundation
import FoundationModels

/// Shared AI configuration + availability gate.
///
/// Usage:
/// ```swift
/// guard VeloAI.isAvailable else { return }
/// let session = try VeloAI.makeSession(instructions: "…")
/// ```
enum VeloAI {
    /// `AppStorage` key used by every AI feature.
    static let enabledKey = "velogpx.aiEnabled"

    // MARK: - Availability

    /// `true` if Apple Intelligence / FoundationModels is available on this device.
    /// `nonisolated` — safe to call from any actor; only queries SystemLanguageModel, no UI state.
    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Session factory

    /// Creates a new `LanguageModelSession` with the given system instruction.
    /// `nonisolated` — safe to call from any actor; no UI state involved.
    /// Always check `isAvailable` first.
    nonisolated static func makeSession(instructions: String) throws -> LanguageModelSession {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw VeloAIError.modelUnavailable
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(instructions)
        )
    }
}

// MARK: - Errors

enum VeloAIError: LocalizedError {
    case modelUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligence is not available on this device."
        case .emptyResponse:
            return "The AI returned an empty response."
        }
    }
}

// MARK: - GenerationError display helper

extension LanguageModelSession.GenerationError {
    /// User-facing one-liner for toast/inline error display.
    var displayMessage: String {
        switch self {
        case .exceededContextWindowSize:
            return "Route data is too large to summarise."
        case .guardrailViolation:
            return "Content couldn't be generated."
        default:
            return "Couldn't generate a response. Try again."
        }
    }
}
