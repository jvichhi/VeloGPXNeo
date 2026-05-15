//
//  VeloAI.swift
//  VeloGPX
//
//  Availability gate and shared constants for all on-device AI features (F-A).
//  Does NOT hold a shared LanguageModelSession — each feature creates its own
//  one-shot session to avoid context leakage between unrelated tasks.
//

import Foundation
import FoundationModels

// MARK: - Availability

enum VeloAI {
    /// True when Apple Intelligence is available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// UserDefaults key for the user's AI Features toggle in Settings.
    static let enabledKey = "veloai.featuresEnabled"

    /// Returns true when AI is both available and enabled by the user.
    static func isEnabled() -> Bool {
        guard isAvailable else { return false }
        // Default true — opt-in by default when hardware supports it.
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

// MARK: - Error Presentation

extension LanguageModelSession.GenerationError {
    /// User-facing message for common generation errors.
    var displayMessage: String {
        switch self {
        case .guardrailViolation:
            return "The model couldn't generate a response for this content."
        case .exceededContextWindowSize:
            return "Too much data for the model — try a shorter route or fewer POIs."
        default:
            return "Couldn't generate a response. Try again."
        }
    }
}
