import AppKit
import ApplicationServices

@main
@MainActor
struct FullscreenAccessibilityTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                exit(1)
            }
            checks += 1
        }
        func update(_ monitor: FullscreenAccessibilityMonitor) async -> Bool {
            await withCheckedContinuation { continuation in
                monitor.update { continuation.resume(returning: $0) }
            }
        }
        func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }
        func waitUntil(_ condition: () -> Bool) async {
            for _ in 0..<200 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        let first = FakeAccessibilitySession(pid: 123)
        let second = FakeAccessibilitySession(pid: 456)
        let factory = FakeAccessibilityFactory(sessions: [123: first, 456: second])
        var foreground: pid_t? = 123
        var monitor: FullscreenAccessibilityMonitor? = FullscreenAccessibilityMonitor(
            foregroundPID: { foreground }, sessionFactory: { factory.make(pid: $0, onChange: $1) }
        )
        guard let initial = monitor else { preconditionFailure("Monitor fixture") }
        check(initial.hasEligibleForegroundApp, "Foreground eligibility is available before scheduling worker work")
        check(await update(initial), "Supported geometry notifications attach")
        check(first.registrations.count == 8, "Application and first window notifications register")
        check(first.allCallsOffMain && factory.allCallsOffMain, "Observer creation and AX messaging run off the main thread")
        let oldWindow = first.windowList[0]
        first.windowList = [AXUIElementCreateApplication(789)]
        check(await update(initial), "Window replacement reconciles supported notifications")
        check(!first.registrations.contains { CFEqual($0.0, oldWindow) }, "Replaced window registrations are removed")
        check(first.removals == 5 && first.registrations.count == 8, "Replacement keeps one set of application notifications")
        first.windowList = []
        check(!(await update(initial)), "A windowless application cannot suppress borderless fullscreen")
        check(first.registrations.count == 3, "Window creation remains observed while the app has no windows")
        var events = 0
        initial.onChange = { events += 1 }
        first.fire()
        await settle()
        check(events == 1, "Window creation can trigger detection after a windowless interval")
        first.windowList = (0..<40).map { AXUIElementCreateApplication(pid_t(1000 + $0)) }
        check(await update(initial), "A large window list retains supported detection")
        check(first.registrations.count == 3 + 32 * 5, "At most 32 windows are registered")
        let idleReads = first.reads
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        check(first.reads == idleReads, "Worker run loop performs no AX queries during three idle seconds")
        let oldCallback = first.callback
        second.unsupportedGeometry = true
        foreground = 456
        check(!(await update(initial)), "Unsupported foreground app fails open")
        check(first.stops > 0 && first.registrations.isEmpty, "App changes detach the prior observer")
        oldCallback?()
        await settle()
        check(events == 1, "Callbacks from the previous foreground app are rejected")
        let stoppedCallback = second.callback
        stoppedCallback?()
        initial.stop()
        await settle()
        check(events == 1 && second.registrations.isEmpty, "Stop invalidates queued callbacks and removes registrations")
        foreground = nil
        check(!initial.hasEligibleForegroundApp, "Ineligible foreground contexts reject a pending gate synchronously")
        check(!(await update(initial)), "No eligible foreground app leaves detection inactive")

        let budgetSession = FakeAccessibilitySession(pid: 555)
        let budgetFactory = FakeAccessibilityFactory(sessions: [555: budgetSession])
        let budgetMonitor = FullscreenAccessibilityMonitor(
            foregroundPID: { 555 }, sessionFactory: { budgetFactory.make(pid: $0, onChange: $1) }
        )
        check(await update(budgetMonitor), "Budget fixture attaches its initial window")
        budgetSession.removalDelay = 0.07
        budgetSession.windowList = [AXUIElementCreateApplication(888)]
        check(!(await update(budgetMonitor)), "Slow obsolete registration removal respects the reconciliation budget")
        check(budgetSession.removals > 0 && budgetSession.removals < 5, "Partial removal makes bounded progress")
        var finishedBudget = false
        for _ in 0..<5 {
            let removed = budgetSession.removals
            finishedBudget = await update(budgetMonitor)
            check(finishedBudget || budgetSession.removals > removed,
                  "Each event advances obsolete removal or completes replacement registration")
            if finishedBudget { break }
        }
        check(finishedBudget, "Later events finish partial reconciliation rather than repeating old removals")
        check(budgetSession.removals == 5 && budgetSession.registrations.count == 8,
              "Completed reconciliation leaves only the replacement window and app registrations")
        budgetMonitor.stop()

        let slow = FakeAccessibilitySession(pid: 321)
        slow.readDelay = 0.25
        let slowFactory = FakeAccessibilityFactory(sessions: [321: slow])
        var slowMonitor: FullscreenAccessibilityMonitor? = FullscreenAccessibilityMonitor(
            foregroundPID: { 321 }, sessionFactory: { slowFactory.make(pid: $0, onChange: $1) }
        )
        var slowResult: Bool?
        let started = ProcessInfo.processInfo.systemUptime
        slowMonitor?.update { slowResult = $0 }
        check(ProcessInfo.processInfo.systemUptime - started < 0.15, "Slow AX work does not block the calling main actor")
        await settle()
        check(slowResult == nil, "Main actor stays responsive while a slow AX query is pending")
        await waitUntil { slowResult != nil }
        check(slowResult == false && slow.registrations.count == 3,
              "An exhausted reconciliation budget fails open without registering geometry notifications")
        slowResult = nil
        slowMonitor?.update { slowResult = $0 }
        await settle()
        slowMonitor?.stop()
        await waitUntil { slowResult != nil && slow.registrations.isEmpty }
        check(slowResult == false && slow.registrations.isEmpty, "Stopping an in-flight query discards its result")
        slowMonitor = nil
        await settle()
        check(slow.stops > 0 && slow.allCallsOffMain, "Teardown cleans up the worker session off the main thread")

        // This final fixture owns its monitor exclusively, so teardown is real.
        let finalSession = FakeAccessibilitySession(pid: 654)
        let finalFactory = FakeAccessibilityFactory(sessions: [654: finalSession])
        var finalMonitor: FullscreenAccessibilityMonitor? = FullscreenAccessibilityMonitor(
            foregroundPID: { 654 }, sessionFactory: { finalFactory.make(pid: $0, onChange: $1) }
        )
        let attached: Bool = await withCheckedContinuation { continuation in
            finalMonitor?.update { continuation.resume(returning: $0) }
        }
        check(attached, "Teardown fixture attaches a real worker session")
        let finalCallback = finalSession.callback
        weak var weakMonitor = finalMonitor
        finalMonitor = nil
        await settle()
        check(weakMonitor == nil && finalSession.stops == 1 && finalSession.registrations.isEmpty,
              "Monitor teardown releases the owner and detaches its session")
        weakMonitor = nil
        finalCallback?()
        await settle()
        check(finalSession.stops == 1, "A retained old callback is safe after monitor teardown")
        monitor = nil
        print("PASS \(checks) Accessibility observer and worker checks")
    }
}

private final class FakeAccessibilityFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let sessions: [pid_t: FakeAccessibilitySession]
    private var offMain = true
    init(sessions: [pid_t: FakeAccessibilitySession]) { self.sessions = sessions }
    var allCallsOffMain: Bool { lock.withLock { offMain } }
    func make(pid: pid_t, onChange: @escaping @Sendable () -> Void) -> FullscreenAccessibilitySession? {
        let session = lock.withLock {
            offMain = offMain && !Thread.isMainThread
            return sessions[pid]
        }
        session?.callback = onChange
        return session
    }
}

private final class FakeAccessibilitySession: FullscreenAccessibilitySession, @unchecked Sendable {
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
