import Foundation

struct QuotaSelection: Codable, Equatable {
    var groupID: String?
    var metricIDs: [String]?
    var primaryID: String?
}

@MainActor
final class ProviderQuotaPreferences: ObservableObject {
    static let shared = ProviderQuotaPreferences()
    @Published private(set) var selections: [String: QuotaSelection]
    private let defaults: UserDefaults
    private static let key = "MacIsland.providerQuotaPreferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selections = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: QuotaSelection].self, from: $0) } ?? [:]
    }

    func selection(for scope: String) -> QuotaSelection {
        selections[scope] ?? QuotaSelection()
    }

    func save(_ selection: QuotaSelection, for scope: String) {
        selections[scope] = selection
        if let data = try? JSONEncoder().encode(selections) { defaults.set(data, forKey: Self.key) }
    }

    static func resolve(_ usage: ConnectedUsage, selection: QuotaSelection) -> [ConnectedLimit] {
        let groups = Array(Set(usage.limits.map(\.groupID))).sorted()
        let preferred = groups.first { id in
            usage.limits.contains { $0.groupID == id && ($0.groupLabel ?? "").localizedCaseInsensitiveContains("gemini") }
        }
        guard let group = selection.groupID ?? preferred ?? groups.first else { return [] }
        let candidates = usage.limits.filter { $0.groupID == group }.sorted {
            if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
            return $0.id < $1.id
        }
        guard let ids = selection.metricIDs else { return Array(candidates.prefix(2)) }
        guard groups.contains(group) else { return [] }
        return Array(ids.prefix(2)).map { id in
            candidates.first { $0.id == id }
                ?? ConnectedLimit(id: id, label: "Unavailable", usedFraction: nil, resetAt: nil,
                                  groupID: group, groupLabel: candidates.first?.groupLabel)
        }
    }

    static func primary(_ limits: [ConnectedLimit], selection: QuotaSelection) -> ConnectedLimit? {
        if let id = selection.primaryID { return limits.first { $0.id == id } }
        return limits.first
    }
}
