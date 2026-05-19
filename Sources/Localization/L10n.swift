import Foundation

enum L10n {
    static var locale: Locale {
        AppLanguageResolver.locale
    }

    static func tr(_ key: String) -> String {
        if let bundle = AppLanguageResolver.bundle {
            let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key { return localized }
            if let fallback = AppLanguageResolver.englishBundle {
                return fallback.localizedString(forKey: key, value: key, table: nil)
            }
        }
        return NSLocalizedString(key, comment: "")
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: arguments)
    }
}
