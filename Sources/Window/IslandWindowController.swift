import AppKit
import SwiftUI

@MainActor
final class IslandWindowController {
    let window: NSWindow
    let model: IslandModel
    private let host: IslandHostingView
    private var mouseMonitor: Any?
    private var trackingTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?

    static let windowSize = CGSize(width: 900, height: 280)

    init() {
        let notch = NotchInfo.detect(from: Self.targetScreen())
        self.model = IslandModel(notch: notch)

        window = BorderlessFloatingWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false

        host = IslandHostingView(
            rootView: IslandRootView(model: model),
            model: model
        )
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func show() {
        repositionForCurrentScreen()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        installMouseTracking()
        observeScreenChanges()
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Click-through for everything outside the visible shape. We watch cursor
    /// position globally and flip ignoresMouseEvents accordingly so clicks
    /// outside the notch pill go straight to whatever's underneath.
    ///
    /// The hitTest override on IslandHostingView is necessary but not
    /// sufficient — without the global monitor, the window still steals focus
    /// on click even when hitTest returns nil.
    private func installMouseTracking() {
        window.ignoresMouseEvents = true

        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.updateMouseEventsBasedOnCursor() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }

        // Polling safety net for the case where the cursor is already inside
        // the shape area at launch — no mouseMoved event would otherwise fire.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMouseEventsBasedOnCursor() }
        }
    }

    private func updateMouseEventsBasedOnCursor() {
        let cursor = NSEvent.mouseLocation
        let win = window.frame
        let local = NSPoint(x: cursor.x - win.minX, y: cursor.y - win.minY)

        let size = model.size
        let rect = NSRect(
            x: win.width / 2 - size.width / 2,
            y: win.height - size.height,
            width: size.width,
            height: size.height
        )
        let inside = rect.contains(local)
        if window.ignoresMouseEvents == inside {
            window.ignoresMouseEvents = !inside
        }
    }

    /// Anchor to the notched display so the island always sits over the
    /// physical notch — even when an external monitor is the active screen.
    /// Falls back to `NSScreen.main` on Macs without a notch.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionForCurrentScreen() }
        }
    }

    private func repositionForCurrentScreen() {
        guard let screen = Self.targetScreen() else { return }
        model.updateNotch(NotchInfo.detect(from: screen))
        let size = Self.windowSize
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
