import Foundation
import Combine

// MARK: - Supported Languages

enum AppLanguage: String, CaseIterable, Identifiable {
    // Western Europe
    case english    = "en"
    case french     = "fr"
    case spanish    = "es"
    case portuguese = "pt"
    case italian    = "it"
    case german     = "de"
    case dutch      = "nl"
    // Nordic
    case danish     = "da"
    case swedish    = "sv"
    // Central/Eastern Europe
    case polish     = "pl"
    // Major cycling nations outside Europe
    case japanese   = "ja"
    case chinese    = "zh-Hans"
    case korean     = "ko"
    // Benelux / popular cycling
    case norwegian  = "nb"
    // North Africa / Middle East cycling growth
    case arabic     = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .french:     return "Français"
        case .spanish:    return "Español"
        case .portuguese: return "Português"
        case .italian:    return "Italiano"
        case .german:     return "Deutsch"
        case .dutch:      return "Nederlands"
        case .danish:     return "Dansk"
        case .swedish:    return "Svenska"
        case .polish:     return "Polski"
        case .japanese:   return "日本語"
        case .chinese:    return "简体中文"
        case .korean:     return "한국어"
        case .norwegian:  return "Norsk"
        case .arabic:     return "العربية"
        }
    }

    var flag: String {
        switch self {
        case .english:    return "🇬🇧"
        case .french:     return "🇫🇷"
        case .spanish:    return "🇪🇸"
        case .portuguese: return "🇧🇷"
        case .italian:    return "🇮🇹"
        case .german:     return "🇩🇪"
        case .dutch:      return "🇳🇱"
        case .danish:     return "🇩🇰"
        case .swedish:    return "🇸🇪"
        case .polish:     return "🇵🇱"
        case .japanese:   return "🇯🇵"
        case .chinese:    return "🇨🇳"
        case .korean:     return "🇰🇷"
        case .norwegian:  return "🇳🇴"
        case .arabic:     return "🇸🇦"
        }
    }

    /// Returns true for RTL languages
    var isRTL: Bool { self == .arabic }
}

// MARK: - LocalizationManager

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: AppLanguage
    private var bundle: Bundle = .main

    private let storageKey = "velogpx.language"

    private init() {
        // Resolve saved preference → system language → English fallback
        if let saved = UserDefaults.standard.string(forKey: "velogpx.language"),
           let lang = AppLanguage(rawValue: saved) {
            currentLanguage = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            let code = String(preferred.prefix(2))
            // Match zh specially
            if preferred.hasPrefix("zh") {
                currentLanguage = .chinese
            } else {
                currentLanguage = AppLanguage(rawValue: code) ?? .english
            }
        }
        bundle = resolveBundle(for: currentLanguage)
    }

    func set(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        bundle = resolveBundle(for: language)
        objectWillChange.send()
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private func resolveBundle(for language: AppLanguage) -> Bundle {
        // Try exact code first, then 2-char prefix
        let codes = [language.rawValue, String(language.rawValue.prefix(2))]
        for code in codes {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
        }
        return .main
    }
}

// MARK: - Convenience

extension String {
    /// Shorthand: "key".localized
    var localized: String {
        LocalizationManager.shared.string(self)
    }
}
