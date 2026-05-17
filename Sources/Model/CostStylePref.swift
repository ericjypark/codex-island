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
        case .multi:  L10n.tr("VALUE")
        case .tokens: L10n.tr("TOKENS")
        case .spark:  L10n.tr("TREND")
        }
    }
}

@MainActor
final class CostStylePref: StylePreferenceStore<CostStyle> {
    static let shared = CostStylePref()

    private init() {
        super.init(
            styleKey: "MacIsland.costStyle",
            cycledKey: "MacIsland.costStyleCycled",
            defaultStyle: .dollar
        )
    }
}
