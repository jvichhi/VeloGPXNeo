import Foundation
import Combine
import SwiftUI

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case arabic     = "ar"
    case chinese    = "zh-Hans"
    case danish     = "da"
    case dutch      = "nl"
    case english    = "en"
    case french     = "fr"
    case german     = "de"
    case italian    = "it"
    case japanese   = "ja"
    case korean     = "ko"
    case norwegian  = "nb"
    case polish     = "pl"
    case portuguese = "pt"
    case spanish    = "es"
    case swedish    = "sv"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arabic:     return "Arabic"
        case .chinese:    return "Chinese (Simplified)"
        case .danish:     return "Danish"
        case .dutch:      return "Dutch"
        case .english:    return "English"
        case .french:     return "French"
        case .german:     return "German"
        case .italian:    return "Italian"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        case .norwegian:  return "Norwegian"
        case .polish:     return "Polish"
        case .portuguese: return "Portuguese"
        case .spanish:    return "Spanish"
        case .swedish:    return "Swedish"
        }
    }

    var nativeName: String {
        switch self {
        case .arabic:     return "\u{202A}\u{0627}\u{0644}\u{0639}\u{0631}\u{0628}\u{064A}\u{0629}\u{202C}"
        case .chinese:    return "\u{4E2D}\u{6587}\u{FF08}\u{7B80}\u{4F53}\u{FF09}"
        case .danish:     return "Dansk"
        case .dutch:      return "Nederlands"
        case .english:    return "English"
        case .french:     return "Fran\u{00E7}ais"
        case .german:     return "Deutsch"
        case .italian:    return "Italiano"
        case .japanese:   return "\u{65E5}\u{672C}\u{8A9E}"
        case .korean:     return "\u{D55C}\u{AD6D}\u{C5B4}"
        case .norwegian:  return "Norsk"
        case .polish:     return "Polski"
        case .portuguese: return "Portugu\u{00EA}s"
        case .spanish:    return "Espa\u{00F1}ol"
        case .swedish:    return "Svenska"
        }
    }

    var flag: String {
        switch self {
        case .arabic:     return "\u{1F1F8}\u{1F1E6}"
        case .chinese:    return "\u{1F1E8}\u{1F1F3}"
        case .danish:     return "\u{1F1E9}\u{1F1F0}"
        case .dutch:      return "\u{1F1F3}\u{1F1F1}"
        case .english:    return "\u{1F1EC}\u{1F1E7}"
        case .french:     return "\u{1F1EB}\u{1F1F7}"
        case .german:     return "\u{1F1E9}\u{1F1EA}"
        case .italian:    return "\u{1F1EE}\u{1F1F9}"
        case .japanese:   return "\u{1F1EF}\u{1F1F5}"
        case .korean:     return "\u{1F1F0}\u{1F1F7}"
        case .norwegian:  return "\u{1F1F3}\u{1F1F4}"
        case .polish:     return "\u{1F1F5}\u{1F1F1}"
        case .portuguese: return "\u{1F1F5}\u{1F1F9}"
        case .spanish:    return "\u{1F1EA}\u{1F1F8}"
        case .swedish:    return "\u{1F1F8}\u{1F1EA}"
        }
    }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    static var alphabetical: [AppLanguage] {
        allCases.sorted { $0.displayName < $1.displayName }
    }
}

// MARK: - LocalizationManager

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: AppLanguage
    /// The bundle to use for all localized string lookups.
    /// Rebuilds whenever currentLanguage changes.
    @Published private(set) var bundle: Bundle = .main

    private let key = "velogpx.language"

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "velogpx.language"),
           let lang = AppLanguage(rawValue: saved) {
            currentLanguage = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            currentLanguage = AppLanguage.allCases.first {
                preferred.hasPrefix($0.rawValue)
            } ?? .english
        }
        bundle = Self.makeBundle(for: currentLanguage)
    }

    func set(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        // Persist so the next cold launch starts in the right language
        UserDefaults.standard.set(language.rawValue, forKey: key)
        // Tell iOS which language to use for system APIs (e.g. date formatters)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        // Swap the bundle — all .localized calls will now return strings
        // from the matching .lproj folder once those catalogs exist.
        bundle = Self.makeBundle(for: language)
    }

    // MARK: Private helpers

    private static func makeBundle(for language: AppLanguage) -> Bundle {
        // Look for an .lproj inside the main bundle
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let lprojBundle = Bundle(path: path)
        else {
            // No .lproj yet — fall back to main bundle (strings stay in English)
            return .main
        }
        return lprojBundle
    }
}

// MARK: - String localization helper

extension String {
    /// Returns the localized version of this string using LocalizationManager's
    /// active bundle. Falls back to `self` when no translation is found.
    var localized: String {
        LocalizationManager.shared.bundle
            .localizedString(forKey: self, value: self, table: nil)
    }
}

// MARK: - Environment key so views can read the active layout direction

struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
