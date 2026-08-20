import SwiftUI

enum AppAppearance: String, CaseIterable, Hashable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    static let key = "MacIsland.appearance"

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        appearance = AppAppearance(rawValue: raw) ?? .dark
    }
}
