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

    /// Accumulated horizontal scroll delta for the in-flight two-finger swipe.
    /// Reset on `.began`, evaluated on `.ended`.
    private var swipeAccumX: CGFloat = 0
    private var swipeAccumY: CGFloat = 0

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

    /// Two-finger trackpad swipe → page change. Only fires when the panel is
    /// expanded and the gesture is horizontal-dominant. Uses
    /// `hasPreciseScrollingDeltas` to filter out mouse-wheel ticks (which
    /// shouldn't be page-changers — only gestures should).
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas,
              islandModel.state == .expanded else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .began {
            swipeAccumX = 0
            swipeAccumY = 0
        }
        swipeAccumX += event.scrollingDeltaX
        swipeAccumY += event.scrollingDeltaY

        guard event.phase == .ended else { return }

        // Threshold tuned to feel like a single deliberate swipe (~1/4 inch
        // of finger travel) without firing on a small horizontal nudge that
        // crept into a vertical scroll.
        let threshold: CGFloat = 60
        defer { swipeAccumX = 0; swipeAccumY = 0 }
        guard abs(swipeAccumX) > abs(swipeAccumY),
              abs(swipeAccumX) > threshold else { return }

        // Natural-scrolling convention: physical swipe-left → negative
        // deltaX → advance to next page (cost screen sits "to the right" of
        // the usage screen, like an iOS Home Screen page 2).
        if swipeAccumX < 0 {
            ScreenPref.shared.advance()
        } else {
            ScreenPref.shared.rewind()
        }
    }
}
