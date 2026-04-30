import Foundation

/// Which page of the expanded panel is currently active. Persisted across
/// launches so the app reopens on the last-viewed page.
@MainActor
final class ScreenPref: ObservableObject {
    static let shared = ScreenPref()

    enum Screen: String, CaseIterable {
        case usage
        case cost
    }

    private static let key = "MacIsland.screen"

    @Published var screen: Screen {
        didSet { UserDefaults.standard.set(screen.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        self.screen = Screen(rawValue: raw) ?? .usage
    }

    /// Two-page carousel — swipe left advances forward, swipe right rewinds.
    /// Wraps trivially since there are only two pages.
    func advance() {
        screen = (screen == .usage) ? .cost : .usage
    }

    func rewind() {
        screen = (screen == .cost) ? .usage : .cost
    }
}
