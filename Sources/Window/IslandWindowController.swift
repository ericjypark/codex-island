import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController {
    let window: NSWindow
    let model: IslandModel
    private let host: IslandHostingView
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var trackingTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var subs: Set<AnyCancellable> = []
    private var hasSeenMouseEvent = false

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
        observeTargetChoice()
        observeOcclusion()
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = occlusionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        trackingTimer?.invalidate()
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
            Task { @MainActor in
                guard let self else { return }
                self.hasSeenMouseEvent = true
                self.invalidateTrackingTimerIfReady()
                self.updateMouseEventsBasedOnCursor()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }

        // Polling safety net for the case where the cursor is already inside
        // the shape area at launch — no mouseMoved event would otherwise fire.
        // Self-invalidates once any real mouseMoved arrives, so steady-state
        // doesn't pay the 10Hz timer cost forever.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMouseEventsBasedOnCursor() }
        }
    }

    private func invalidateTrackingTimerIfReady() {
        guard hasSeenMouseEvent, let timer = trackingTimer else { return }
        timer.invalidate()
        trackingTimer = nil
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

    @MainActor
    private static func targetScreen() -> NSScreen? {
        DisplayInfo.currentTarget()?.screen
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

    /// Pauses the LoadingSweep when the user can't see the island —
    /// fullscreen apps on a separate Space, the screen going to sleep,
    /// or anything else macOS reports as making the window invisible.
    /// The 30Hz TimelineView is the dominant idle-CPU cost; pausing it
    /// while occluded drops idle to ~0%.
    private func observeOcclusion() {
        // Seed the initial state — the notification doesn't fire on launch.
        WindowOcclusionStore.shared.update(
            isVisible: window.occlusionState.contains(.visible)
        )
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let visible = self.window.occlusionState.contains(.visible)
            Task { @MainActor in
                WindowOcclusionStore.shared.update(isVisible: visible)
            }
        }
    }

    private func observeTargetChoice() {
        IslandTargetDisplayStore.shared.$choice
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.repositionForCurrentScreen() }
            }
            .store(in: &subs)
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
