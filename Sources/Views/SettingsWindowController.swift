import AppKit
import SwiftUI

/// Hand-rolled NSWindow for Settings instead of the SwiftUI `Settings` scene.
/// The Scene-based approach refused to actually hide the title bar on macOS
/// 13 (`.windowStyle(.hiddenTitleBar)` left a divider + title text behind),
/// and we want full control of the chrome anyway: transparent title bar,
/// traffic lights inset over our own header, fixed size, dark canvas.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(
            calibratedRed: 0.075, green: 0.077, blue: 0.090, alpha: 1
        )
        window.minSize = NSSize(width: 440, height: 420)
        // Hide the dock-stow button (we have no dock icon) but keep zoom
        // alongside resize handles so the user controls size.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window, !window.isVisible { window.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Give the latest values to the live strip the moment the window
        // appears — the user opened settings, so a fresh fetch is timely.
        UsageStore.shared.refresh()
        LaunchAtLoginStore.shared.refresh()
    }
}
