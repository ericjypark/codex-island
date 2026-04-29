import SwiftUI

/// Locked color tokens for CodexIsland.
enum IslandColor {
    /// #0047AB — loading sweep, glow halo.
    static let cobalt = Color(red: 0/255, green: 71/255, blue: 171/255)

    /// #CC785C — Anthropic terracotta. Claude logo + ring/bar fills.
    static let claude = Color(red: 204/255, green: 120/255, blue: 92/255)

    /// #5AA8F0 — OpenAI sky blue. Codex logo + ring/bar fills.
    static let codex = Color(red: 90/255, green: 168/255, blue: 240/255)

    /// #3DD68C — live status dot. Sits next to cobalt without clashing.
    static let liveTeal = Color(red: 61/255, green: 214/255, blue: 140/255)
}
