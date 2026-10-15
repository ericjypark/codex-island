import Foundation

enum IslandProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, grok, antigravity, muse

    var id: String { rawValue }
    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .antigravity: return "Antigravity"
        case .muse: return "Muse Code"
        }
    }
    var usesLegacyUsage: Bool { self == .claude || self == .codex }
}
