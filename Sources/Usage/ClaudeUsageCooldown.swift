import Foundation

struct ClaudeUsageCooldown {
    private(set) var deadline: Date?

    func isActive(at date: Date) -> Bool {
        deadline.map { date < $0 } ?? false
    }

    mutating func arm(now: Date, duration: TimeInterval) {
        deadline = now.addingTimeInterval(duration)
    }

    mutating func clear() {
        deadline = nil
    }
}
