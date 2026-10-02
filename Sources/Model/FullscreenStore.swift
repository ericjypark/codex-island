import AppKit
import Combine

@MainActor
final class FullscreenStore: ObservableObject {
    static let shared = FullscreenStore {
        FullscreenSpaceReader.read(targetDisplayID: DisplayInfo.currentTarget()?.stableID)
    }
    static let preferenceKey = "MacIsland.hideInFullscreen"

    @Published var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: Self.preferenceKey) }
    }
    @Published private(set) var isActive = false

    private let defaults: UserDefaults
    private let readFullscreen: () -> Bool?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         applicationCenter: NotificationCenter = .default,
         readFullscreen: @escaping () -> Bool?) {
        self.defaults = defaults
        self.readFullscreen = readFullscreen
        hideInFullscreen = defaults.object(forKey: Self.preferenceKey) == nil
            ? true : defaults.bool(forKey: Self.preferenceKey)
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observe(name, on: workspaceCenter)
        }
        observe(NSApplication.didChangeScreenParametersNotification, on: applicationCenter)
        refresh()
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    func refresh() {
        let active = readFullscreen() ?? false
        if active != isActive { isActive = active }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers.append((center, observer))
    }
}
