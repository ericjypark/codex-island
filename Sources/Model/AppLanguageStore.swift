import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Hashable {
    case auto
    case en
    case zhHans = "zh-Hans"
    case ko

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
        case .ko: "ko"
        }
    }

    var menuLabel: String {
        switch self {
        case .auto: L10n.tr("Auto")
        case .en: "English"
        case .zhHans: "简体中文"
        case .ko: "한국어"
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
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("CodexIsland: failed to restart app: %@", error.localizedDescription)
        }
    }
}
