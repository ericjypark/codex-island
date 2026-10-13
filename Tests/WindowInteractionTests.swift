import AppKit
import Combine

// Compile the real controller against window/input spies. No windows are
// displayed, system input is observed or injected, or app activation is sent.
#if !FULLSCREEN_PLACEMENT_TESTS
@main
@MainActor
struct WindowInteractionTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                exit(1)
            }
            checks += 1
        }
        let inside = NSPoint(x: 450, y: 350)
        let outside = NSPoint(x: 20, y: 20)
        NSEvent.mouseLocation = inside
        GameModeStore.shared.isActive = true
        DisplayInfo.target = DisplayInfo(screen: NSScreen(
            frame: NSRect(x: 0, y: 0, width: 900, height: 360)
        ))
        let controller = IslandWindowController()
        controller.show()
        let window = controller.window
        check(FullscreenStore.shared.refreshedDisplayID == "0.0",
              "Initial placement publishes its display before refreshing fullscreen")
        check(!window.isVisible && window.ignoresMouseEvents, "Launch while suppressed blocks clicks")
        check(NSApp.activations == 0 && window.keyRequests == 0, "Suppressed launch does not focus")

        GameModeStore.shared.isActive = false
        check(window.isVisible && !window.ignoresMouseEvents,
              "Restoring beneath a stationary cursor accepts the first click without a mouse move")
        check(NSApp.activations == 0 && window.keyRequests == 0, "Restoration preserves foreground focus")
        check(NSEvent.keyMonitorCount == 1, "Stationary first click has keyboard handling ready")
        let quit = NSEvent(modifierFlags: .command, charactersIgnoringModifiers: "q")
        check(NSEvent.deliverKey(quit) != nil && NSApp.terminations == 0,
              "Prepared keyboard monitor ignores keys while the island is not key")
        window.isKeyWindow = true // Simulate the focus granted by a deliberate click.
        _ = NSEvent.deliverKey(quit)
        check(NSApp.terminations == 1, "First click enables shortcuts without requiring mouse movement")
        window.isKeyWindow = false

        NSEvent.deliverMouseMove()
        await settle()
        check(NSApp.activations == 1 && window.keyRequests == 1,
              "Passive restoration does not consume the next real pointer entry")
        check(NSEvent.keyMonitorCount == 1, "Pointer entry does not duplicate the prepared keyboard monitor")
        NSEvent.deliverMouseMove()
        await settle()
        check(NSApp.activations == 1 && window.keyRequests == 1, "Movement inside does not refocus repeatedly")
        NSEvent.mouseLocation = outside
        NSEvent.deliverMouseMove()
        await settle()
        check(window.ignoresMouseEvents && NSEvent.keyMonitorCount == 0, "Pointer exit restores click-through")

        for alwaysShow in [false, true] {
            AlwaysShowUsageStore.shared.enabled = alwaysShow
            for cursor in [inside, outside] {
                for trigger in 0..<2 {
                    if trigger == 0 { GameModeStore.shared.isActive = true }
                    else { FullscreenStore.shared.isActive = true }
                    check(!window.isVisible && window.ignoresMouseEvents && NSEvent.keyMonitorCount == 0,
                          "Both suppressors disable the window and its keyboard monitor")
                    NSEvent.mouseLocation = cursor
                    NSEvent.deliverMouseMove()
                    await settle()
                    let activations = NSApp.activations
                    let keyRequests = window.keyRequests
                    if trigger == 0 { GameModeStore.shared.isActive = false }
                    else { FullscreenStore.shared.isActive = false }
                    check(window.isVisible && window.ignoresMouseEvents == (cursor == outside),
                          "Restore recomputes click access for the current pointer in compact and peek modes")
                    check(NSApp.activations == activations && window.keyRequests == keyRequests,
                          "No restoration path activates the app or makes the island key")
                    check(NSEvent.keyMonitorCount == (cursor == inside ? 1 : 0),
                          "Only the island's clickable region prepares a keyboard monitor")
                }
            }
        }

        NSEvent.mouseLocation = inside
        GameModeStore.shared.isActive = true
        FullscreenStore.shared.isActive = true
        GameModeStore.shared.isActive = false
        check(!window.isVisible && window.ignoresMouseEvents, "One remaining suppressor still blocks input")
        FullscreenStore.shared.isActive = false
        check(!window.ignoresMouseEvents, "Clearing the final suppressor restores stationary click access")

        GameModeStore.shared.isActive = true
        let frontsBeforeLock = window.frontRequests
        DistributedNotificationCenter.default().post(name: .init("com.apple.screenIsLocked"), object: nil)
        GameModeStore.shared.isActive = false
        check(!window.isVisible && window.frontRequests == frontsBeforeLock,
              "Lock notification sets its gate before a queued Game Mode ending can reveal the window")
        await settle()
        check(!window.isVisible && window.ignoresMouseEvents, "Lock suspends interaction")
        let activations = NSApp.activations
        let keyRequests = window.keyRequests
        DistributedNotificationCenter.default().post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        await settle()
        check(window.isVisible && !window.ignoresMouseEvents, "Unlock also restores stationary click access")
        check(NSApp.activations == activations && window.keyRequests == keyRequests, "Unlock preserves focus")

        NSEvent.mouseLocation = outside
        FullscreenStore.shared.isCheckingFullscreen = true
        do {
            let pendingController = IslandWindowController()
            let activations = NSApp.activations
            pendingController.show()
            check(!pendingController.window.isVisible && pendingController.window.ignoresMouseEvents,
                  "Launch waits for the first asynchronous borderless result")
            check(NSApp.activations == activations && pendingController.window.keyRequests == 0,
                  "Pending startup cannot activate the island or change the foreground detection context")
            FullscreenStore.shared.isActive = true
            FullscreenStore.shared.isCheckingFullscreen = false
            check(!pendingController.window.isVisible, "A fullscreen startup result never reveals the window")
            FullscreenStore.shared.isActive = false
            check(pendingController.window.isVisible && NSApp.activations == activations,
                  "A later clear result restores the window without activation")
        }
        FullscreenStore.shared.isCheckingFullscreen = true
        DistributedNotificationCenter.default().post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        await settle()
        check(!window.isVisible && window.ignoresMouseEvents,
              "Unlock cannot reveal an island while its borderless recheck is pending")
        FullscreenStore.shared.isActive = true
        FullscreenStore.shared.isCheckingFullscreen = false
        check(!window.isVisible, "Fullscreen reply replaces the unlock gate without a flash")
        FullscreenStore.shared.isActive = false

        for alwaysShow in [false, true] {
            AlwaysShowUsageStore.shared.enabled = alwaysShow
            for transient in [IslandModel.State.peek, .expanded] {
                if alwaysShow && transient == .peek { continue }
                GameModeStore.shared.isActive = true
                controller.model.setState(transient)
                NSEvent.mouseLocation = transient == .peek ? NSPoint(x: 650, y: 350) : NSPoint(x: 450, y: 250)
                let activations = NSApp.activations
                let keyRequests = window.keyRequests
                GameModeStore.shared.isActive = false
                check(controller.model.state == (alwaysShow ? .peek : .compact),
                      "Restoration resets hidden pulse/expansion state before displaying the island")
                check(window.ignoresMouseEvents && NSEvent.keyMonitorCount == 0,
                      "A stationary pointer in discarded transient bounds retains click-through")
                check(NSApp.activations == activations && window.keyRequests == keyRequests,
                      "Resetting hidden transient state preserves foreground focus")
            }
        }

        for alwaysShow in [false, true] {
            AlwaysShowUsageStore.shared.enabled = alwaysShow
            for clearsFullscreen in [false, true] {
                for screenNotification in [false, true] {
                    for pointerOnNewDisplay in [false, true] {
                        FullscreenStore.shared.refreshedState = nil
                        FullscreenStore.shared.isActive = true
                        DisplayInfo.target = DisplayInfo(screen: NSScreen(
                            frame: NSRect(x: 0, y: 0, width: 900, height: 360)
                        ))
                        NotificationCenter.default.post(
                            name: NSApplication.didChangeScreenParametersNotification, object: nil
                        )
                        await settle()
                        NSEvent.mouseLocation = NSPoint(x: pointerOnNewDisplay ? 2450 : 450, y: 350)
                        DisplayInfo.target = DisplayInfo(screen: NSScreen(
                            frame: NSRect(x: 2000, y: 0, width: 900, height: 360)
                        ))
                        FullscreenStore.shared.refreshedState = !clearsFullscreen
                        let activations = NSApp.activations
                        let keyRequests = window.keyRequests
                        if screenNotification {
                            NotificationCenter.default.post(
                                name: NSApplication.didChangeScreenParametersNotification, object: nil
                            )
                        } else {
                            IslandTargetDisplayStore.shared.choice += 1
                        }
                        await settle()
                        check(window.frame.minX == 2000 && window.isVisible == clearsFullscreen,
                              "Display changes move the island and preserve fullscreen suppression")
                        check(FullscreenStore.shared.refreshedDisplayID == "2000.0",
                              "Display notification and explicit selection refresh against the positioned display")
                        let acceptsClicks = clearsFullscreen && pointerOnNewDisplay
                        check(window.ignoresMouseEvents == !acceptsClicks,
                              "Stationary click access follows the final display position in compact and peek modes")
                        check(NSEvent.keyMonitorCount == (acceptsClicks ? 1 : 0),
                              "Display changes prepare shortcuts only beneath the final clickable region")
                        check(NSApp.activations == activations && window.keyRequests == keyRequests,
                              "Display changes never activate the app or make the island key")
                    }
                }
            }
        }
        let placedID = FullscreenStore.shared.refreshedDisplayID
        let placedFrame = window.frame
        DisplayInfo.target = DisplayInfo(screen: NSScreen(
            frame: NSRect(x: 4000, y: 0, width: 900, height: 360)
        ))
        FullscreenStore.shared.refresh()
        check(window.frame == placedFrame && FullscreenStore.shared.refreshedDisplayID == placedID,
              "Auto resolving another active display cannot retarget fullscreen without moving the island")
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await settle()
        check(window.frame.minX == 4000 && FullscreenStore.shared.refreshedDisplayID == "4000.0",
              "Display reconfiguration moves the island and fullscreen target together")
        DisplayInfo.target = nil
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await settle()
        check(FullscreenStore.shared.refreshedDisplayID == nil,
              "No connected target clears fullscreen placement instead of reading an unrelated display")
        print("PASS \(checks) window interaction regression checks")
    }

    static func settle() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

#endif

final class NSWindow: NSObject {
    enum Style { case borderless, fullSizeContentView }
    enum Backing { case buffered }
    enum Level { case popUpMenu }
    enum Behavior { case canJoinAllSpaces, stationary, ignoresCycle }
    static let didChangeOcclusionStateNotification = Notification.Name("WindowInteractionTests.occlusion")
    var frame: NSRect
    var isVisible = false
    var isKeyWindow = false
    var keyRequests = 0
    var ignoresMouseEvents = true
    var isOpaque = false
    var backgroundColor = NSColor.clear
    var hasShadow = false
    var level = Level.popUpMenu
    var collectionBehavior: [Behavior] = []
    var isMovable = false
    var contentView: IslandHostingView?
    var alphaValue: CGFloat = 1
    var occlusionState: AppKit.NSWindow.OcclusionState { isVisible ? [.visible] : [] }
    init(contentRect: NSRect, styleMask: [Style], backing: Backing, defer: Bool) { frame = contentRect }
    var frontRequests = 0
    func orderFrontRegardless() { frontRequests += 1; isVisible = true }
    func orderOut(_ sender: Any?) { isVisible = false; isKeyWindow = false }
    func makeKey() { keyRequests += 1; isKeyWindow = true }
    func setFrame(_ frame: NSRect, display: Bool) { self.frame = frame }
}
typealias BorderlessFloatingWindow = NSWindow

final class NSApplication {
    static let didChangeScreenParametersNotification = Notification.Name("WindowInteractionTests.screens")
    var activations = 0
    var terminations = 0
    func activate(ignoringOtherApps: Bool) { activations += 1 }
    func terminate(_ sender: Any?) { terminations += 1 }
}
let NSApp = NSApplication()

enum DistributedNotificationCenter {
    private static let center = NotificationCenter()
    static func `default`() -> NotificationCenter { center }
}

final class NSEvent {
    typealias ModifierFlags = AppKit.NSEvent.ModifierFlags
    typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
    static var mouseLocation = NSPoint.zero
    static var monitors: [UUID: (EventTypeMask, (NSEvent) -> NSEvent?)] = [:]
    static var keyMonitorCount: Int { monitors.values.filter { $0.0.contains(.keyDown) }.count }
    let modifierFlags: ModifierFlags
    let charactersIgnoringModifiers: String?
    let keyCode: UInt16 = 0
    init(modifierFlags: ModifierFlags = [], charactersIgnoringModifiers: String? = nil) {
        self.modifierFlags = modifierFlags
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }
    static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        addLocalMonitorForEvents(matching: matching) { handler($0); return $0 }
    }
    static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let id = UUID()
        monitors[id] = (matching, handler)
        return id
    }
    static func removeMonitor(_ monitor: Any) {
        if let id = monitor as? UUID { monitors.removeValue(forKey: id) }
    }
    static func deliverMouseMove() {
        // A real event reaches either the global or local monitor, not both.
        _ = monitors.values.first(where: { $0.0.contains(.mouseMoved) })?.1(NSEvent())
    }
    static func deliverKey(_ event: NSEvent) -> NSEvent? {
        for (_, handler) in monitors.values.filter({ $0.0.contains(.keyDown) }) {
            if handler(event) == nil { return nil }
        }
        return event
    }
}

final class IslandHostingView {
    enum Autoresizing { case width, height }
    var autoresizingMask: [Autoresizing] = []
    init(rootView: IslandRootView, model: IslandModel) {}
}
struct IslandRootView { let model: IslandModel }
struct NSScreen { let frame: NSRect }
struct NotchInfo { static func detect(from: NSScreen?) -> NotchInfo { NotchInfo() } }
struct DisplayInfo {
    let screen: NSScreen
    var stableID: String { String(describing: screen.frame.minX) }
    var displayID: CGDirectDisplayID { CGDirectDisplayID(screen.frame.minX) }
    static var target: DisplayInfo?
    static var positionedDisplay: (stableID: String, displayID: CGDirectDisplayID)?
    static func currentTarget() -> DisplayInfo? { target }
}
@MainActor final class IslandModel {
    enum State { case compact, peek, expanded }
    var state = State.compact
    var isSuppressed = false
    var size = CGSize(width: 280, height: 32)
    init(notch: NotchInfo) {}
    func updateNotch(_ notch: NotchInfo) {}
    func setState(_ state: State) {
        self.state = state
        size = CGSize(width: state == .compact ? 280 : (state == .peek ? 420 : 600),
                      height: state == .expanded ? 200 : 32)
    }
    func showScreen(_ screen: ScreenPref.Screen) {}
    func rewindScreen() {}
    func advanceScreen() {}
}
enum ScreenPref { enum Screen: CaseIterable { case usage, cost, overview } }
@MainActor final class AlwaysShowUsageStore { static let shared = AlwaysShowUsageStore(); var enabled = false }
@MainActor final class WindowOcclusionStore {
    static let shared = WindowOcclusionStore()
    func update(isVisible: Bool) {}
}
@MainActor final class IslandTargetDisplayStore {
    static let shared = IslandTargetDisplayStore()
    @Published var choice = 0
}
@MainActor final class GameModeStore {
    static let shared = GameModeStore()
    @Published var isActive = false
    @Published var hideDuringGameMode = true
    func refresh() {}
}
#if !FULLSCREEN_PLACEMENT_TESTS
@MainActor final class FullscreenStore {
    static let shared = FullscreenStore()
    @Published var isActive = false
    @Published var isCheckingFullscreen = false
    @Published var hideInFullscreen = true
    var refreshedState: Bool?
    var refreshedDisplayID: String?
    func refreshAfterPlacement() { refresh() }
    func refresh() {
        refreshedDisplayID = DisplayInfo.positionedDisplay?.stableID
        if let refreshedState { isActive = refreshedState }
    }
}
#endif
