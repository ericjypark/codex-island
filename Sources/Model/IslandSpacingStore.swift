import Foundation
import SwiftUI

/// User preference for the silhouette width on Macs without a hardware
/// notch. On notched targets the preference is irrelevant — the model
/// uses the real notch width directly.
///
/// Default is `.compact` (100pt). Existing non-notch users see the
/// silhouette tighten on first launch after upgrade — silent
/// migration, no opt-in.
@MainActor
final class IslandSpacingStore: ObservableObject {
    static let shared = IslandSpacingStore()

    enum Mode: String {
        case compact
        case notchStyle

        /// Per-mode width, exposed on `Mode` (not on the store) so consumers
        /// can compute width from a known mode value without round-tripping
        /// through `IslandSpacingStore.shared.mode`. Critical for the
        /// `@Published` sink path: subscribers receive the new mode value
        /// *during* willSet, before the store's own property has been
        /// assigned — reading `shared.mode` there returns the *old* value
        /// and produces inverted widths. Using `mode.width` on the closure
        /// parameter avoids the race entirely.
        var width: CGFloat {
            switch self {
            case .compact:    return IslandSpacingStore.compactWidth
            case .notchStyle: return IslandSpacingStore.notchStyleWidth
            }
        }
    }

    /// Compact preset width — the new default for non-notch hardware.
    /// `nonisolated` so non-MainActor call sites (notably `NotchInfo`
    /// as a free `struct`) can read it. Trivially safe; a `CGFloat`
    /// literal with no shared mutable state.
    nonisolated static let compactWidth: CGFloat = 100

    /// Notch-style preset width — preserves the original look for
    /// users who prefer the wider silhouette.
    nonisolated static let notchStyleWidth: CGFloat = 200

    private static let key = "MacIsland.spacingMode"

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    var width: CGFloat { mode.width }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        self.mode = Mode(rawValue: raw ?? "") ?? .compact
    }
}
