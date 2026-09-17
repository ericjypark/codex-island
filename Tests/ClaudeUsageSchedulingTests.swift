import Foundation

@main
struct ClaudeUsageSchedulingTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS \(label)")
        } else {
            print("FAIL \(label)")
            failures += 1
        }
    }

    static func main() {
        let start = Date(timeIntervalSince1970: 1_700_003_000)
        var gate = ClaudeRequestGate()
        expect(gate.claim(at: start), "first Claude request is allowed")
        expect(!gate.claim(at: start.addingTimeInterval(1)),
               "second Claude request inside five minutes is denied")
        expect(gate.delayUntilAllowed(at: start.addingTimeInterval(299)) == 1,
               "credential change waits only for the remaining safe interval")
        expect(gate.claim(at: start.addingTimeInterval(300)),
               "Claude request is allowed at the five-minute boundary")
        expect(!gate.claim(at: start.addingTimeInterval(300)),
               "coalesced timer and credential refresh cannot double-probe")

        expect(ClaudeCredentialWatchPolicy.action(claudeSelected: true, watchRunning: false) == .start,
               "selecting Claude starts its credential watcher")
        expect(ClaudeCredentialWatchPolicy.action(claudeSelected: true, watchRunning: true) == .keep,
               "selected Claude keeps one watcher")
        expect(ClaudeCredentialWatchPolicy.action(claudeSelected: false, watchRunning: true) == .stop,
               "deselecting Claude stops its credential watcher")
        expect(ClaudeCredentialWatchPolicy.action(claudeSelected: false, watchRunning: false) == .none,
               "deselected Claude does not create a watcher")

        if failures > 0 { exit(1) }
        print("all ClaudeUsageSchedulingTests passed")
    }
}
