import Foundation

/// User preference for keeping the peek-state percentage pills visible at
/// rest, without requiring a hover.
///
/// Default off: the pills only appear during hover/peek, then collapse with
/// the silhouette back to compact. With this on, the island launches into
/// `.peek` and stays there — hover-out keeps the pill visible, expanded-out
/// returns to peek instead of compact.
@MainActor
final class AlwaysShowUsageStore: ObservableObject {
    static let shared = AlwaysShowUsageStore()

    private static let key = "MacIsland.alwaysShowUsage"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    private init() {
        // UserDefaults.bool returns false for missing keys, which matches our
        // intended default (off → preserves the existing hover-only behavior
        // for users who upgrade).
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
    }
}
