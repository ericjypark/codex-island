import Foundation
import Combine

/// User preference for the ambient halo.
///
/// Default off: the halo glow remains visible at rest. With low-power mode
/// on, it appears only while a fetch is in flight, the cursor is hovering the
/// island, or an alert is active. The cobalt loading sweep is limited to
/// in-flight refreshes regardless of this preference.
///
/// `effectiveEnabled` ORs the user toggle with macOS's system-wide Low
/// Power Mode. When the user enables battery saving in System Settings,
/// our LPM gating activates automatically — same convention Apple's own
/// apps follow. AC users see no change.
@MainActor
final class LowPowerModeStore: ObservableObject {
    static let shared = LowPowerModeStore()

    private static let key = "MacIsland.lowPowerMode"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    /// Mirrors `ProcessInfo.processInfo.isLowPowerModeEnabled`. Updated
    /// via NSProcessInfoPowerStateDidChange.
    @Published private(set) var systemLowPowerEnabled: Bool

    /// True if either the user opted in OR macOS reports system LPM is on.
    /// Use this in render-gating predicates instead of `enabled` directly.
    var effectiveEnabled: Bool { enabled || systemLowPowerEnabled }

    private var observer: NSObjectProtocol?

    private init() {
        // UserDefaults.bool returns false for missing keys, which matches our
        // intended default (off → continuous sweep).
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
        self.systemLowPowerEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let now = ProcessInfo.processInfo.isLowPowerModeEnabled
                if now != self.systemLowPowerEnabled {
                    self.systemLowPowerEnabled = now
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
