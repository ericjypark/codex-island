import AppKit
import Combine

@main
@MainActor
struct FullscreenTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                exit(1)
            }
            checks += 1
        }
        func display(_ id: String, _ type: Int) -> [String: Any] {
            ["Display Identifier": id, "Current Space": ["type": type]]
        }
        let desktop = display("built-in", 0)
        let fullscreen = display("built-in", 4)
        let external = display("external", 4)
        func decode(_ displays: [[String: Any]], target: String? = "built-in") -> Bool? {
            FullscreenSpaceReader.isFullscreen(displays: displays, targetDisplayID: target)
        }
        check(decode([fullscreen]) == true, "Native fullscreen, including video and Split View, hides")
        check(decode([desktop]) == false, "Desktop windows, even maximized, do not hide")
        check(decode([desktop, external]) == false, "Fullscreen on another display does not hide")
        check(decode([desktop, external], target: "external") == true, "Selected external display hides")
        check(decode([fullscreen, display("external", 0)]) == true, "Other display focus does not override the island's Space")
        check(decode([display("Main", 4)]) == true, "Shared fullscreen Space applies across displays")
        check(decode([display("Main", 0)]) == false, "Shared desktop Space restores")
        check(decode([display("Main", 4), external]) == nil, "Ambiguous Main display does not override selection")
        check(decode([]) == nil, "Unavailable data fails open")
        check(decode([fullscreen], target: nil) == nil, "Unavailable target fails open")
        check(decode([fullscreen], target: "disconnected") == nil, "Missing display fails open")
        check(decode([fullscreen, fullscreen]) == nil, "Duplicate display data fails open")
        check(decode([display("built-in", 99)]) == nil, "Unknown Space types fail open")
        check(decode([["Display Identifier": "built-in"]]) == nil, "Missing current Space fails open")
        check(decode([["Display Identifier": "built-in", "Current Space": ["type": "4"]]]) == nil,
              "Malformed Space type fails open")
        check(decode([["Display Identifier": "built-in", "Current Space": ["type": 0],
                       "Spaces": [["type": 4]]]]) == false, "A game in an inactive Space does not hide the desktop")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pid: pid_t = 123
        func window(_ bounds: CGRect, owner: pid_t = 123, layer: Int = 0,
                    alpha: Double = 1, onScreen: Bool = true) -> [String: Any] {
            [kCGWindowOwnerPID as String: owner, kCGWindowBounds as String: bounds.dictionaryRepresentation,
             kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
             kCGWindowIsOnscreen as String: onScreen]
        }
        func covers(_ windows: [[String: Any]], target: CGRect? = nil) -> Bool {
            FullscreenWindowReader.isFullscreen(windows: windows, targetBounds: target ?? screen,
                                                 foregroundPID: pid)
        }
        check(decode([desktop]) == false && covers([window(screen)]),
              "CrossOver borderless fullscreen hides even on a desktop Space")
        check(covers([window(screen, layer: 3)]), "VLC floating fullscreen video hides")
        check(!covers([window(screen, owner: 456)]), "Background apps do not suppress the foreground desktop")
        check(covers([window(CGRect(x: 10, y: 10, width: 200, height: 100)), window(screen)]),
              "A foreground video application's controls do not mask its fullscreen video window")
        check(!covers([window(CGRect(x: 0, y: 38, width: 1512, height: 874))]),
              "An ordinary maximized window leaves menu bar and Dock space")
        check(!covers([window(CGRect(x: 0, y: 38, width: 1512, height: 944))]),
              "Maximized windows with an auto-hidden Dock still leave menu bar space")
        check(!covers([window(CGRect(x: 100, y: 100, width: 800, height: 600))]),
              "Windowed video and games do not hide")
        check(!covers([window(screen, onScreen: false)]), "Minimized or inactive-Space windows do not hide")
        check(!covers([window(screen, alpha: 0)]), "Invisible windows do not hide")
        check(!covers([window(screen, alpha: .infinity)]), "Invalid opacity fails open")
        check(!covers([window(screen, layer: -1)]), "Desktop layers do not hide")
        let otherScreen = CGRect(x: -1920, y: -1200, width: 1920, height: 1200)
        check(!covers([window(otherScreen)]), "Fullscreen on another display does not hide")
        check(covers([window(otherScreen)], target: otherScreen),
              "Selected displays above and left use Core Graphics coordinates")
        check(!covers([window(CGRect(x: -1920, y: 0, width: 3432, height: 982))]),
              "Oversized windows spanning displays are not mistaken for fullscreen")
        check(covers([window(screen.insetBy(dx: 1, dy: 1))]), "One-point rounding is tolerated")
        check(!covers([window(screen.insetBy(dx: 3, dy: 3))]), "Substantial borders do not qualify")
        check(!covers([]), "Missing windows fail open")
        check(!covers([window(screen)], target: .zero), "Unknown display geometry fails open")
        check(!covers([window(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 982))]),
              "Non-finite window geometry fails open")
        check(!FullscreenWindowReader.isFullscreen(windows: [window(screen)], targetBounds: screen,
                                                   foregroundPID: 0), "Missing foreground identity fails open")
        for key in [kCGWindowOwnerPID, kCGWindowBounds, kCGWindowLayer, kCGWindowAlpha, kCGWindowIsOnscreen] {
            var malformed = window(screen)
            malformed.removeValue(forKey: key as String)
            check(!covers([malformed]), "Missing required metadata fails open: \(key)")
        }

        for locked in [false, true] {
            for game in [false, true] {
                for hideGame in [false, true] {
                    for full in [false, true] {
                        for hideFull in [false, true] {
                            let state = IslandVisibilityState(isSessionLocked: locked, isGameModeActive: game,
                                                              hideDuringGameMode: hideGame, isFullscreen: full,
                                                              hideInFullscreen: hideFull)
                            let hidden = locked || (game && hideGame) || (full && hideFull)
                            check(state.shouldHide == hidden, "Lock, Game Mode and fullscreen settings compose independently")
                            check(state.allowsMouseInteraction(windowIsVisible: true) == !hidden,
                                  "Suppressed windows cannot capture input before orderOut")
                            check(!state.allowsMouseInteraction(windowIsVisible: false), "Ordered-out windows cannot capture input")
                        }
                    }
                }
            }
        }

        let suite = "CodexIsland.FullscreenTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserved", forKey: "unrelated")
        let workspace = NotificationCenter()
        let application = NotificationCenter()
        let session = NotificationCenter()
        var reading: Bool? = true
        var reads = 0
        let store = FullscreenStore(defaults: defaults, workspaceCenter: workspace,
                                    applicationCenter: application, sessionCenter: session) {
            reads += 1
            return reading
        }
        check(store.isActive, "Launch into an already fullscreen Space seeds hidden state")
        check(store.hideInFullscreen, "Fullscreen hiding defaults on")
        var visibility = IslandVisibilityState()
        let observation = store.$isActive.combineLatest(store.$hideInFullscreen).sink { active, enabled in
            visibility.isFullscreen = active
            visibility.hideInFullscreen = enabled
        }
        defer { observation.cancel() }
        check(visibility.shouldHide, "Initial subscription hides before the island's first display")
        store.hideInFullscreen = false
        check(!visibility.shouldHide, "Opt-out restores immediately")
        check(!FullscreenStore(defaults: defaults, workspaceCenter: workspace,
                               applicationCenter: application, sessionCenter: session,
                               readFullscreen: { true }).hideInFullscreen,
              "Opt-out survives relaunch")
        store.hideInFullscreen = true
        check(visibility.shouldHide, "Opt-in hides immediately")
        check(defaults.bool(forKey: FullscreenStore.preferenceKey), "Opt-in persists")

        func post(_ name: Notification.Name, center: NotificationCenter, state: Bool?) async {
            reading = state
            let before = reads
            center.post(name: name, object: nil)
            for _ in 0..<100 {
                if reads > before { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Fullscreen event was not observed")
        }
        await post(NSWorkspace.activeSpaceDidChangeNotification, center: workspace, state: false)
        check(!visibility.shouldHide, "Leaving fullscreen restores via Space notification")
        await post(NSWorkspace.activeSpaceDidChangeNotification, center: workspace, state: true)
        check(visibility.shouldHide, "Reentering fullscreen hides via Space notification")
        await post(NSWorkspace.didActivateApplicationNotification, center: workspace, state: false)
        check(!visibility.shouldHide, "App activation refreshes current Space")
        await post(NSWorkspace.didWakeNotification, center: workspace, state: true)
        check(visibility.shouldHide, "Wake refreshes current Space")
        await post(NSApplication.didChangeScreenParametersNotification, center: application, state: nil)
        check(!visibility.shouldHide, "Unavailable display snapshot clears stale suppression")
        reading = true
        store.refresh()
        check(visibility.shouldHide, "Target-display change can refresh synchronously")
        visibility.isSessionLocked = true
        reading = false
        store.refresh()
        check(visibility.shouldHide, "Leaving fullscreen while locked cannot reveal the island")
        visibility.isSessionLocked = false
        visibility.isGameModeActive = true
        check(visibility.shouldHide, "Leaving fullscreen cannot override active Game Mode")
        visibility.isGameModeActive = false
        check(!visibility.shouldHide, "Clearing all suppression reasons restores")
        check(defaults.string(forKey: "unrelated") == "preserved", "Unrelated settings remain intact")

        var liveWindows = [window(CGRect(x: 100, y: 100, width: 800, height: 600))]
        var pollReads = 0
        var pollingStore: FullscreenStore? = FullscreenStore(
            defaults: defaults, workspaceCenter: workspace, applicationCenter: application,
            sessionCenter: session, pollInterval: 0.02
        ) {
            pollReads += 1
            return covers(liveWindows)
        }
        func waitFor(_ predicate: () -> Bool) async -> Bool {
            for _ in 0..<100 {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return false
        }
        check(pollingStore?.isActive == false, "Windowed launch stays visible")
        liveWindows = [window(screen)]
        let entered = await waitFor { pollingStore?.isActive == true }
        check(entered, "The timer detects same-app fullscreen entry without a notification")
        liveWindows = []
        let exited = await waitFor { pollingStore?.isActive == false }
        check(exited, "The timer detects same-app fullscreen exit without a notification")

        pollingStore?.hideInFullscreen = false
        let disabledReads = pollReads
        liveWindows = [window(screen)]
        try? await Task.sleep(nanoseconds: 80_000_000)
        check(pollReads == disabledReads, "Disabled fullscreen hiding stops window inspection")
        pollingStore?.hideInFullscreen = true
        check(pollingStore?.isActive == true, "Re-enabling immediately reads current geometry")
        liveWindows = []
        let resumed = await waitFor { pollingStore?.isActive == false }
        check(resumed, "Re-enabling also resumes periodic detection")

        for (pause, resume, center) in [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, workspace),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, workspace),
            (Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked"), session)
        ] {
            center.post(name: pause, object: nil)
            try? await Task.sleep(nanoseconds: 30_000_000)
            let pausedReads = pollReads
            liveWindows = [window(screen)]
            try? await Task.sleep(nanoseconds: 80_000_000)
            check(pollReads == pausedReads, "Sleep/lock suspends window inspection: \(pause)")
            center.post(name: resume, object: nil)
            let woke = await waitFor { pollingStore?.isActive == true }
            check(woke, "Wake/unlock immediately refreshes: \(resume)")
            liveWindows = []
            let pollingAgain = await waitFor { pollingStore?.isActive == false }
            check(pollingAgain, "Wake/unlock resumes periodic detection: \(resume)")
        }
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        session.post(name: .init("com.apple.screenIsLocked"), object: nil)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let suspendedReads = pollReads
        liveWindows = [window(screen)]
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        session.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        try? await Task.sleep(nanoseconds: 80_000_000)
        check(pollReads == suspendedReads, "System wake/unlock cannot resume inspection while the display sleeps")
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        let fullyAwake = await waitFor { pollingStore?.isActive == true }
        check(fullyAwake, "Clearing the final suspension resumes inspection")
        pollingStore = nil
        let finalReads = pollReads
        try? await Task.sleep(nanoseconds: 80_000_000)
        check(pollReads == finalReads, "Destroying the store stops polling")
        print("PASS \(checks) fullscreen and visibility checks")
    }
}
