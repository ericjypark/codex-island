import SwiftUI

enum ChartStyle: String, CaseIterable {
    case rails, ring, capacity, telemetry, stepped

    static let legacyStyles: [String: ChartStyle] = ["bar": .rails, "spark": .telemetry]

    var label: String {
        switch self {
        case .rails: L10n.tr("Rails")
        case .ring: L10n.tr("Ring")
        case .capacity: L10n.tr("Grid")
        case .telemetry: L10n.tr("History")
        case .stepped: L10n.tr("Stepped")
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
            defaultStyle: .ring,
            legacyStyles: ChartStyle.legacyStyles
        )
    }
}
