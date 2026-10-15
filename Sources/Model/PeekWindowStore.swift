import Foundation

/// Which rate window Claude and Codex show in the collapsed peek and track
/// for approaching-limit alerts. Only matters when the plan reports both a
/// 5-hour and a weekly window; single-window plans always use the one they
/// have.
@MainActor
final class PeekWindowStore: ObservableObject {
    static let shared = PeekWindowStore()

    static let choices: [UsageWindow] = [.fiveHour, .weekly]

    private static let key = "MacIsland.peekWindows.v1"

    @Published private(set) var windows: [IslandProvider: UsageWindow]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        var windows: [IslandProvider: UsageWindow] = [:]
        for (rawProvider, rawWindow) in stored {
            guard let provider = IslandProvider(rawValue: rawProvider),
                  let window = UsageWindow(rawValue: rawWindow),
                  Self.choices.contains(window) else { continue }
            windows[provider] = window
        }
        self.windows = windows
    }

    func window(for provider: IslandProvider) -> UsageWindow {
        windows[provider] ?? .fiveHour
    }

    func set(_ window: UsageWindow, for provider: IslandProvider) {
        guard Self.choices.contains(window), window != self.window(for: provider) else { return }
        windows[provider] = window
        let stored = Dictionary(uniqueKeysWithValues: windows.map { ($0.key.rawValue, $0.value.rawValue) })
        UserDefaults.standard.set(stored, forKey: Self.key)
    }
}
