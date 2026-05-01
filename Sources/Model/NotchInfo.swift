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
            return NotchInfo(width: 200, height: menuBarFallback(), hasNotch: false)
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
        return NotchInfo(width: 200, height: visualHeight, hasNotch: false)
    }

    private static func visibleMenuBarHeight(of screen: NSScreen) -> CGFloat {
        let fromVisibleFrame = screen.frame.maxY - screen.visibleFrame.maxY
        if fromVisibleFrame > 0 { return fromVisibleFrame }
        // Auto-hide menu bar — visibleFrame == frame, so derive from the
        // physical notch (if present) or the system status bar thickness.
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return menuBarFallback()
    }

    private static func menuBarFallback() -> CGFloat {
        let t = NSStatusBar.system.thickness
        return t > 0 ? t : 24
    }
}
