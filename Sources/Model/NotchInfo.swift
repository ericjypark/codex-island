import AppKit

struct NotchInfo {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// On notched MacBooks (M1 Pro / Max / Air 2022+) safeAreaInsets.top is
    /// non-zero and equals the visible notch height. auxiliaryTopLeftArea /
    /// auxiliaryTopRightArea give the menu-bar regions on either side of the
    /// notch, so the notch's own width is (screen width - left - right).
    static func detect(from screen: NSScreen?) -> NotchInfo {
        guard let screen else {
            return NotchInfo(width: 200, height: 32, hasNotch: false)
        }
        let safeTop = screen.safeAreaInsets.top
        if safeTop > 0 {
            let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightW = screen.auxiliaryTopRightArea?.width ?? 0
            let width: CGFloat = (leftW > 0 && rightW > 0)
                ? screen.frame.width - leftW - rightW
                : 200
            return NotchInfo(width: width, height: safeTop, hasNotch: true)
        }
        return NotchInfo(width: 200, height: 28, hasNotch: false)
    }
}
