import AppKit

struct NotchInfo {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// `screen.frame.maxY - screen.visibleFrame.maxY` reports the actual
    /// pixel distance between the top of the screen and the top of the app
    /// content area — i.e., where the menu bar visually ends. Use that as
    /// the silhouette height so the dark pill's bottom edge always sits
    /// flush with the menu bar's bottom, in both default notched mode
    /// (≈37pt) and "Scaled to avoid the notch" mode (≈24pt, menu bar sits
    /// below the dead notch area).
    ///
    /// `safeAreaInsets.top` reports the *physical notch* and can disagree
    /// with the visible menu bar in scaled modes — use it only as a
    /// fallback when visibleFrame is unmeasurable (auto-hide menu bar).
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
    /// `visibleFrame.maxY` sits 1pt BELOW the menu bar's bottom edge (AppKit
    /// reserves that strip), so the raw frame/visibleFrame delta over-reports
    /// the bar by 1pt — measured 39pt against a 38pt bar on a notched 14".
    /// That extra point made the silhouette's bottom edge dip into app
    /// content below the menu bar. Correct for the gap, and clamp to the
    /// physical notch height so a stale visibleFrame reading (login, display
    /// wake) can never push the silhouette below the real bar either.
    static func menuBarHeight(
        safeTop: CGFloat,
        visibleFrameDelta: CGFloat,
        statusBarThickness: CGFloat
    ) -> CGFloat {
        let fromVisibleFrame = visibleFrameDelta - 1
        if fromVisibleFrame > 0 {
            return safeTop > 0 ? min(fromVisibleFrame, safeTop) : fromVisibleFrame
        }
        // Auto-hide menu bar — visibleFrame == frame, so derive from the
        // physical notch (if present) or the system status bar thickness.
        if safeTop > 0 { return safeTop }
        return statusBarThickness > 0 ? statusBarThickness : 24
    }

    private static func menuBarFallback() -> CGFloat {
        menuBarHeight(safeTop: 0, visibleFrameDelta: 0, statusBarThickness: NSStatusBar.system.thickness)
    }
}
