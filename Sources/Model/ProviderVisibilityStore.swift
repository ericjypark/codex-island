import Foundation

@MainActor
final class ProviderVisibilityStore: ObservableObject {
    static let shared = ProviderVisibilityStore()
    static let selectionKey = "MacIsland.selectedProviders"

    @Published private(set) var selected: [IslandProvider]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.stringArray(forKey: Self.selectionKey) {
            self.selected = Self.normalized(saved.compactMap(IslandProvider.init(rawValue:)))
        } else {
            let legacy: [IslandProvider] = [.claude, .codex].filter {
                defaults.object(forKey: "MacIsland.\($0.rawValue)Visible") as? Bool ?? true
            }
            self.selected = Self.normalized(legacy)
        }
        persist()
    }

    var left: IslandProvider { selected.first ?? .claude }
    var right: IslandProvider? { selected.count == 2 ? selected[1] : nil }
    var claudeVisible: Bool { selected.contains(.claude) }
    var codexVisible: Bool { selected.contains(.codex) }

    static func normalized(_ providers: [IslandProvider]) -> [IslandProvider] {
        var result: [IslandProvider] = []
        for provider in providers where !result.contains(provider) {
            result.append(provider)
            if result.count == 2 { break }
        }
        return result.isEmpty ? [.claude] : result
    }

    func set(_ provider: IslandProvider?, at slot: Int) {
        guard (0...1).contains(slot) else { return }
        guard let provider else {
            guard slot == 1 else { return }
            selected = [left]
            persist()
            return
        }
        if let current = selected.firstIndex(of: provider) {
            if current != slot, selected.count == 2 { swap() }
            return
        }
        var next = selected
        if slot < next.count { next[slot] = provider } else { next.append(provider) }
        selected = Self.normalized(next)
        persist()
    }

    func swap() {
        guard selected.count == 2 else { return }
        selected.swapAt(0, 1)
        persist()
    }

    private func persist() {
        defaults.set(selected.map(\.rawValue), forKey: Self.selectionKey)
    }
}
