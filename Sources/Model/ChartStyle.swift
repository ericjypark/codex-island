import SwiftUI

enum ChartStyle: String, CaseIterable {
    case ring, bar, stepped, numeric, spark

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .bar: return "Bar"
        case .stepped: return "Stepped"
        case .numeric: return "Numeric"
        case .spark: return "Sparkline"
        }
    }
}

@MainActor
final class StylePref: StylePreferenceStore<ChartStyle> {
    static let shared = StylePref()

    private init() {
        super.init(
            styleKey: "MacIsland.chartStyle",
            cycledKey: "MacIsland.hasCycledStyle",
            defaultStyle: .ring
        )
    }
}
