import AppKit
import SwiftUI

/// Locked color tokens for CodexIsland.
enum IslandColor {
    static let settingsBackground = Color(
        light: NSColor(calibratedWhite: 0.965, alpha: 1),
        dark: NSColor(calibratedRed: 0.020, green: 0.020, blue: 0.027, alpha: 1)
    )

    /// #0047AB — loading sweep, glow halo.
    static let cobalt = Color(red: 0/255, green: 71/255, blue: 171/255)

    /// #CC785C — Anthropic terracotta. Claude logo + ring/bar fills.
    static let claude = Color(red: 204/255, green: 120/255, blue: 92/255)

    /// #5AA8F0 — OpenAI sky blue. Codex logo + ring/bar fills.
    static let codex = Color(red: 90/255, green: 168/255, blue: 240/255)

    /// #3DD68C — live status dot. Sits next to cobalt without clashing.
    static let liveTeal = Color(red: 61/255, green: 214/255, blue: 140/255)

    /// #F5A524 — approaching-limit warning tint. Reads as "amber" against
    /// the black silhouette without competing with the cobalt halo. Used
    /// for the static glow + peek pill accent at warning severity.
    static let alertAmber = Color(red: 245/255, green: 165/255, blue: 36/255)

    /// #E5484D — approaching-limit critical tint. Saturated enough to read
    /// as "stop, you're cooked" without going full red-alert pure.
    static let alertRed = Color(red: 229/255, green: 72/255, blue: 77/255)
}

private extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
