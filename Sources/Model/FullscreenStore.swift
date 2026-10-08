import AppKit
import Combine

@MainActor
final class FullscreenStore: ObservableObject {
    static let shared = FullscreenStore {
        guard let display = DisplayInfo.currentTarget() else { return nil }
        if FullscreenSpaceReader.read(targetDisplayID: display.stableID) == true { return true }
        return FullscreenWindowReader.read(targetDisplayID: display.displayID)
    }
    static let preferenceKey = "MacIsland.hideInFullscreen"

    @Published var hideInFullscreen: Bool {
        didSet {
            defaults.set(hideInFullscreen, forKey: Self.preferenceKey)
            updatePolling()
            refresh()
        }
    }
    @Published private(set) var isActive = false

    private let defaults: UserDefaults
    private let readFullscreen: () -> Bool?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval
    private var isSystemSleeping = false
    private var isScreenSleeping = false
    private var isSessionLocked = false

    private var shouldMonitor: Bool {
        hideInFullscreen && !isSystemSleeping && !isScreenSleeping && !isSessionLocked
    }

    init(defaults: UserDefaults = .standard,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         applicationCenter: NotificationCenter = .default,
         sessionCenter: NotificationCenter = DistributedNotificationCenter.default(),
         pollInterval: TimeInterval = 1,
         readFullscreen: @escaping () -> Bool?) {
        self.defaults = defaults
        self.readFullscreen = readFullscreen
        self.pollInterval = pollInterval
        hideInFullscreen = defaults.object(forKey: Self.preferenceKey) == nil
            ? true : defaults.bool(forKey: Self.preferenceKey)
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observe(name, on: workspaceCenter)
        }
        observe(NSWorkspace.willSleepNotification, on: workspaceCenter) { $0.isSystemSleeping = true }
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter) { $0.isSystemSleeping = false }
        observe(NSWorkspace.screensDidSleepNotification, on: workspaceCenter) { $0.isScreenSleeping = true }
        observe(NSWorkspace.screensDidWakeNotification, on: workspaceCenter) { $0.isScreenSleeping = false }
        observe(.init("com.apple.screenIsLocked"), on: sessionCenter) { $0.isSessionLocked = true }
        observe(.init("com.apple.screenIsUnlocked"), on: sessionCenter) { $0.isSessionLocked = false }
        observe(NSApplication.didChangeScreenParametersNotification, on: applicationCenter)
        updatePolling()
        refresh()
    }

    deinit {
        pollTimer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    func refresh() {
        guard shouldMonitor else { return }
        let active = readFullscreen() ?? false
        if active != isActive { isActive = active }
    }

    private func updatePolling() {
        guard shouldMonitor else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        guard pollTimer == nil else { return }
        // Borderless fullscreen resizes a window without changing app or Space.
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = pollInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter,
                         change: @escaping (FullscreenStore) -> Void = { _ in }) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                change(self)
                self.updatePolling()
                self.refresh()
            }
        }
        observers.append((center, observer))
    }
}
