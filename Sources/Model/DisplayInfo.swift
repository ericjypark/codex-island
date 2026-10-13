import AppKit
import CoreGraphics

/// Per-screen value type. Bundles the facts the app needs to decide
/// where to render the island and how wide its silhouette should be.
///
/// `stableID` is `CGDisplayCreateUUIDFromDisplayID` stringified — it
/// survives plug/unplug. `isBuiltin` distinguishes the Mac's own
/// display from any external monitor. `notch` is the existing
/// per-screen notch detection result.
struct DisplayInfo {
    // Auto can resolve differently when app focus changes without a window move.
    // Only the controller's placement transaction updates the detection target.
    @MainActor static var positionedDisplay: (stableID: String, displayID: CGDirectDisplayID)?

    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let stableID: String
    let name: String
    let isBuiltin: Bool
    let notch: NotchInfo

    /// All currently-connected displays, in `NSScreen.screens` order.
    /// Drops any screen that doesn't expose a `CGDirectDisplayID` (rare;
    /// would happen for genuinely unidentifiable headless devices).
    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { Self.make(from: $0) }
    }

    /// Resolves the user's `IslandTargetDisplayStore.choice` against
    /// the current display set. Falls back to auto's logic when the
    /// chosen display is unplugged. Both `IslandWindowController` and
    /// `SettingsView` call this to ensure a single source of truth.
    @MainActor
    static func currentTarget() -> DisplayInfo? {
        let choice = IslandTargetDisplayStore.shared.choice
        let all = Self.all()
        switch choice {
        case .auto:
            return Self.autoPick(from: all)
        case .stable(let id):
            return all.first(where: { $0.stableID == id })
                ?? Self.autoPick(from: all)
        }
    }

    /// Today's auto logic, lifted from
    /// `IslandWindowController.targetScreen` — prefer a notched screen
    /// (so the silhouette covers the physical notch), else
    /// `NSScreen.main`, else any available display.
    private static func autoPick(from all: [DisplayInfo]) -> DisplayInfo? {
        all.first(where: \.notch.hasNotch)
            ?? all.first(where: { $0.screen == NSScreen.main })
            ?? all.first
    }

    private static func make(from screen: NSScreen) -> DisplayInfo? {
        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else {
            return nil
        }
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let cfuuid = unmanaged.takeRetainedValue()
        guard let stable = CFUUIDCreateString(nil, cfuuid) as String? else {
            return nil
        }
        return DisplayInfo(
            screen: screen,
            displayID: displayID,
            stableID: stable,
            name: screen.localizedName,
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            notch: NotchInfo.detect(from: screen)
        )
    }
}
