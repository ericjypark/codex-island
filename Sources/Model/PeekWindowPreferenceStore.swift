import Foundation
import Combine

@MainActor
final class PeekWindowPreferenceStore: ObservableObject {
    static let shared = PeekWindowPreferenceStore()
    private static let key = "MacIsland.peekWindows"
    private let defaults: UserDefaults
    @Published private(set) var selections: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selections = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func preference(for provider: IslandProvider) -> PeekWindowPreference {
        PeekWindowPreference(rawValue: selections[provider.rawValue] ?? "") ?? .auto
    }

    func set(_ preference: PeekWindowPreference, for provider: IslandProvider) {
        guard provider.usesLegacyUsage else { return }
        selections[provider.rawValue] = preference.rawValue
        defaults.set(selections, forKey: Self.key)
    }
}
