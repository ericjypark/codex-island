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
    private var sessionResignObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?
    private var subs: Set<AnyCancellable> = []
    private var hasSeenMouseEvent = false
    private var isMouseInsideIsland = false
    private var cmdQMonitor: Any?
    private var visibility = IslandVisibilityState()

    static let windowSize = CGSize(width: 900, height: 360)

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
        installMouseTracking()
        observeScreenChanges()
        observeTargetChoice()
        observeOcclusion()
        observeSessionState()
        observeVisibility()
        if !visibility.shouldHide { NSApp.activate(ignoringOtherApps: true) }
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = occlusionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = sessionResignObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = sessionActiveObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = cmdQMonitor { NSEvent.removeMonitor(m) }
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

    private func updateMouseEventsBasedOnCursor(activateOnEntry: Bool = true) {
        guard visibility.allowsMouseInteraction(windowIsVisible: window.isVisible) else {
            suspendMouseInteraction()
            return
        }
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
        if inside, cmdQMonitor == nil {
            cmdQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event) ?? event
            }
        } else if !inside, let monitor = cmdQMonitor {
            NSEvent.removeMonitor(monitor)
            cmdQMonitor = nil
        }
        // Restoring click access must not focus the app or consume the next
        // real pointer entry. Keyboard handling remains gated by isKeyWindow.
        guard activateOnEntry else { return }
        if inside != isMouseInsideIsland {
            isMouseInsideIsland = inside
            if inside {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKey()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard visibility.allowsMouseInteraction(windowIsVisible: window.isVisible),
              window.isKeyWindow else { return event }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock])
        if modifiers == .command, event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return nil
        }

        guard model.state == .expanded else { return event }

        if modifiers == .command,
           let character = event.charactersIgnoringModifiers,
           let index = ["1", "2", "3"].firstIndex(of: character) {
            model.showScreen(ScreenPref.Screen.allCases[index])
            return nil
        }

        let navigationModifiers = modifiers.subtracting([.function, .numericPad, .capsLock])
        guard navigationModifiers.isEmpty else { return event }
        switch event.keyCode {
        case 123:
            model.rewindScreen()
            return nil
        case 124:
            model.advanceScreen()
            return nil
        default:
            return event
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
            Task { @MainActor in
                guard let self else { return }
                WindowOcclusionStore.shared.update(
                    isVisible: !self.visibility.shouldHide && self.window.occlusionState.contains(.visible)
                )
            }
        }
    }

    /// Hides the island when the screen locks so it doesn't ride the
    /// lock-screen slide animation (which makes the notch appear to fall).
    /// DistributedNotificationCenter "com.apple.screenIsLocked" fires as soon
    /// as the lock is initiated, before the slide animation completes.
    private func observeSessionState() {
        let dc = DistributedNotificationCenter.default()
        sessionResignObserver = dc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.visibility.isSessionLocked = true
                self?.applyVisibility()
            }
        }
        sessionActiveObserver = dc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                GameModeStore.shared.refresh()
                FullscreenStore.shared.refresh()
                self?.visibility.isSessionLocked = false
                self?.applyVisibility()
            }
        }
    }

    private func observeVisibility() {
        let store = GameModeStore.shared
        let fullscreen = FullscreenStore.shared
        store.$isActive.combineLatest(store.$hideDuringGameMode,
                                      fullscreen.$isActive, fullscreen.$hideInFullscreen)
            .sink { [weak self] active, enabled, isFullscreen, hideInFullscreen in
                guard let self else { return }
                self.visibility.isGameModeActive = active
                self.visibility.hideDuringGameMode = enabled
                self.visibility.isFullscreen = isFullscreen
                self.visibility.hideInFullscreen = hideInFullscreen
                self.applyVisibility()
            }
            .store(in: &subs)
    }

    private func applyVisibility() {
        model.isSuppressed = visibility.shouldHide
        if visibility.shouldHide {
            suspendMouseInteraction()
            model.setState(AlwaysShowUsageStore.shared.enabled ? .peek : .compact)
            window.orderOut(nil)
            WindowOcclusionStore.shared.update(isVisible: false)
            return
        }
        guard !window.isVisible else { return }
        window.alphaValue = 1
        window.orderFrontRegardless()
        updateMouseEventsBasedOnCursor(activateOnEntry: false)
        WindowOcclusionStore.shared.update(isVisible: window.occlusionState.contains(.visible))
    }

    private func suspendMouseInteraction() {
        window.ignoresMouseEvents = true
        isMouseInsideIsland = false
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let monitor = cmdQMonitor {
            NSEvent.removeMonitor(monitor)
            cmdQMonitor = nil
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
        FullscreenStore.shared.refresh()
        guard let screen = Self.targetScreen() else { return }
        model.updateNotch(NotchInfo.detect(from: screen))
        let size = Self.windowSize
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
