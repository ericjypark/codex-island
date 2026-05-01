import Foundation

/// User preference for the ambient loading-sweep animation.
///
/// Default off: the cobalt orbit runs continuously, even when no fetch is in
/// progress. With low-power mode on, the sweep only renders while a fetch is
/// actually running — saving the per-frame angular-gradient + blur work the
/// rest of the time.
@MainActor
final class LowPowerModeStore: ObservableObject {
    static let shared = LowPowerModeStore()

    private static let key = "MacIsland.lowPowerMode"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    private init() {
        // UserDefaults.bool returns false for missing keys, which matches our
        // intended default (off → continuous sweep).
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
    }
}
