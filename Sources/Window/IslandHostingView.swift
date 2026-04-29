import AppKit
import SwiftUI

/// Hosting view that only captures mouse events when the cursor is over the
/// visible island shape. Anywhere else inside the window's frame, hitTest
/// returns nil so clicks pass through to whatever's underneath.
///
/// Pair with the global+local NSEvent.mouseMoved monitors in
/// IslandWindowController — those toggle window.ignoresMouseEvents based on
/// cursor position. Together: hitTest stops focus-steal *during* a click,
/// the global monitor stops it *before* the click even reaches us.
final class IslandHostingView: NSHostingView<IslandRootView> {
    /// Updated by the window controller whenever the visible shape morphs.
    var currentShapeSize: CGSize = .zero

    init(rootView: IslandRootView, initialShapeSize: CGSize) {
        self.currentShapeSize = initialShapeSize
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init(rootView: IslandRootView) {
        fatalError("Use init(rootView:initialShapeSize:)")
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let b = bounds
        let size = currentShapeSize
        let rect = NSRect(
            x: b.midX - size.width / 2,
            y: b.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.contains(point) ? super.hitTest(point) : nil
    }
}
