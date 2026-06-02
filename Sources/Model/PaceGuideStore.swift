import Foundation

/// User preference for showing the reset-window pace guide in usage charts.
///
/// Default off so upgrading users keep the original cleaner charts until
/// they opt in from General settings.
@MainActor
final class PaceGuideStore: ObservableObject {
    static let shared = PaceGuideStore()

    private static let key = "MacIsland.paceGuideEnabled"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    private init() {
        self.enabled = Pref.seededBool(key: Self.key, default: false)
    }
}
