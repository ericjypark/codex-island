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
    let islandModel: IslandModel

    init(rootView: IslandRootView, model: IslandModel) {
        self.islandModel = model
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init(rootView: IslandRootView) {
        fatalError("Use init(rootView:model:)")
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let b = bounds
        let size = islandModel.size
        let rect = NSRect(
            x: b.midX - size.width / 2,
            y: b.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.contains(point) ? super.hitTest(point) : nil
    }
}
