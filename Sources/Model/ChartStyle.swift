import Foundation

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
