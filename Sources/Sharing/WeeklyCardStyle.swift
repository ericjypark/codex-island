import SwiftUI

enum WeeklyCardFormat: String, CaseIterable, Identifiable {
    case feed, square, story
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feed: return "Feed · 4:5"
        case .square: return "Square · 1:1"
        case .story: return "Story · 9:16"
        }
    }
    var size: CGSize {
        switch self {
        case .feed: return CGSize(width: 540, height: 675)
        case .square: return CGSize(width: 540, height: 540)
        case .story: return CGSize(width: 540, height: 960)
        }
    }
    var pixelLabel: String { "1080 × \(Int(size.height * 2)) PNG" }
}

extension WeeklyCardTier {
    var theme: WeeklyCardTheme {
        switch self {
        case .white: return .paper
        case .black: return .midnight
        case .blue: return .cobalt
        }
    }
}

enum WeeklyCardTheme {
    case midnight, paper, cobalt

    var background: Color {
        switch self {
        case .midnight: return Color(red: 0.035, green: 0.044, blue: 0.052)
        case .paper: return Color(red: 0.956, green: 0.946, blue: 0.918)
        case .cobalt: return Color(red: 0.055, green: 0.17, blue: 0.79)
        }
    }
    var foreground: Color {
        self == .paper ? Color(red: 0.10, green: 0.15, blue: 0.19) : Color(red: 0.97, green: 0.96, blue: 0.91)
    }
    var secondary: Color { foreground.opacity(self == .paper ? 0.72 : 0.70) }
    var rule: Color { foreground.opacity(0.18) }

    func color(for provider: IslandProvider) -> Color {
        switch (self, provider) {
        case (.paper, .claude): return Color(red: 0.75, green: 0.30, blue: 0.20)
        case (.paper, .codex): return Color(red: 0.12, green: 0.38, blue: 0.79)
        case (.paper, .antigravity): return Color(red: 0.47, green: 0.32, blue: 0.71)
        case (.paper, .grok): return Color(red: 0.19, green: 0.30, blue: 0.30)
        case (_, .claude): return Color(red: 0.96, green: 0.57, blue: 0.42)
        case (_, .codex): return Color(red: 0.52, green: 0.80, blue: 0.98)
        case (_, .antigravity): return Color(red: 0.76, green: 0.66, blue: 0.98)
        case (_, .grok): return Color(red: 0.87, green: 0.96, blue: 0.73)
        }
    }
}
