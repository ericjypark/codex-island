import Foundation

/// Visualization style for the cost screen — cycled via Cmd-click on the
/// expanded panel, mirroring how `StylePref` cycles chart styles on the
/// usage screen. Each style is a different way of bragging about the same
/// number: pure dollars, value extracted vs a $20/mo subscription baseline,
/// raw token throughput, or a cumulative trend line.
enum CostStyle: String, CaseIterable {
    case dollar
    case multi
    case tokens
    case spark

    var label: String {
        switch self {
        case .dollar: "USD"
        case .multi:  "VALUE"
        case .tokens: "TOKENS"
        case .spark:  "TREND"
        }
    }
}

@MainActor
final class CostStylePref: ObservableObject {
    static let shared = CostStylePref()

    private static let key = "MacIsland.costStyle"

    @Published var style: CostStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        self.style = CostStyle(rawValue: raw) ?? .dollar
    }

    func cycle() {
        let all = CostStyle.allCases
        if let i = all.firstIndex(of: style) {
            style = all[(i + 1) % all.count]
        }
    }
}
