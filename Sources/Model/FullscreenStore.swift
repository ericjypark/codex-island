import AppKit
import Combine
@preconcurrency import ApplicationServices

struct FullscreenDetectionContext: Equatable, Sendable {
    var displayID: String?
    var foregroundPID: pid_t?

    @MainActor
    static func current() -> FullscreenDetectionContext {
        FullscreenDetectionContext(displayID: DisplayInfo.positionedDisplay?.stableID,
                                   foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
}

@MainActor
final class FullscreenStore: ObservableObject {
    static let shared = FullscreenStore(
        windowMonitor: FullscreenAccessibilityMonitor(),
        detectionContext: { FullscreenDetectionContext.current() },
        accessibilityTrusted: { AXIsProcessTrusted() },
        requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        openSettings: { NSWorkspace.shared.open($0) },
        readBorderless: {
            guard let display = DisplayInfo.positionedDisplay else { return nil }
            return FullscreenWindowReader.read(targetDisplayID: display.displayID)
        },
        readFullscreen: {
            FullscreenSpaceReader.read(targetDisplayID: DisplayInfo.positionedDisplay?.stableID)
        }
    )
    static let borderlessPreferenceKey = "MacIsland.detectBorderlessFullscreen"
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")

    enum BorderlessStatus {
        case disabled, permissionRequired, observing, unsupported
    }

    @Published var detectBorderlessFullscreen: Bool {
        didSet {
            defaults.set(detectBorderlessFullscreen, forKey: Self.borderlessPreferenceKey)
            if detectBorderlessFullscreen && !oldValue && hideInFullscreen && !accessibilityTrusted() {
                requestAccessibility()
            }
            refresh()
        }
    }
    @Published private(set) var borderlessStatus: BorderlessStatus = .disabled
    @Published private(set) var accessibilitySettingsOpenFailed = false
    static let preferenceKey = "MacIsland.hideInFullscreen"

    @Published var hideInFullscreen: Bool {
        didSet {
            defaults.set(hideInFullscreen, forKey: Self.preferenceKey)
            refresh()
        }
    }
    @Published private(set) var isActive = false
    @Published private(set) var isCheckingFullscreen = false

    private let defaults: UserDefaults
    private let readFullscreen: () -> Bool?
    private let observers = FullscreenNotificationObservers()
    private let windowMonitor: FullscreenWindowMonitoring?
    private let accessibilityTrusted: () -> Bool
    private let requestAccessibility: () -> Void
    private let openSettings: (URL) -> Bool
    private let readBorderless: () -> Bool?
    private let detectionContext: () -> FullscreenDetectionContext
    private var observationContext: FullscreenDetectionContext?
    private var transitionTask: Task<Void, Never>?
    private var pendingCheckTask: Task<Void, Never>?
    private var pendingCheckExpired = false
    private var transitionRevision = 0
    private var snapshotRevision = 0
    private var nativeFullscreen = false
    private var borderlessFullscreen = false
    private var hasBorderlessResult = false
    private var isSystemSleeping = false
    private var isScreenSleeping = false
    private var isSessionLocked = false

    private var shouldMonitor: Bool {
        hideInFullscreen && !isSystemSleeping && !isScreenSleeping && !isSessionLocked
    }

    init(defaults: UserDefaults = .standard,
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         sessionCenter: NotificationCenter = DistributedNotificationCenter.default(),
         windowMonitor: FullscreenWindowMonitoring? = nil,
         detectionContext: @escaping () -> FullscreenDetectionContext = { FullscreenDetectionContext() },
         accessibilityTrusted: @escaping () -> Bool = { false },
         requestAccessibility: @escaping () -> Void = {},
         openSettings: @escaping (URL) -> Bool = { _ in false },
         readBorderless: @escaping () -> Bool? = { false },
         readFullscreen: @escaping () -> Bool?) {
        self.defaults = defaults
        self.readFullscreen = readFullscreen
        self.windowMonitor = windowMonitor
        self.detectionContext = detectionContext
        self.accessibilityTrusted = accessibilityTrusted
        self.requestAccessibility = requestAccessibility
        self.openSettings = openSettings
        self.readBorderless = readBorderless
        detectBorderlessFullscreen = defaults.bool(forKey: Self.borderlessPreferenceKey)
        hideInFullscreen = defaults.object(forKey: Self.preferenceKey) == nil
            ? true : defaults.bool(forKey: Self.preferenceKey)
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observe(name, on: workspaceCenter)
        }
        observe(NSWorkspace.willSleepNotification, on: workspaceCenter) { $0.isSystemSleeping = true }
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter) { $0.isSystemSleeping = false }
        observe(NSWorkspace.screensDidSleepNotification, on: workspaceCenter) { $0.isScreenSleeping = true }
        observe(NSWorkspace.screensDidWakeNotification, on: workspaceCenter) { $0.isScreenSleeping = false }
        observe(.init("com.apple.screenIsLocked"), on: sessionCenter) { $0.isSessionLocked = true }
        observe(.init("com.apple.screenIsUnlocked"), on: sessionCenter) { $0.isSessionLocked = false }
        windowMonitor?.onChange = { [weak self] in self?.scheduleTransitionChecks() }
        refresh()
    }

    deinit {
        transitionTask?.cancel()
        pendingCheckTask?.cancel()
        Task { @MainActor [windowMonitor] in
            windowMonitor?.onChange = nil
            windowMonitor?.stop()
        }
        observers.cancel()
    }

    func refresh() {
        if accessibilitySettingsOpenFailed && accessibilityTrusted() {
            accessibilitySettingsOpenFailed = false
        }
        cancelTransitionChecks()
        sample()
    }

    func refreshAfterPlacement() {
        refresh()
        scheduleTransitionChecks()
    }

    func openAccessibilitySettings() {
        guard let url = Self.accessibilitySettingsURL else { return }
        accessibilitySettingsOpenFailed = !openSettings(url)
    }

    private func sample() {
        snapshotRevision += 1
        let revision = snapshotRevision
        guard shouldMonitor else {
            cancelTransitionChecks()
            resetPendingCheck()
            windowMonitor?.stop()
            hasBorderlessResult = false
            // The controller may unlock before this store receives its resume
            // event. Cached native state can be stale after a display change.
            isCheckingFullscreen = hideInFullscreen
            borderlessStatus = .disabled
            // Keep native suppression until the resume snapshot: the controller's
            // separate lock handler may run after this store's notification task.
            if !hideInFullscreen { nativeFullscreen = false }
            borderlessFullscreen = false
            publishVisibility()
            return
        }
        let context = detectionContext()
        if context != observationContext {
            resetPendingCheck()
            windowMonitor?.stop()
            borderlessFullscreen = false
            hasBorderlessResult = false
            observationContext = context
        }
        var awaitingReply = false
        nativeFullscreen = readFullscreen() ?? false
        if !detectBorderlessFullscreen {
            resetPendingCheck()
            windowMonitor?.stop()
            borderlessStatus = .disabled
            borderlessFullscreen = false
            hasBorderlessResult = false
        } else if !accessibilityTrusted() {
            resetPendingCheck()
            windowMonitor?.stop()
            borderlessStatus = .permissionRequired
            borderlessFullscreen = false
            hasBorderlessResult = false
        } else if let windowMonitor, windowMonitor.hasEligibleForegroundApp {
            awaitingReply = true
            if !hasBorderlessResult { beginPendingCheck(context: context) }
            windowMonitor.update { [weak self] supported in
                guard let self, self.snapshotRevision == revision, self.shouldMonitor,
                      self.detectBorderlessFullscreen else { return }
                guard self.detectionContext() == context else {
                    self.refresh()
                    return
                }
                guard self.accessibilityTrusted() else {
                    self.resetPendingCheck()
                    windowMonitor.stop()
                    self.borderlessStatus = .permissionRequired
                    self.borderlessFullscreen = false
                    self.hasBorderlessResult = false
                    self.publishVisibility()
                    self.isCheckingFullscreen = false
                    return
                }
                self.resetPendingCheck()
                self.borderlessStatus = supported ? .observing : .unsupported
                self.borderlessFullscreen = supported && (self.readBorderless() ?? false)
                self.hasBorderlessResult = true
                self.publishVisibility()
                self.isCheckingFullscreen = false
            }
        } else {
            resetPendingCheck()
            windowMonitor?.stop()
            borderlessStatus = .unsupported
            borderlessFullscreen = false
            hasBorderlessResult = false
        }
        publishVisibility()
        if !awaitingReply { isCheckingFullscreen = false }
    }

    private func beginPendingCheck(context: FullscreenDetectionContext) {
        guard !pendingCheckExpired else { return }
        isCheckingFullscreen = true
        guard pendingCheckTask == nil else { return }
        // The display wait is per context, not per snapshot or worker slice.
        // Reconciliation may continue after this one-shot fail-open deadline.
        pendingCheckTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 750_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.shouldMonitor,
                  self.observationContext == context, !self.hasBorderlessResult else { return }
            self.pendingCheckTask = nil
            self.pendingCheckExpired = true
            self.isCheckingFullscreen = false
        }
    }

    private func resetPendingCheck() {
        pendingCheckTask?.cancel()
        pendingCheckTask = nil
        pendingCheckExpired = false
    }

    private func publishVisibility() {
        let active = nativeFullscreen || borderlessFullscreen
        if active != isActive { isActive = active }
    }

    private func cancelTransitionChecks() {
        transitionRevision += 1
        transitionTask?.cancel()
        transitionTask = nil
    }

    private func scheduleTransitionChecks() {
        cancelTransitionChecks()
        guard shouldMonitor else { return }
        let revision = transitionRevision
        transitionTask = Task { @MainActor [weak self] in
            for delay: UInt64 in [80_000_000, 350_000_000] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, !Task.isCancelled, self.transitionRevision == revision else { return }
                self.sample()
            }
            if self?.transitionRevision == revision { self?.transitionTask = nil }
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter,
                         change: @escaping @MainActor @Sendable (FullscreenStore) -> Void = { _ in }) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                change(self)
                self.refresh()
                self.scheduleTransitionChecks()
            }
        }
        observers.append(center: center, token: observer)
    }
}

// NotificationCenter removal is thread-safe; this owner can cancel from the
// store's nonisolated deinit without transferring raw observer tokens to a task.
private final class FullscreenNotificationObservers: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func append(center: NotificationCenter, token: NSObjectProtocol) {
        lock.withLock { tokens.append((center, token)) }
    }

    func cancel() {
        let removed = lock.withLock {
            let removed = tokens
            tokens.removeAll()
            return removed
        }
        for (center, token) in removed { center.removeObserver(token) }
    }

    deinit { cancel() }
}
