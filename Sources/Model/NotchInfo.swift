import AppKit

struct NotchInfo {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// On notched MacBooks (M1 Pro / Max / Air 2022+) safeAreaInsets.top
    /// reports the *physical notch* height, while
    /// `screen.frame.maxY - screen.visibleFrame.maxY` reports the *visual
    /// menu bar* height. They normally match, but in "Scaled to avoid the
    /// notch" display mode (or with apps/scripts that shrink the menu bar)
    /// the menu bar is shorter than the notch and the silhouette would
    /// extend past the menu bar's bottom edge into app content.
    ///
    /// We size the silhouette to whichever is *smaller* so the bottom edge
    /// of the dark pill always lines up flush with the menu bar's bottom,
    /// regardless of display mode.
    ///
    /// auxiliaryTopLeftArea / auxiliaryTopRightArea give the menu-bar regions
    /// on either side of the notch; the notch's own width is
    /// (screen width - left - right).
    static func detect(from screen: NSScreen?) -> NotchInfo {
        guard let screen else {
            return NotchInfo(width: 200, height: menuBarFallback(), hasNotch: false)
        }
        let safeTop = screen.safeAreaInsets.top
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let visualHeight = chooseHeight(safeTop: safeTop, menuBarHeight: menuBarHeight)

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

    /// Pick the smallest non-zero candidate so we never overhang.
    private static func chooseHeight(safeTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        let candidates = [safeTop, menuBarHeight, NSStatusBar.system.thickness].filter { $0 > 0 }
        return candidates.min() ?? menuBarFallback()
    }

    /// Last-resort default when no screen / menu bar is available
    /// (auto-hide menu bar mode + no NSScreen, basically).
    private static func menuBarFallback() -> CGFloat {
        let t = NSStatusBar.system.thickness
        return t > 0 ? t : 24
    }
}
