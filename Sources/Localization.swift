import Foundation

/// The UI follows the system language: English unless the first preferred
/// system language is Russian. Strings are written inline as L(ru, en) so a
/// missing translation is visible in code review instead of silently falling
/// back.
enum Localization {
    static let isRussian: Bool = {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru")
    }()

    static var languageCode: String { isRussian ? "ru" : "en" }

    static func text(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}

func L(_ ru: String, _ en: String) -> String {
    Localization.text(ru, en)
}

func LF(_ ru: String, _ en: String, _ arguments: CVarArg...) -> String {
    String(format: Localization.text(ru, en), arguments: arguments)
}
