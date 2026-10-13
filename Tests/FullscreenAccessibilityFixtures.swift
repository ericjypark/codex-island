import AppKit
import ApplicationServices

final class FakeAccessibilityFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let sessions: [pid_t: FakeAccessibilitySession]
    private var offMain = true
    private var failuresRemaining: Int
    private var attemptsStorage = 0
    init(sessions: [pid_t: FakeAccessibilitySession], failures: Int = 0) {
        self.sessions = sessions
        failuresRemaining = failures
    }
    var attempts: Int { lock.withLock { attemptsStorage } }
    var allCallsOffMain: Bool { lock.withLock { offMain } }
    func make(pid: pid_t, onChange: @escaping @Sendable () -> Void) -> FullscreenAccessibilitySession? {
        let session: FakeAccessibilitySession? = lock.withLock {
            attemptsStorage += 1
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                return nil
            }
            offMain = offMain && !Thread.isMainThread
            return sessions[pid]
        }
        session?.callback = onChange
        return session
    }
}

final class FakeAccessibilitySession: FullscreenAccessibilitySession, @unchecked Sendable {
    let application: AXUIElement
    private let lock = NSLock()
    private var windowsStorage: [AXUIElement]
    private var registrationStorage: [(AXUIElement, String)] = []
    private var callbackStorage: (@Sendable () -> Void)?
    private var readsStorage = 0
    private var stopsStorage = 0
    private var removalsStorage = 0
    private var offMain = true
    private var delayStorage: TimeInterval = 0
    private var removalDelayStorage: TimeInterval = 0
    private var unsupportedStorage = false
    init(pid: pid_t) {
        application = AXUIElementCreateApplication(pid)
        windowsStorage = [AXUIElementCreateApplication(pid + 1)]
    }
    var windowList: [AXUIElement] {
        get { lock.withLock { windowsStorage } }
        set { lock.withLock { windowsStorage = newValue } }
    }
    var callback: (@Sendable () -> Void)? {
        get { lock.withLock { callbackStorage } }
        set { lock.withLock { callbackStorage = newValue } }
    }
    var readDelay: TimeInterval {
        get { lock.withLock { delayStorage } }
        set { lock.withLock { delayStorage = newValue } }
    }
    var unsupportedGeometry: Bool {
        get { lock.withLock { unsupportedStorage } }
        set { lock.withLock { unsupportedStorage = newValue } }
    }
    var removalDelay: TimeInterval {
        get { lock.withLock { removalDelayStorage } }
        set { lock.withLock { removalDelayStorage = newValue } }
    }
    var registrations: [(AXUIElement, String)] { lock.withLock { registrationStorage } }
    var reads: Int { lock.withLock { readsStorage } }
    var stops: Int { lock.withLock { stopsStorage } }
    var removals: Int { lock.withLock { removalsStorage } }
    var allCallsOffMain: Bool { lock.withLock { offMain } }
    func fire() { callback?() }
    func windows() -> [AXUIElement]? {
        let delay = lock.withLock {
            readsStorage += 1
            offMain = offMain && !Thread.isMainThread
            return delayStorage
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return windowList
    }
    func add(_ element: AXUIElement, notification: String) -> Bool {
        lock.withLock {
            offMain = offMain && !Thread.isMainThread
            if unsupportedStorage && (notification == kAXResizedNotification || notification == kAXMovedNotification) {
                return false
            }
            registrationStorage.append((element, notification))
            return true
        }
    }
    func remove(_ element: AXUIElement, notification: String) {
        let delay = removalDelay
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.withLock {
            offMain = offMain && !Thread.isMainThread
            removalsStorage += 1
            registrationStorage.removeAll { CFEqual($0.0, element) && $0.1 == notification }
        }
    }
    func stop() {
        lock.withLock {
            offMain = offMain && !Thread.isMainThread
            stopsStorage += 1
            registrationStorage.removeAll()
        }
    }
}
