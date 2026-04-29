import SwiftUI

enum ChartStyle: String, CaseIterable {
    case ring, bar, stepped, numeric, spark

    var label: String {
        switch self {
        case .ring: "Ring"
        case .bar: "Bar"
        case .stepped: "Stepped"
        case .numeric: "Numeric"
        case .spark: "Sparkline"
        }
    }
}

@MainActor
final class StylePref: ObservableObject {
    static let shared = StylePref()

    private static let styleKey = "MacIsland.chartStyle"

    @Published var style: ChartStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.styleKey) ?? ""
        self.style = ChartStyle(rawValue: raw) ?? .ring
    }

    func cycle() {
        let all = ChartStyle.allCases
        if let i = all.firstIndex(of: style) {
            style = all[(i + 1) % all.count]
        }
    }
}
