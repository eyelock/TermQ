import Foundation

/// Represents a language supported by the app
struct SupportedLanguage: Identifiable, Hashable {
    let code: String
    let englishName: String
    let nativeName: String

    var id: String { code }

    /// Display name showing both native and English names
    var displayName: String {
        if code.isEmpty {
            return "System Default"
        }
        if nativeName == englishName {
            return "\(englishName) (\(code))"
        }
        return "\(nativeName) — \(englishName) (\(code))"
    }

    /// Searchable text for filtering
    var searchableText: String {
        "\(englishName) \(nativeName) \(code)".lowercased()
    }

    /// System default option
    static let systemDefault = SupportedLanguage(
        code: "",
        englishName: "System Default",
        nativeName: "System Default"
    )

    /// All languages supported by macOS
    /// Based on languages available in System Preferences > Language & Region
    static let all: [SupportedLanguage] = {
        let languageCodes = [
            "en", "en-GB", "en-AU",
            "es", "es-419",
            "fr", "fr-CA",
            "de",
            "it",
            "pt", "pt-PT",
            "nl",
            "sv",
            "da",
            "fi",
            "no",
            "pl",
            "ru",
            "uk",
            "cs",
            "sk",
            "hu",
            "ro",
            "hr",
            "sl",
            "el",
            "tr",
            "he",
            "ar",
            "th",
            "vi",
            "id",
            "ms",
            "zh-Hans",
            "zh-Hant",
            "zh-HK",
            "ja",
            "ko",
            "hi",
            "ca",
        ]

        return languageCodes.compactMap { code -> SupportedLanguage? in
            let locale = Locale(identifier: code)
            let englishLocale = Locale(identifier: "en")

            guard let englishName = englishLocale.localizedString(forIdentifier: code),
                let nativeName = locale.localizedString(forIdentifier: code)
            else {
                return nil
            }

            return SupportedLanguage(
                code: code,
                englishName: englishName,
                nativeName: nativeName
            )
        }.sorted { $0.englishName < $1.englishName }
    }()

    /// All options including system default
    static let allWithDefault: [SupportedLanguage] = [systemDefault] + all
}

/// Manager for app language preferences
enum LanguageManager {
    private static let preferredLanguageKey = "preferredLanguage"

    /// Get the currently selected language code (empty = system default)
    static var preferredLanguage: String {
        get {
            UserDefaults.standard.string(forKey: preferredLanguageKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: preferredLanguageKey)
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set(newValue, forKey: preferredLanguageKey)
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Get the current SupportedLanguage selection
    static var currentLanguage: SupportedLanguage {
        let code = preferredLanguage
        if code.isEmpty {
            return .systemDefault
        }
        return SupportedLanguage.all.first { $0.code == code } ?? .systemDefault
    }

    /// Apply the language setting (call on app launch)
    static func applyLanguageSetting() {
        let code = preferredLanguage
        if !code.isEmpty {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// Check if a restart is needed for the language change to take effect
    static func needsRestart(for newCode: String) -> Bool {
        let current = preferredLanguage
        return current != newCode
    }
}
