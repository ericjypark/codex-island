import AppKit
import Combine

@main
@MainActor
struct FullscreenTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
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
        var reading: Bool? = true
        var reads = 0
        let store = FullscreenStore(defaults: defaults, workspaceCenter: workspace,
                                    applicationCenter: application) {
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
                               applicationCenter: application, readFullscreen: { true }).hideInFullscreen,
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
        print("PASS \(checks) fullscreen and visibility checks")
    }
}
