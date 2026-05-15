//
//  VeloAI.swift
//  VeloGPX
//
//  Shared gate + configuration for all FoundationModels (Apple Intelligence)
//  features. Import this file instead of importing FoundationModels directly
//  in views — keeps the availability guard in one place.
//

import Foundation
import FoundationModels

enum VeloAI {
    /// AppStorage key for the user-facing "AI Features" toggle in SettingsView.
    static let enabledKey = "veloai_enabled"

    /// True when Apple Intelligence is available on this device.
    /// nonisolated so it can be read from any actor context (Swift 6 compat).
    /// Views gate AI UI behind this check so nothing AI-related renders on
    /// unsupported hardware.
    nonisolated static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
}
