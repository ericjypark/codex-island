import AppKit
import SwiftUI

/// Full-screen frosted intro that covers the desktop, fades the brand
/// icons in at center, animates them to the notch position, then fades
/// the frost out. Closes itself when the sequence finishes; the
/// AppDelegate brings up the regular island window in its place.
@MainActor
final class SplashWindowController {
    let window: NSWindow
    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let screen = NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1728, height: 1117)

        window = BorderlessFloatingWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // .screenSaver (1000) sits above the island's .popUpMenu (101) so a
        // brief overlap during handoff doesn't reveal the island
        // mid-animation.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true

        let notch = NotchInfo.detect(from: screen)
        let host = NSHostingView(rootView: SplashView(
            screenSize: frame.size,
            notch: notch,
            onComplete: onComplete
        ))
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    func close() {
        window.close()
    }
}
