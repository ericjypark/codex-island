import Foundation

enum UsageDisplayMode: String, CaseIterable {
    case used
    case remaining

    var label: String {
        switch self {
        case .used: return "Used"
        case .remaining: return "Remaining"
        }
    }
}

@MainActor
final class UsageDisplayModeStore: ObservableObject {
    static let shared = UsageDisplayModeStore()

    private static let key = "MacIsland.usageDisplayMode"

    @Published var mode: UsageDisplayMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        self.mode = UsageDisplayMode(rawValue: raw ?? "") ?? .used
    }
}
