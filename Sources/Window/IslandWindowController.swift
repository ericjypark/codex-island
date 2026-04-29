import AppKit
import SwiftUI

@MainActor
final class IslandWindowController {
    let window: NSWindow

    static let windowSize = CGSize(width: 900, height: 280)

    init() {
        window = BorderlessFloatingWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // popUpMenu (101) draws above the system menu bar — needed so the panel
        // can extend into the menu-bar area without system items showing through.
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false
    }

    func show() {
        positionAtTop()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionAtTop() {
        guard let screen = NSScreen.main else { return }
        let size = Self.windowSize
        // screen.frame (NOT visibleFrame) so the panel can extend into the
        // notch / menu-bar area.
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
