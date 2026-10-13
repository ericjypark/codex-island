import AppKit
import ApplicationServices
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
        DisplayInfo.positionedDisplay = ("positioned-display", 123)
        check(FullscreenDetectionContext.current().displayID == "positioned-display",
              "Fullscreen context follows the positioned display instead of resolving Auto again")
        DisplayInfo.positionedDisplay = ("replacement-display", 456)
        check(FullscreenDetectionContext.current().displayID == "replacement-display",
              "Fullscreen context changes with the next window placement")
        DisplayInfo.positionedDisplay = nil
        check(FullscreenDetectionContext.current().displayID == nil,
              "Missing placement does not fall back to a different active display")
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
        let session = NotificationCenter()
        var reading: Bool? = true
        var reads = 0
        let store = FullscreenStore(defaults: defaults, workspaceCenter: workspace,
                                    sessionCenter: session) {
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
                               sessionCenter: session,
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
        await post(NSWorkspace.didTerminateApplicationNotification, center: workspace, state: true)
        check(visibility.shouldHide, "App termination refreshes current Space")
        await post(NSWorkspace.didWakeNotification, center: workspace, state: true)
        check(visibility.shouldHide, "Wake refreshes current Space")
        reading = nil
        store.refreshAfterPlacement()
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

        let monitor = WindowMonitorSpy()
        var trusted = false
        var borderlessReads = 0
        var nativeReads = 0
        var nativeFullscreen = false
        var borderless = false
        var permissionRequests = 0
        var settingsURLs: [URL] = []
        var settingsOpenSucceeds = true
        let events = NotificationCenter()
        let lockEvents = NotificationCenter()
        var monitoredStore: FullscreenStore? = FullscreenStore(
            defaults: defaults, workspaceCenter: events,
            sessionCenter: lockEvents, windowMonitor: monitor,
            accessibilityTrusted: { trusted }, requestAccessibility: { permissionRequests += 1 },
            openSettings: { url in settingsURLs.append(url); return settingsOpenSucceeds }, readBorderless: {
                borderlessReads += 1
                return borderless
            }, readFullscreen: {
                nativeReads += 1
                return nativeFullscreen
            }
        )
        func settle() async { try? await Task.sleep(nanoseconds: 550_000_000) }
        check(monitoredStore?.detectBorderlessFullscreen == false, "Accessibility detection requires explicit opt-in")
        check(monitor.updates == 0 && borderlessReads == 0, "Default performs no Accessibility or borderless query")
        check(permissionRequests == 0 && settingsURLs.isEmpty, "Startup neither requests access nor opens Settings")
        monitoredStore?.detectBorderlessFullscreen = true
        check(monitoredStore?.borderlessStatus == .permissionRequired && permissionRequests == 1,
              "Turning borderless detection on requests missing permission once and reports its pending state")
        monitoredStore?.detectBorderlessFullscreen = true
        monitoredStore?.refresh()
        check(permissionRequests == 1 && settingsURLs.isEmpty, "Repeated values and Recheck never prompt or open Settings")
        do {
            let restored = FullscreenStore(defaults: defaults, workspaceCenter: NotificationCenter(),
                                           sessionCenter: NotificationCenter(),
                                           requestAccessibility: { permissionRequests += 1 }, readFullscreen: { false })
            check(restored.detectBorderlessFullscreen && permissionRequests == 1,
                  "Restoring an enabled preference at launch never requests permission")
        }
        monitoredStore?.openAccessibilitySettings()
        check(settingsURLs.last?.absoluteString == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility" && permissionRequests == 1,
              "Open Settings targets the Accessibility permission pane without granting access or prompting")
        settingsOpenSucceeds = false
        monitoredStore?.openAccessibilitySettings()
        check(monitoredStore?.accessibilitySettingsOpenFailed == true, "Failed Settings dispatch exposes manual navigation instructions")
        settingsOpenSucceeds = true
        monitoredStore?.openAccessibilitySettings()
        check(monitoredStore?.accessibilitySettingsOpenFailed == false, "A successful Settings retry clears its error")
        monitoredStore?.detectBorderlessFullscreen = false
        check(permissionRequests == 1, "Turning the toggle off never requests permission")
        monitoredStore?.detectBorderlessFullscreen = true
        check(permissionRequests == 2, "A new explicit opt-in can request access again after denial")
        check(monitor.updates == 0 && borderlessReads == 0, "Missing permission performs no observer or geometry query")
        nativeFullscreen = true
        monitoredStore?.refresh()
        check(monitoredStore?.isActive == true, "Native fullscreen remains available without Accessibility permission")
        nativeFullscreen = false
        settingsOpenSucceeds = false
        monitoredStore?.openAccessibilitySettings()
        monitoredStore?.refresh()
        check(monitoredStore?.accessibilitySettingsOpenFailed == true,
              "Untrusted Recheck retains manual permission recovery instructions")
        trusted = true
        let dispatchesBeforeRecovery = settingsURLs.count
        monitoredStore?.refresh()
        check(monitoredStore?.accessibilitySettingsOpenFailed == false &&
              monitoredStore?.borderlessStatus == .observing && settingsURLs.count == dispatchesBeforeRecovery,
              "Recheck after a manual grant clears stale Settings errors without reopening Settings")
        monitoredStore?.detectBorderlessFullscreen = false
        monitoredStore?.detectBorderlessFullscreen = true
        check(permissionRequests == 2, "Already granted access does not trigger a permission request")
        monitoredStore?.refresh()
        check(monitoredStore?.borderlessStatus == .observing && monitor.running, "Explicit recheck attaches after permission grant")
        borderless = true
        for _ in 0..<30 { monitor.onChange?() }
        let beforeBurst = borderlessReads
        await settle()
        check(monitoredStore?.isActive == true, "Resize notification detects same-app borderless entry")
        check(borderlessReads - beforeBurst == 2, "Notification bursts coalesce into two bounded transition reads")
        let idleReads = nativeReads + borderlessReads
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        check(nativeReads + borderlessReads == idleReads, "Settled app has no fullscreen queries during three idle seconds")
        let beforeTrailingEvent = borderlessReads
        monitor.onChange?()
        for _ in 0..<100 {
            if borderlessReads > beforeTrailingEvent { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        check(borderlessReads == beforeTrailingEvent + 1, "The first event snapshot runs before its follow-up")
        borderless = false
        monitor.onChange?()
        await settle()
        check(borderlessReads == beforeTrailingEvent + 3 && monitoredStore?.isActive == false,
              "A trailing event supersedes the old follow-up and gets two new settled snapshots")
        borderless = false
        monitor.onChange?()
        await settle()
        check(monitoredStore?.isActive == false, "Window notification detects borderless exit")
        borderless = true
        monitor.onChange?()
        monitoredStore?.hideInFullscreen = false
        monitoredStore?.detectBorderlessFullscreen = false
        trusted = false
        monitoredStore?.detectBorderlessFullscreen = true
        check(permissionRequests == 2, "A disabled fullscreen feature cannot request Accessibility access")
        trusted = true
        let disabledReads = nativeReads + borderlessReads
        events.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await settle()
        check(!monitor.running && nativeReads + borderlessReads == disabledReads,
              "Disable detaches and cancels queued work, including native queries")
        check(monitoredStore?.isActive == false, "Disable clears stale suppression")
        monitoredStore?.hideInFullscreen = true
        check(monitoredStore?.isActive == true, "Re-enable immediately samples and observes")
        trusted = false
        monitor.onChange?()
        await settle()
        check(monitoredStore?.borderlessStatus == .permissionRequired && !monitor.running,
              "Revocation detected at the next event detaches observers")
        check(monitoredStore?.isActive == false, "Revocation clears stale borderless suppression")
        trusted = true
        monitor.supported = false
        monitoredStore?.refresh()
        let unsupportedReads = borderlessReads
        check(monitoredStore?.borderlessStatus == .unsupported && monitoredStore?.isActive == false,
              "Unsupported notifications fail open and report the limitation")
        await settle()
        check(borderlessReads == unsupportedReads, "Unsupported app does not trigger a polling fallback")
        monitor.supported = true
        events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await settle()
        check(monitoredStore?.isActive == true, "App activation retries observer attachment")
        for (pause, resume, center) in [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, events),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, events),
            (Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked"), lockEvents)
        ] {
            center.post(name: pause, object: nil)
            await settle()
            let pausedReads = nativeReads + borderlessReads
            monitor.onChange?()
            await settle()
            check(!monitor.running && nativeReads + borderlessReads == pausedReads,
                  "Sleep/lock suspends observers and queries")
            center.post(name: resume, object: nil)
            await settle()
            check(monitor.running && monitoredStore?.isActive == true, "Wake/unlock reattaches and refreshes")
        }
        events.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        events.post(name: NSWorkspace.willSleepNotification, object: nil)
        lockEvents.post(name: .init("com.apple.screenIsLocked"), object: nil)
        await settle()
        let suspendedReads = nativeReads + borderlessReads
        events.post(name: NSWorkspace.didWakeNotification, object: nil)
        lockEvents.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        await settle()
        check(nativeReads + borderlessReads == suspendedReads && !monitor.running,
              "Wake/unlock cannot resume queries while the display remains asleep")
        events.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await settle()
        check(monitoredStore?.isActive == true && monitor.running, "Final suspension clearing restores observers")
        monitoredStore?.detectBorderlessFullscreen = false
        check(!monitor.running && monitoredStore?.isActive == false, "Borderless opt-out detaches and clears suppression")
        monitoredStore?.detectBorderlessFullscreen = true
        monitor.onChange?()
        monitoredStore = nil
        await settle()
        check(!monitor.running && monitor.onChange == nil, "Store teardown cancels pending work and detaches")

        let delayed = WindowMonitorSpy()
        delayed.holdReplies = true
        var delayedTrusted = true
        var delayedReads = 0
        var delayedContext = FullscreenDetectionContext(displayID: "display-a", foregroundPID: 123)
        let delayedEvents = NotificationCenter()
        let delayedSessionEvents = NotificationCenter()
        var delayedStore: FullscreenStore? = FullscreenStore(
            defaults: defaults, workspaceCenter: delayedEvents,
            sessionCenter: delayedSessionEvents, windowMonitor: delayed,
            detectionContext: { delayedContext },
            accessibilityTrusted: { delayedTrusted }, readBorderless: {
                delayedReads += 1
                return true
            }, readFullscreen: { false }
        )
        check(delayedStore?.isCheckingFullscreen == true && delayedStore?.isActive == false,
              "The initial asynchronous borderless snapshot gates display without claiming fullscreen")
        delayedStore?.refresh()
        delayed.reply(true)
        check(delayedReads == 0 && delayedStore?.isActive == false,
              "Results from a superseded display/app snapshot cannot hide the island")
        delayed.reply(true)
        check(delayedReads == 1 && delayedStore?.isActive == true, "Only the current snapshot can publish borderless suppression")
        check(delayedStore?.isCheckingFullscreen == false, "A current result resolves the initial display gate")
        for (suspend, resume, center) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, delayedEvents),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, delayedEvents),
            (Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked"), delayedSessionEvents)
        ] {
            let stops = delayed.stops
            center.post(name: suspend, object: nil)
            for _ in 0..<100 {
                if delayed.stops > stops { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            check(delayedStore?.isCheckingFullscreen == true && !delayed.running,
                  "Suspension detaches the observer while retaining a display gate")
            let updates = delayed.updates
            center.post(name: resume, object: nil)
            for _ in 0..<100 {
                if delayed.updates > updates { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            check(delayedStore?.isCheckingFullscreen == true && delayedStore?.isActive == false,
                  "Wake/unlock stays gated while the asynchronous recheck is pending")
            delayed.reply(true)
            check(delayedStore?.isActive == true && delayedStore?.isCheckingFullscreen == false,
                  "The resumed fullscreen result replaces the gate without exposing the island")
        }
        let stopsBeforeRefresh = delayed.stops
        var transientVisibility: [Bool] = []
        let refreshObservation = delayedStore?.$isActive.sink { transientVisibility.append($0) }
        let updatesBeforeTermination = delayed.updates
        delayedEvents.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for _ in 0..<100 {
            if delayed.updates > updatesBeforeTermination { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        check(delayedStore?.isActive == true && delayed.stops == stopsBeforeRefresh,
              "An unrelated app exit preserves suppression and the existing observer while its reply is pending")
        check(delayedStore?.isCheckingFullscreen == false, "A settled same-context recheck needs no new display gate")
        delayed.reply(true)
        check(transientVisibility == [true], "A successful refresh never flashes an interactive island")
        refreshObservation?.cancel()
        delayedStore?.refresh()
        delayedContext.displayID = "display-b"
        let readsBeforeContextChange = delayedReads
        delayed.reply(true)
        check(delayedReads == readsBeforeContextChange && delayedStore?.isActive == false,
              "A display change detected at reply time discards stale geometry and clears the old context")
        check(delayed.stops > stopsBeforeRefresh, "Changing detection context detaches the old observer")
        delayed.reply(true)
        check(delayedStore?.isActive == true, "A fresh display-context reply can hide the island")
        delayedContext.foregroundPID = 456
        delayedStore?.refresh()
        check(delayedStore?.isActive == false, "Changing foreground app immediately clears the previous app's suppression")
        delayed.reply(true)
        check(delayedStore?.isActive == true, "The new foreground app can establish its own suppression")
        let allowedReads = delayedReads
        delayedStore?.refresh()
        delayedStore?.detectBorderlessFullscreen = false
        delayed.reply(true)
        check(delayedReads == allowedReads && delayedStore?.isActive == false && delayedStore?.isCheckingFullscreen == false,
              "Opt-out invalidates an in-flight observer result before geometry is read")
        delayedStore?.detectBorderlessFullscreen = true
        delayedTrusted = false
        delayed.reply(true)
        check(delayedReads == allowedReads && delayedStore?.borderlessStatus == .permissionRequired && !delayed.running,
              "Permission loss during observer attachment detaches and prevents geometry access")
        delayedTrusted = true
        delayedStore?.refresh()
        delayed.reply(false)
        check(delayedStore?.isCheckingFullscreen == false && delayedStore?.isActive == false &&
              delayedStore?.borderlessStatus == .unsupported,
              "Unsupported notification delivery resolves the pending gate and fails open")
        delayedStore?.refresh()
        delayedStore = nil
        await settle()
        delayed.reply(true)
        check(delayedReads == allowedReads && !delayed.running, "Teardown invalidates in-flight observer completion")

        let replacementSession = FakeAccessibilitySession(pid: 789)
        replacementSession.windowList = [AXUIElementCreateApplication(790), AXUIElementCreateApplication(791)]
        let replacementFactory = FakeAccessibilityFactory(sessions: [789: replacementSession])
        let replacementMonitor = FullscreenAccessibilityMonitor(
            foregroundPID: { 789 }, sessionFactory: { replacementFactory.make(pid: $0, onChange: $1) }
        )
        var replacementReads = 0
        var stillFullscreen = true
        let replacementStore = FullscreenStore(
            defaults: defaults, workspaceCenter: NotificationCenter(),
            sessionCenter: NotificationCenter(), windowMonitor: replacementMonitor,
            detectionContext: { FullscreenDetectionContext(displayID: "test", foregroundPID: 789) },
            accessibilityTrusted: { true },
            readBorderless: { replacementReads += 1; return stillFullscreen }, readFullscreen: { false }
        )
        func waitForReplacement(_ condition: () -> Bool) async {
            for _ in 0..<500 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        await waitForReplacement { replacementStore.isActive }
        check(replacementStore.isActive, "Real worker establishes initial borderless suppression")
        var replacementStates: [Bool] = []
        let replacementObservation = replacementStore.$isActive.sink { replacementStates.append($0) }
        replacementSession.removalDelay = 0.07
        replacementSession.windowList = [AXUIElementCreateApplication(792)]
        replacementSession.fire()
        await waitForReplacement { replacementSession.removals == 10 && replacementReads > 1 }
        check(replacementSession.removals == 10 && replacementReads > 1,
              "One AX event completes a multi-slice replacement without further external events")
        check(replacementStates == [true] && replacementStore.isActive,
              "Budget exhaustion cannot publish a visible island during borderless replacement")
        let settledReads = replacementSession.reads
        try? await Task.sleep(nanoseconds: 600_000_000)
        check(replacementSession.reads == settledReads, "Completed continuation returns to idle without polling")
        stillFullscreen = false
        replacementSession.fire()
        await waitForReplacement { !replacementStore.isActive }
        check(!replacementStore.isActive, "A later real geometry change clears suppression normally")
        replacementObservation.cancel()
        replacementStore.hideInFullscreen = false

        defaults.set(true, forKey: FullscreenStore.preferenceKey)
        var eligiblePID: pid_t? = 123
        var eligibilityContext = FullscreenDetectionContext(displayID: "display-a", foregroundPID: 123)
        var eligibilityNative = false
        var eligibilityGeometryReads = 0
        let eligibilityMonitor = FullscreenAccessibilityMonitor(
            foregroundPID: { eligiblePID }, sessionFactory: { _, _ in nil }
        )
        let eligibilityStore = FullscreenStore(
            defaults: defaults, workspaceCenter: NotificationCenter(),
            sessionCenter: NotificationCenter(), windowMonitor: eligibilityMonitor,
            detectionContext: { eligibilityContext }, accessibilityTrusted: { true },
            readBorderless: { eligibilityGeometryReads += 1; return true },
            readFullscreen: { eligibilityNative }
        )
        for (name, pid) in [("island", Optional(ProcessInfo.processInfo.processIdentifier)),
                            ("Finder", Optional(pid_t(456))), ("missing foreground", nil)] {
            eligiblePID = 123
            eligibilityContext.foregroundPID = 123
            eligibilityStore.refresh()
            for _ in 0..<200 {
                if !eligibilityStore.isCheckingFullscreen { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            check(!eligibilityStore.isCheckingFullscreen, "Eligible-app worker fixture settles")
            var suppressed: [Bool] = []
            let observation = eligibilityStore.$isActive.combineLatest(eligibilityStore.$isCheckingFullscreen)
                .map { $0 || $1 }.removeDuplicates().sink { suppressed.append($0) }
            eligibilityContext.foregroundPID = pid
            eligiblePID = nil
            eligibilityStore.refresh()
            check(suppressed == [false], "Activating \(name) never briefly suppresses the island")
            check(!eligibilityStore.isCheckingFullscreen && eligibilityStore.borderlessStatus == .unsupported,
                  "An ineligible \(name) context completes without a pending gate")
            observation.cancel()
        }
        eligibilityNative = true
        eligibilityStore.refresh()
        check(eligibilityStore.isActive && !eligibilityStore.isCheckingFullscreen,
              "Native fullscreen suppression is independent of foreground AX eligibility")
        eligibilityNative = false
        eligiblePID = 789
        eligibilityContext.foregroundPID = 789
        eligibilityStore.refresh()
        check(eligibilityStore.isCheckingFullscreen, "An eligible changed context still gates its asynchronous snapshot")
        eligiblePID = nil
        eligibilityContext.foregroundPID = ProcessInfo.processInfo.processIdentifier
        eligibilityStore.refresh()
        await settle()
        check(!eligibilityStore.isActive && !eligibilityStore.isCheckingFullscreen && eligibilityGeometryReads == 0,
              "Self-activation cancels an eligible pending reply without reading stale geometry or restoring its gate")
        eligibilityMonitor.stop()
        let deadlineMonitor = WindowMonitorSpy()
        deadlineMonitor.holdReplies = true
        let deadlineSession = NotificationCenter()
        var deadlineContext = FullscreenDetectionContext(displayID: "deadline-a", foregroundPID: 123)
        let deadlineStore = FullscreenStore(
            defaults: defaults, workspaceCenter: NotificationCenter(),
            sessionCenter: deadlineSession, windowMonitor: deadlineMonitor,
            detectionContext: { deadlineContext }, accessibilityTrusted: { true },
            readBorderless: { true }, readFullscreen: { false }
        )
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            deadlineStore.refresh()
        }
        check(!deadlineStore.isCheckingFullscreen && !deadlineStore.isActive,
              "A slow initial AX check fails open within one second despite same-context refreshes")
        let deadlineUpdates = deadlineMonitor.updates
        try? await Task.sleep(nanoseconds: 850_000_000)
        check(deadlineMonitor.updates == deadlineUpdates && !deadlineStore.isCheckingFullscreen,
              "Expired pending gates neither retry nor rearm while idle")
        for _ in 0..<deadlineUpdates { deadlineMonitor.reply(true) }
        check(deadlineStore.isActive, "A late current AX result can still establish fullscreen suppression")
        deadlineStore.refresh()
        try? await Task.sleep(nanoseconds: 850_000_000)
        check(deadlineStore.isActive && !deadlineStore.isCheckingFullscreen,
              "The initial-check deadline never clears established same-context fullscreen suppression")
        deadlineMonitor.reply(true)
        deadlineContext.foregroundPID = 456
        deadlineStore.refresh()
        try? await Task.sleep(nanoseconds: 400_000_000)
        deadlineContext.foregroundPID = 789
        deadlineStore.refresh()
        try? await Task.sleep(nanoseconds: 400_000_000)
        check(deadlineStore.isCheckingFullscreen,
              "A cancelled old-context deadline cannot release a newer context's pending gate")
        try? await Task.sleep(nanoseconds: 450_000_000)
        check(!deadlineStore.isCheckingFullscreen, "The new context has its own finite pending deadline")
        deadlineContext.foregroundPID = 999
        deadlineStore.refresh()
        deadlineSession.post(name: .init("com.apple.screenIsLocked"), object: nil)
        try? await Task.sleep(nanoseconds: 900_000_000)
        check(deadlineStore.isCheckingFullscreen,
              "A cancelled AX deadline cannot clear the native suspension gate while locked")
        deadlineStore.hideInFullscreen = false
        check(!deadlineStore.isCheckingFullscreen, "Opt-out cancels every pending display gate")
        deadlineStore.hideInFullscreen = true

        let nativeSession = NotificationCenter()
        var nativeDisplayID = "desktop-target"
        var nativeReading = true
        var nativeLockReads = 0
        let nativeOnly = FullscreenStore(defaults: defaults, workspaceCenter: NotificationCenter(),
                                         sessionCenter: nativeSession,
                                         detectionContext: { FullscreenDetectionContext(displayID: nativeDisplayID) },
                                         readFullscreen: { nativeLockReads += 1; return nativeReading })
        nativeOnly.detectBorderlessFullscreen = false
        let lockProbe = NativeLockVisibilityProbe()
        let nativeObservation = nativeOnly.$isActive.combineLatest(nativeOnly.$isCheckingFullscreen).sink { active, checking in
            lockProbe.state.isFullscreen = active || checking
            lockProbe.samples.append(!lockProbe.state.shouldHide)
        }
        let nativeLock = Notification.Name("com.apple.screenIsLocked")
        let lateControllerObserver = nativeSession.addObserver(forName: nativeLock, object: nil, queue: .main) { _ in
            Task { @MainActor in
                lockProbe.state.isSessionLocked = true
                lockProbe.samples.append(!lockProbe.state.shouldHide)
            }
        }
        nativeSession.post(name: nativeLock, object: nil)
        await settle()
        check(nativeOnly.isActive && !lockProbe.samples.contains(true),
              "A native-fullscreen lock never reveals the island before the controller's later lock task")
        let lockedReads = nativeLockReads
        nativeOnly.refresh()
        check(nativeLockReads == lockedReads && nativeOnly.isActive,
              "Native suppression stays cached during suspension without WindowServer queries")
        nativeReading = false
        nativeSession.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        await settle()
        check(!nativeOnly.isActive && nativeLockReads > lockedReads,
              "A fresh desktop snapshot clears cached native suppression on resume")
        // Simulate controller-first unlock: refresh still sees the store locked,
        // then the controller clears its own gate before the store's unlock task.
        nativeSession.post(name: nativeLock, object: nil)
        await settle()
        let beforeUnlockReads = nativeLockReads
        nativeDisplayID = "fullscreen-fallback"
        nativeReading = true
        nativeOnly.refreshAfterPlacement()
        await settle()
        lockProbe.samples.removeAll()
        nativeOnly.refresh()
        lockProbe.state.isSessionLocked = false
        lockProbe.samples.append(!lockProbe.state.shouldHide)
        check(nativeLockReads == beforeUnlockReads && !lockProbe.samples.contains(true),
              "Controller-first unlock stays hidden until a fresh native display sample")
        nativeSession.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        await settle()
        check(nativeOnly.isActive && nativeLockReads > beforeUnlockReads && !lockProbe.samples.contains(true),
              "Native fullscreen replaces the resume gate without revealing the island")
        nativeReading = false
        nativeOnly.refresh()
        check(!lockProbe.state.shouldHide, "A later desktop snapshot releases resume suppression")
        nativeSession.post(name: nativeLock, object: nil)
        await settle()
        nativeOnly.hideInFullscreen = false
        check(!nativeOnly.isCheckingFullscreen && !nativeOnly.isActive,
              "Opt-out releases the suspended native gate without waiting for unlock")
        nativeObservation.cancel()
        nativeSession.removeObserver(lateControllerObserver)
        print("PASS \(checks) fullscreen and visibility checks")
    }
}

@MainActor
private final class WindowMonitorSpy: FullscreenWindowMonitoring {
    var onChange: (() -> Void)?
    var hasEligibleForegroundApp = true
    var updates = 0
    var supported = true
    var running = false
    var stops = 0
    var holdReplies = false
    private var replies: [@MainActor @Sendable (Bool) -> Void] = []
    func update(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        updates += 1
        running = supported
        if holdReplies { replies.append(completion) }
        else { completion(supported) }
    }
    func reply(_ supported: Bool) { replies.removeFirst()(supported) }
    func stop() { stops += 1; running = false }
}

@MainActor
private final class NativeLockVisibilityProbe {
    var state = IslandVisibilityState()
    var samples: [Bool] = []
}
