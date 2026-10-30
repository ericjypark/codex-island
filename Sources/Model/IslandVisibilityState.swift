struct IslandVisibilityState {
    var isSessionLocked = false
    var isGameModeActive = false
    var hideDuringGameMode = true
    var isFullscreen = false
    var hideInFullscreen = true

    var shouldHide: Bool {
        isSessionLocked || (hideDuringGameMode && isGameModeActive) || (hideInFullscreen && isFullscreen)
    }

    func allowsMouseInteraction(windowIsVisible: Bool) -> Bool {
        !shouldHide && windowIsVisible
    }
}
