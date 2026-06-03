import Foundation

/// User preference for showing the provider logos in the compact rest state.
///
/// Default on preserves the current branded island. On notched displays,
/// turning it off affects only `.compact`: the rest-state silhouette shrinks
/// to the physical notch width, so loading sweeps and alert glow stay fitted
/// to the hardware notch. Non-notched displays ignore the hidden state to
/// avoid leaving an empty synthetic pill at top-center.
@MainActor
final class LogoVisibilityStore: ObservableObject {
    static let shared = LogoVisibilityStore()

    private static let key = "MacIsland.compactLogosVisible"

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: Self.key) }
    }

    private init() {
        self.visible = Pref.seededBool(key: Self.key, default: true)
    }
}
