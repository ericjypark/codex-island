import SwiftUI

/// The locked type scale for CodexIsland. SF Pro everywhere, monospacedDigit
/// on every percentage so digits don't jiggle as values change.
///
/// Sizes (top-to-bottom in visual prominence):
///   38pt semibold mono — NumericChart big number
///   18pt semibold mono — chart values (ring / bar / stepped / spark)
///   13pt semibold      — provider titles ("Claude", "Codex")
///   11pt               — chart labels ("5h", "week"), live-status text
///   10pt mono          — footer captions ("resets in 3h", "synced 5s ago")
///   9pt bold mono      — chips (MAX / PLUS / style label), tracking 0.8
///
/// White-text ladder (foregroundStyle.opacity) for emphasis tiers:
///   1.0   — primary value text
///   0.78  — chip text
///   0.55  — labels / "synced" caption
///   0.42  — secondary hints
///   0.06  — hairline strokes / divider gradients
enum Typography {
    static let bigNumber = Font.system(size: 38, weight: .semibold).monospacedDigit()
    static let chartValue = Font.system(size: 18, weight: .semibold).monospacedDigit()
    static let providerTitle = Font.system(size: 13, weight: .semibold)
    static let label = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 10).monospaced()
    static let chip = Font.system(size: 9, weight: .bold).monospaced()
}
