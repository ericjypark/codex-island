import Foundation
import Combine
import notify

@MainActor
final class GameModeStore: ObservableObject {
    static let shared = GameModeStore()
    static let preferenceKey = "MacIsland.hideDuringGameMode"

    // gamepolicyd publishes a Boolean state here. This is an undocumented,
    // read-only signal; missing/unreadable signals leave the island visible.
    nonisolated static let notificationName = "com.apple.system.console_mode_changed"

    @Published var hideDuringGameMode: Bool {
        didSet { defaults.set(hideDuringGameMode, forKey: Self.preferenceKey) }
    }
    @Published private(set) var isActive = false

    private let defaults: UserDefaults
    private var token: Int32 = NOTIFY_TOKEN_INVALID

    init(defaults: UserDefaults = .standard, notificationName: String = GameModeStore.notificationName) {
        self.defaults = defaults
        hideDuringGameMode = defaults.object(forKey: Self.preferenceKey) == nil
            ? true : defaults.bool(forKey: Self.preferenceKey)

        let result = notify_register_dispatch(notificationName, &token, .main) { [weak self] token in
            Task { @MainActor in
                guard let self, self.token == token else { return }
                self.refresh()
            }
        }
        if result == NOTIFY_STATUS_OK {
            refresh()
        } else {
            token = NOTIFY_TOKEN_INVALID
        }
    }

    deinit {
        if token != NOTIFY_TOKEN_INVALID { notify_cancel(token) }
    }

    func refresh() {
        var state: UInt64 = 0
        let status = notify_get_state(token, &state)
        let active = Self.isActive(state: state, status: status)
        if active != isActive { isActive = active }
    }

    static func isActive(state: UInt64, status: UInt32) -> Bool {
        status == NOTIFY_STATUS_OK && state == 1
    }
}
