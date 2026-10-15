import Foundation

@main
struct ClaudeUsageCooldownTests {
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
        let now = Date(timeIntervalSince1970: 1_700_002_000)
        var cooldown = ClaudeUsageCooldown()
        cooldown.arm(now: now, duration: 900)
        expect(cooldown.isActive(at: now.addingTimeInterval(60)),
               "old account rate limit arms the Claude cooldown")

        cooldown.clear()
        expect(!cooldown.isActive(at: now.addingTimeInterval(60)),
               "credential-store account switch clears the old account cooldown")
        expect(cooldown.deadline == nil,
               "cleared account cooldown has no inherited retry deadline")

        if failures > 0 { exit(1) }
        print("all ClaudeUsageCooldownTests passed")
    }
}
