import Foundation

/// User-controlled poll cadence for `UsageStore`. The Anthropic
/// `/api/oauth/usage` endpoint is heavily rate-limited per token, so we
/// only expose 5min / 15min / 30min — never anything below 5min.
@MainActor
final class RefreshIntervalStore: ObservableObject {
    static let shared = RefreshIntervalStore()

    private static let key = "MacIsland.refreshInterval"
    static let allowed: [Int] = [300, 900, 1800]

    @Published var seconds: Int {
        didSet { UserDefaults.standard.set(seconds, forKey: Self.key) }
    }

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.key)
        self.seconds = Self.allowed.contains(stored) ? stored : 300
    }
}
