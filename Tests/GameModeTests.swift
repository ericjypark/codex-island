import Foundation
import Combine
import notify

@main
@MainActor
struct GameModeTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        for locked in [false, true] {
            for active in [false, true] {
                for enabled in [false, true] {
                    let state = IslandVisibilityState(isSessionLocked: locked,
                                                      isGameModeActive: active,
                                                      hideDuringGameMode: enabled)
                    check(state.shouldHide == (locked || (active && enabled)),
                          "Lock and Game Mode remain independent reasons to hide")
                    check(!state.allowsMouseInteraction(windowIsVisible: false),
                          "An ordered-out window never captures input or activates the app")
                    check(state.allowsMouseInteraction(windowIsVisible: true) == !state.shouldHide,
                          "Game Mode and lock suppress mouse handling even before orderOut")
                }
            }
        }

        check(GameModeStore.isActive(state: 1, status: UInt32(NOTIFY_STATUS_OK)), "Enabled signal hides")
        check(!GameModeStore.isActive(state: 0, status: UInt32(NOTIFY_STATUS_OK)), "Disabled signal restores")
        check(!GameModeStore.isActive(state: 2, status: UInt32(NOTIFY_STATUS_OK)), "Unknown states fail open")
        check(!GameModeStore.isActive(state: 1, status: UInt32(NOTIFY_STATUS_INVALID_TOKEN)),
              "A failed read cannot strand the island hidden")

        let suite = "CodexIsland.GameModeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserved", forKey: "unrelated")

        // Exercise real notify delivery using our own namespace, never Apple's.
        let notification = "dev.codexisland.tests.game-mode.\(UUID().uuidString)"
        var publisher: Int32 = NOTIFY_TOKEN_INVALID
        check(notify_register_check(notification, &publisher) == NOTIFY_STATUS_OK, "Test publisher registers")
        defer { notify_cancel(publisher) }
        check(notify_set_state(publisher, 1) == NOTIFY_STATUS_OK, "Seed active before store startup")
        let store = GameModeStore(defaults: defaults, notificationName: notification)
        check(store.isActive, "Starting during Game Mode reads the existing state without waiting for an event")
        check(store.hideDuringGameMode, "Auto-hide defaults on for an existing installation")

        var visibility = IslandVisibilityState()
        let observation = store.$isActive.combineLatest(store.$hideDuringGameMode).sink { active, enabled in
            visibility.isGameModeActive = active
            visibility.hideDuringGameMode = enabled
        }
        defer { observation.cancel() }
        check(visibility.shouldHide, "Initial subscription suppresses the island before first display")
        store.hideDuringGameMode = false
        check(!visibility.shouldHide, "Turning off the preference restores immediately during a game")
        check(!GameModeStore(defaults: defaults, notificationName: notification).hideDuringGameMode,
              "Opt-out survives relaunch")
        store.hideDuringGameMode = true
        check(visibility.shouldHide, "Turning on the preference hides immediately during a game")
        check(GameModeStore(defaults: defaults, notificationName: notification).hideDuringGameMode,
              "Opt-in survives relaunch")

        func publish(_ state: UInt64) {
            precondition(notify_set_state(publisher, state) == NOTIFY_STATUS_OK)
            precondition(notify_post(notification) == NOTIFY_STATUS_OK)
        }
        func awaitState(_ active: Bool) async {
            for _ in 0..<100 {
                if store.isActive == active { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Game Mode notification did not arrive")
        }

        publish(0)
        await awaitState(false)
        check(!visibility.shouldHide, "Leaving Game Mode restores without polling")
        publish(1)
        await awaitState(true)
        check(visibility.shouldHide, "Entering Game Mode hides without polling")
        visibility.isSessionLocked = true
        publish(0)
        await awaitState(false)
        check(visibility.shouldHide, "Game ending while locked never reveals the island")
        publish(1)
        await awaitState(true)
        visibility.isSessionLocked = false
        check(visibility.shouldHide, "Unlocking during Game Mode keeps the island hidden")
        publish(0)
        await awaitState(false)
        check(!visibility.shouldHide, "Island returns only after both suppressors clear")
        publish(1)
        await awaitState(true)
        publish(UInt64.max)
        await awaitState(false)
        check(!store.isActive, "Unrecognized OS state leaves normal visibility intact")
        check(defaults.string(forKey: "unrelated") == "preserved", "Other preferences are preserved")
        print("PASS \(checks) Game Mode and visibility checks")
    }
}
