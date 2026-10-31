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
    private var lastWheelPageChange: TimeInterval = 0

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

    /// Default macOS behavior on a non-key window: the first click is
    /// swallowed to activate/focus the window, the second click triggers the
    /// actual gesture. With our overlay model, the user is hovering over the
    /// notch from a different focused app (Terminal, Xcode) and expects the
    /// first click to expand the panel — not just bring the window to focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Two-finger trackpad swipe → page change. Only fires when the panel is
    /// expanded and the gesture is horizontal-dominant. Mouse-wheel ticks
    /// (no gesture phases, whatever their delta precision) change pages only
    /// when they are explicitly horizontal: Shift+wheel, the macOS
    /// convention, or a horizontal wheel such as a thumb wheel. Vertical
    /// ticks still pass through.
    override func scrollWheel(with event: NSEvent) {
        guard islandModel.state == .expanded else {
            super.scrollWheel(with: event)
            return
        }

        if shouldDeferScrollToNestedScrollView(event) {
            super.scrollWheel(with: event)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        // Phases, not `hasPreciseScrollingDeltas`, tell a wheel from a
        // trackpad: some mouse drivers smooth ticks into precise deltas but
        // never send phases, so they would otherwise wait for an `.ended`
        // that never comes.
        let isTick = event.phase == [] && event.momentumPhase == []
        if shift || isTick {
            if shift, event.momentumPhase != [] { return }
            guard let direction = WheelSwipe.direction(
                deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, shift: shift,
                now: event.timestamp, lastChange: lastWheelPageChange)
            else {
                if !shift { super.scrollWheel(with: event) }
                return
            }
            lastWheelPageChange = event.timestamp
            switch direction {
            case .advance: islandModel.advanceScreen()
            case .rewind: islandModel.rewindScreen()
            }
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
            islandModel.advanceScreen()
        } else {
            islandModel.rewindScreen()
        }
    }

    private func shouldDeferScrollToNestedScrollView(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard let target = super.hitTest(point) else { return false }

        var view: NSView? = target
        while let current = view {
            if current is NSScrollView { return true }
            view = current.superview
        }

        return false
    }
}
