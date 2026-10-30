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

        let retrySession = FakeAccessibilitySession(pid: 567)
        let retryFactory = FakeAccessibilityFactory(sessions: [567: retrySession], failures: 1)
        let retryMonitor = FullscreenAccessibilityMonitor(
            foregroundPID: { 567 }, sessionFactory: { retryFactory.make(pid: $0, onChange: $1) }
        )
        check(!(await update(retryMonitor)), "Transient AX session creation failure fails open")
        try? await Task.sleep(nanoseconds: 600_000_000)
        check(retryFactory.attempts == 1, "Session creation failure does not introduce idle retries")
        check(await update(retryMonitor), "Same-context Recheck retries a failed AX session creation")
        check(retryFactory.attempts == 2 && retrySession.registrations.count == 8,
              "The successful retry attaches app and window notifications")
        check(await update(retryMonitor), "Recovered observation remains supported")
        check(retryFactory.attempts == 2, "Same-context updates reuse the recovered session")
        retryMonitor.stop()

        let budgetSession = FakeAccessibilitySession(pid: 555)
        let budgetFactory = FakeAccessibilityFactory(sessions: [555: budgetSession])
        let budgetMonitor = FullscreenAccessibilityMonitor(
            foregroundPID: { 555 }, sessionFactory: { budgetFactory.make(pid: $0, onChange: $1) }
        )
        check(await update(budgetMonitor), "Budget fixture attaches its initial window")
        budgetSession.removalDelay = 0.07
        budgetSession.windowList = [AXUIElementCreateApplication(888)]
        let readsBeforeReplacement = budgetSession.reads
        var budgetResult: Bool?
        budgetMonitor.update { budgetResult = $0 }
        await waitUntil { budgetSession.removals >= 3 }
        check(budgetResult == nil, "Partial cleanup cannot report unsupported before its continuation finishes")
        await waitUntil { budgetResult != nil }
        check(budgetResult == true, "One event completes replacement across budget slices without another AX event")
        check(budgetSession.removals == 5 && budgetSession.registrations.count == 8,
              "Completed reconciliation leaves only the replacement window and app registrations")
        check(budgetSession.reads == readsBeforeReplacement + 1,
              "Continuations consume one window snapshot instead of repeatedly querying windows")
        budgetSession.windowList = [AXUIElementCreateApplication(999)]
        budgetResult = nil
        let removalsBeforeStop = budgetSession.removals
        budgetMonitor.update { budgetResult = $0 }
        await waitUntil { budgetSession.removals > removalsBeforeStop }
        budgetMonitor.stop()
        await waitUntil { budgetResult != nil && budgetSession.registrations.isEmpty }
        check(budgetResult == false && budgetSession.registrations.isEmpty,
              "Stopping between slices cancels continuation and detaches observation")

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
        check(slowResult == true && slow.registrations.count == 8,
              "A slow window snapshot continues registration in a later slice")
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
