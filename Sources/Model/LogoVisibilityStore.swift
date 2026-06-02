import Foundation

/// User preference for showing the provider logos in the compact rest state.
///
/// Default on preserves the current branded island. Turning it off affects
/// only `.compact`: the rest-state silhouette shrinks to the notch width, so
/// loading sweeps and alert glow stay fitted to the hardware notch.
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
