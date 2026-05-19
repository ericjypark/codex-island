import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Hashable {
    case auto
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case hi
    case ja
    case ko
    case de
    case fr
    case es
    case ptBR = "pt-BR"

    var resourceName: String? {
        switch self {
        case .auto: nil
        default: rawValue
        }
    }

    var localeIdentifier: String {
        switch self {
        case .auto: Locale.current.identifier
        case .en: "en"
        case .zhHans: "zh-Hans"
        case .zhHant: "zh-Hant"
        case .hi: "hi"
        case .ja: "ja"
        case .ko: "ko"
        case .de: "de"
        case .fr: "fr"
        case .es: "es"
        case .ptBR: "pt-BR"
        }
    }

    var menuLabel: String {
        switch self {
        case .auto: L10n.tr("Auto")
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .hi: "हिन्दी"
        case .ja: "日本語"
        case .ko: "한국어"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .ptBR: "Português (Brasil)"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: L10n.tr("Follows macOS")
        default: menuLabel
        }
    }
}

enum AppLanguageResolver {
    static let key = "MacIsland.appLanguage"

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        return AppLanguage(rawValue: raw) ?? .auto
    }

    static var locale: Locale {
        Locale(identifier: current.localeIdentifier)
    }

    static var bundle: Bundle? {
        guard let resourceName = current.resourceName,
              let path = Bundle.main.path(forResource: resourceName, ofType: "lproj")
        else { return nil }
        return Bundle(path: path)
    }

    static var englishBundle: Bundle? {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguageResolver.key) }
    }

    private init() {
        language = AppLanguageResolver.current
    }

    @discardableResult
    func select(_ newLanguage: AppLanguage) -> Bool {
        guard language != newLanguage else { return false }
        language = newLanguage
        return true
    }

    func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
