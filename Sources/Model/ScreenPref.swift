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

    /// Edge-clamped carousel — swiping past the rightmost page does
    /// nothing (no wrap to page 1), and likewise for the leftmost page.
    /// Matches the iOS Home Screen rubber-band feel where the user
    /// understands they've hit a boundary instead of teleporting around.
    func advance() {
        if screen == .usage { screen = .cost }
    }

    func rewind() {
        if screen == .cost { screen = .usage }
    }
}
