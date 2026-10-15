import AppKit

struct NotchInfo {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// Use the screen's safe-area inset, in points, for the physical notch
    /// height. Screens without a top inset use the visible menu-bar height.
    ///
    /// auxiliaryTopLeftArea / auxiliaryTopRightArea give the menu-bar regions
    /// on either side of the notch; the notch's own width is
    /// (screen width - left - right).
    static func detect(from screen: NSScreen?) -> NotchInfo {
        guard let screen else {
            return NotchInfo(width: IslandSpacingStore.compactWidth, height: menuBarFallback(), hasNotch: false)
        }
        let safeTop = screen.safeAreaInsets.top
        let visualHeight = visibleMenuBarHeight(of: screen)

        if safeTop > 0 {
            let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightW = screen.auxiliaryTopRightArea?.width ?? 0
            let width: CGFloat = (leftW > 0 && rightW > 0)
                ? screen.frame.width - leftW - rightW
                : 200
            return NotchInfo(width: width, height: visualHeight, hasNotch: true)
        }
        return NotchInfo(width: IslandSpacingStore.compactWidth, height: visualHeight, hasNotch: false)
    }

    private static func visibleMenuBarHeight(of screen: NSScreen) -> CGFloat {
        menuBarHeight(
            safeTop: screen.safeAreaInsets.top,
            visibleFrameDelta: screen.frame.maxY - screen.visibleFrame.maxY,
            statusBarThickness: NSStatusBar.system.thickness
        )
    }

    /// Pure height rule, separated from NSScreen so the test harness can
    /// drive it (see Tests/NotchHeightTests.swift).
    ///
    /// A positive safe-area inset is authoritative for notch coverage.
    /// The visibleFrame delta can be smaller or larger than that inset,
    /// so using it would leave a gap or overhang the physical notch.
    /// Keep the existing 1pt menu-bar correction for non-notched screens.
    static func menuBarHeight(
        safeTop: CGFloat,
        visibleFrameDelta: CGFloat,
        statusBarThickness: CGFloat
    ) -> CGFloat {
        if safeTop > 0 { return safeTop }
        let fromVisibleFrame = visibleFrameDelta - 1
        if fromVisibleFrame > 0 {
            return fromVisibleFrame
        }
        // Auto-hide menu bar: visibleFrame supplies no usable height.
        return statusBarThickness > 0 ? statusBarThickness : 24
    }

    private static func menuBarFallback() -> CGFloat {
        menuBarHeight(safeTop: 0, visibleFrameDelta: 0, statusBarThickness: NSStatusBar.system.thickness)
    }
}
