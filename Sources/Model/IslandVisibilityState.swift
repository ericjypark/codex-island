struct IslandVisibilityState {
    var isSessionLocked = false
    var isGameModeActive = false
    var hideDuringGameMode = true

    var shouldHide: Bool {
        isSessionLocked || (hideDuringGameMode && isGameModeActive)
    }

    func allowsMouseInteraction(windowIsVisible: Bool) -> Bool {
        !shouldHide && windowIsVisible
    }
}
