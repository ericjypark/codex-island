import Foundation

/// How the cost screen sums tokens for the TOKENS hero. Anthropic's claude.ai
/// stats panel reports billable tokens only (input + output), while ccusage
/// — and CodexIsland by default — sum every token type that crossed the
/// wire, including cache reads. The two diverge by ~10× in normal Claude
/// Code usage because cache_read_input_tokens dwarfs the rest.
enum TokenCountMode: String, CaseIterable {
    /// input + output + cache_creation + cache_read. ccusage parity.
    case all
    /// input + output only. Matches Anthropic's stats dashboard.
    case billable

    var label: String {
        switch self {
        case .all:      L10n.tr("All tokens")
        case .billable: L10n.tr("Input + output")
        }
    }
}

@MainActor
final class TokenCountModeStore: ObservableObject {
    static let shared = TokenCountModeStore()

    private static let key = "MacIsland.tokenCountMode"

    @Published var mode: TokenCountMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        self.mode = TokenCountMode(rawValue: raw) ?? .all
    }
}
