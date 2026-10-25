import Foundation

/// User preference for showing the provider logos beside the notch.
///
/// Default on preserves the current branded island. On notched displays,
/// turning it off removes the logo tabs from every collapsed state: at rest
/// the silhouette shrinks to the physical notch width, and the peek
/// (including "Always show usage") carries only the usage pills, which keep
/// their provider tint. Non-notched displays ignore the hidden state to
/// avoid leaving an empty synthetic pill at top-center.
@MainActor
final class LogoVisibilityStore: ObservableObject {
    static let shared = LogoVisibilityStore()

    private static let key = "MacIsland.providerLogosVisible"

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: Self.key) }
    }

    private init() {
        self.visible = Pref.seededBool(key: Self.key, default: true)
    }
}
