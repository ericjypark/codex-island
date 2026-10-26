import Foundation
import CryptoKit

/// Which rate window Claude and Codex show in the collapsed peek and track
/// for approaching-limit alerts. Only matters when the plan reports both a
/// 5-hour and a weekly window; single-window plans always use the one they
/// have. Kept per account when the credential names one, so switching
/// accounts restores that account's choice.
@MainActor
final class PeekWindowStore: ObservableObject {
    static let shared = PeekWindowStore()

    static let choices: [UsageWindow] = [.fiveHour, .weekly]

    private static let key = "MacIsland.peekWindows.v1"

    @Published private(set) var windows: [String: UsageWindow]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        windows = stored.compactMapValues { raw in
            UsageWindow(rawValue: raw).flatMap { Self.choices.contains($0) ? $0 : nil }
        }
    }

    /// Provider-wide when the credential names no account.
    nonisolated static func scope(_ provider: IslandProvider, usage: AppUsage) -> String {
        guard let accountID = usage.accountID else { return provider.rawValue }
        let hash = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(provider.rawValue).\(hash)"
    }

    /// Whether `scope` is final. Codex names its account only once a fetch
    /// reads the credential; until then a choice would land on the wrong key.
    /// Also false while cached usage still describes an account the local
    /// credential has since switched away from.
    nonisolated static func scopeResolved(_ provider: IslandProvider, usage: AppUsage,
                                          local: @autoclosure () -> AppUsage? = UsageFetcher.codexLocalIdentity()) -> Bool {
        guard provider == .codex else { return true }
        guard usage.accountResolved, let local = local() else { return false }
        return local.accountID == usage.accountID
    }

    func window(for provider: IslandProvider, usage: AppUsage) -> UsageWindow {
        windows[Self.scope(provider, usage: usage)] ?? .fiveHour
    }

    func set(_ window: UsageWindow, for provider: IslandProvider, usage: AppUsage) {
        guard Self.choices.contains(window), Self.scopeResolved(provider, usage: usage),
              window != self.window(for: provider, usage: usage) else { return }
        windows[Self.scope(provider, usage: usage)] = window
        UserDefaults.standard.set(windows.mapValues(\.rawValue), forKey: Self.key)
    }
}
