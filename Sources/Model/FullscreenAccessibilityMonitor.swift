import AppKit
import ApplicationServices

@MainActor
protocol FullscreenWindowMonitoring: AnyObject, Sendable {
    var onChange: (() -> Void)? { get set }
    var hasEligibleForegroundApp: Bool { get }
    func update(_ completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func stop()
}

@MainActor
final class FullscreenAccessibilityMonitor: FullscreenWindowMonitoring {
    var onChange: (() -> Void)?
    var hasEligibleForegroundApp: Bool { foregroundPID() != nil }
    private let foregroundPID: () -> pid_t?
    private let worker: FullscreenAccessibilityWorker
    private var pid: pid_t?
    private var observationRevision = 0
    private var requestRevision = 0

    init(foregroundPID: @escaping () -> pid_t? = {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder" else { return nil }
        return app.processIdentifier
    }, sessionFactory: @escaping FullscreenAccessibilityWorker.SessionFactory = {
        SystemFullscreenAccessibilitySession(pid: $0, onChange: $1)
    }) {
        self.foregroundPID = foregroundPID
        worker = FullscreenAccessibilityWorker(sessionFactory: sessionFactory)
    }

    deinit { worker.shutdown() }

    func stop() {
        requestRevision += 1
        observationRevision += 1
        pid = nil
        worker.stop()
    }

    func update(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let target = foregroundPID() else {
            stop()
            completion(false)
            return
        }
        if target != pid {
            stop()
            pid = target
        }
        requestRevision += 1
        let request = requestRevision
        let observation = observationRevision
        worker.update(pid: target, observation: observation, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationRevision == observation,
                      self.pid == target, self.foregroundPID() == target else { return }
                self.onChange?()
            }
        }, completion: { [weak self] supported in
            Task { @MainActor [weak self] in
                guard let self, self.requestRevision == request,
                      self.observationRevision == observation,
                      self.pid == target, self.foregroundPID() == target else {
                    completion(false)
                    return
                }
                completion(supported)
            }
        })
    }
}

protocol FullscreenAccessibilitySession: AnyObject {
    var application: AXUIElement { get }
    func windows() -> [AXUIElement]?
    func add(_ element: AXUIElement, notification: String) -> Bool
    func remove(_ element: AXUIElement, notification: String)
    func stop()
}

// All AX objects and messaging stay on this worker's run loop. Only cancellation
// state crosses threads, under the lock; notifications carry no AX objects back.
final class FullscreenAccessibilityWorker: @unchecked Sendable {
    typealias SessionFactory = @Sendable (pid_t, @escaping @Sendable () -> Void) -> FullscreenAccessibilitySession?
    private let executor = FullscreenRunLoopExecutor()
    private let sessionFactory: SessionFactory
    private let lock = NSLock()
    private var revision = 0
    private var session: FullscreenAccessibilitySession?
    private var pid: pid_t?
    private var observation: Int?
    private var registrations: [(AXUIElement, String)] = []

    init(sessionFactory: @escaping SessionFactory) { self.sessionFactory = sessionFactory }

    private func invalidate() -> Int {
        lock.lock()
        defer { lock.unlock() }
        revision += 1
        return revision
    }

    private func isCurrent(_ candidate: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return candidate == revision
    }

    func update(pid: pid_t, observation: Int, onChange: @escaping @Sendable () -> Void,
                completion: @escaping @Sendable (Bool) -> Void) {
        let request = invalidate()
        continueReconciliation(pid: pid, observation: observation, request: request,
                               plan: RegistrationPlan(), onChange: onChange, completion: completion)
    }

    private func continueReconciliation(pid: pid_t, observation: Int, request: Int,
                                        plan: RegistrationPlan, onChange: @escaping @Sendable () -> Void,
                                        completion: @escaping @Sendable (Bool) -> Void) {
        executor.perform { [self] in
            guard isCurrent(request) else { completion(false); return }
            let result = reconcile(pid: pid, observation: observation, request: request,
                                   plan: plan, onChange: onChange)
            guard isCurrent(request) else { completion(false); return }
            switch result {
            case .incomplete:
                continueReconciliation(pid: pid, observation: observation, request: request,
                                       plan: plan, onChange: onChange, completion: completion)
            case .complete(let supported):
                completion(supported)
            }
        }
    }

    func stop() {
        _ = invalidate()
        executor.perform(startIfNeeded: false) { [self] in detach() }
    }

    func shutdown() {
        _ = invalidate()
        executor.finish { [self] in detach() }
    }

    private func detach() {
        session?.stop()
        registrations.removeAll()
        session = nil
        pid = nil
        observation = nil
    }

    private enum ReconciliationResult {
        case incomplete
        case complete(Bool)
    }

    // Created empty by update; all AX elements and progress are worker-owned.
    private final class RegistrationPlan: @unchecked Sendable {
        var appIndex = 0
        var removals: [(AXUIElement, String)]?
        var additions: [(AXUIElement, String)] = []
        var removalIndex = 0
        var additionIndex = 0
    }

    private func reconcile(pid: pid_t, observation: Int, request: Int,
                           plan: RegistrationPlan, onChange: @escaping @Sendable () -> Void) -> ReconciliationResult {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        func canContinue() -> Bool {
            isCurrent(request) && ProcessInfo.processInfo.systemUptime < deadline
        }
        if session == nil || self.pid != pid || self.observation != observation {
            detach()
            session = sessionFactory(pid, onChange)
            self.pid = pid
            self.observation = observation
        }
        guard let session else { return .complete(false) }
        let appNotifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                                kAXWindowCreatedNotification]
        while plan.appIndex < appNotifications.count {
            guard canContinue() else { return .incomplete }
            let name = appNotifications[plan.appIndex]
            plan.appIndex += 1
            if registrations.contains(where: { CFEqual($0.0, session.application) && $0.1 == name }) { continue }
            if session.add(session.application, notification: name) { registrations.append((session.application, name)) }
        }
        if plan.removals == nil {
            guard canContinue() else { return .incomplete }
            guard let windows = session.windows() else { return .complete(false) }
            let names = [kAXResizedNotification, kAXMovedNotification,
                         kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification]
            let wanted = [(session.application, appNotifications)] + windows.prefix(32).map { ($0, names) }
            let targets = wanted.flatMap { element, notifications in notifications.map { (element, $0) } }
            plan.removals = registrations.filter { existing in
                !targets.contains { CFEqual($0.0, existing.0) && $0.1 == existing.1 }
            }
            plan.additions = targets.filter { target in
                !registrations.contains { CFEqual($0.0, target.0) && $0.1 == target.1 }
            }
        }
        let removals = plan.removals ?? []
        while plan.removalIndex < removals.count {
            guard canContinue() else { return .incomplete }
            let (element, name) = removals[plan.removalIndex]
            session.remove(element, notification: name)
            registrations.removeAll { CFEqual($0.0, element) && $0.1 == name }
            plan.removalIndex += 1
        }
        while plan.additionIndex < plan.additions.count {
            guard canContinue() else { return .incomplete }
            let (element, name) = plan.additions[plan.additionIndex]
            if session.add(element, notification: name) { registrations.append((element, name)) }
            plan.additionIndex += 1
        }
        return .complete(registrations.contains {
            $0.1 == kAXResizedNotification || $0.1 == kAXMovedNotification
        })
    }

}

private final class SystemFullscreenAccessibilitySession: FullscreenAccessibilitySession {
    let application: AXUIElement
    private let onChange: @Sendable () -> Void
    private var observer: AXObserver?
    private let runLoop = CFRunLoopGetCurrent()

    init?(pid: pid_t, onChange: @escaping @Sendable () -> Void) {
        guard AXIsProcessTrusted() else { return nil }
        self.onChange = onChange
        application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var created: AXObserver?
        let result = AXObserverCreate(pid, { observer, _, _, context in
            guard let context else { return }
            let session = Unmanaged<SystemFullscreenAccessibilitySession>.fromOpaque(context).takeUnretainedValue()
            guard let current = session.observer, CFEqual(current, observer) else { return }
            session.onChange()
        }, &created)
        guard result == .success, let created else { return nil }
        observer = created
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(created), .commonModes)
    }

    func windows() -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    func add(_ element: AXUIElement, notification: String) -> Bool {
        guard let observer else { return false }
        AXUIElementSetMessagingTimeout(element, 0.05)
        let result = AXObserverAddNotification(observer, element, notification as CFString,
                                               Unmanaged.passUnretained(self).toOpaque())
        return result == .success || result == .notificationAlreadyRegistered
    }

    func remove(_ element: AXUIElement, notification: String) {
        guard let observer else { return }
        AXObserverRemoveNotification(observer, element, notification as CFString)
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
    }

    deinit { stop() }
}

private final class FullscreenRunLoopExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var pending: [@Sendable () -> Void] = []
    private var finishing = false
    private var started = false

    func perform(startIfNeeded: Bool = true, _ work: @escaping @Sendable () -> Void) {
        enqueue(work, finish: false, startIfNeeded: startIfNeeded)
    }

    func finish(_ cleanup: @escaping @Sendable () -> Void) {
        enqueue(cleanup, finish: true, startIfNeeded: false)
    }

    private func enqueue(_ work: @escaping @Sendable () -> Void, finish: Bool, startIfNeeded: Bool) {
        lock.lock()
        guard !finishing else { lock.unlock(); return }
        if finish { finishing = true }
        guard started || startIfNeeded else {
            lock.unlock()
            if finish { work() }
            return
        }
        let operation: @Sendable () -> Void = {
            work()
            if finish { CFRunLoopStop(CFRunLoopGetCurrent()) }
        }
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, operation)
            CFRunLoopWakeUp(runLoop)
        } else {
            pending.append(operation)
        }
        let needsStart = !started
        started = true
        lock.unlock()
        if needsStart {
            let thread = Thread { [self] in run() }
            thread.name = "CodexIsland fullscreen notifications"
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    private func run() {
        let current = CFRunLoopGetCurrent()
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        guard let keepAlive = CFRunLoopSourceCreate(nil, 0, &context) else { return }
        CFRunLoopAddSource(current, keepAlive, .defaultMode)
        lock.lock()
        runLoop = current
        let operations = pending
        pending.removeAll()
        for operation in operations { CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue, operation) }
        lock.unlock()
        CFRunLoopRun()
        CFRunLoopRemoveSource(current, keepAlive, .defaultMode)
        lock.lock()
        runLoop = nil
        lock.unlock()
    }
}
