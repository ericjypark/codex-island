import Foundation

struct ClaudeRequestGate {
    static let minimumInterval: TimeInterval = 300
    private(set) var lastRequestAt: Date?

    func delayUntilAllowed(at date: Date) -> TimeInterval {
        guard let lastRequestAt else { return 0 }
        return max(0, lastRequestAt.addingTimeInterval(Self.minimumInterval).timeIntervalSince(date))
    }

    mutating func claim(at date: Date) -> Bool {
        guard delayUntilAllowed(at: date) == 0 else { return false }
        lastRequestAt = date
        return true
    }
}

enum ClaudeCredentialWatchAction: Equatable {
    case start
    case keep
    case stop
    case none
}

enum ClaudeCredentialWatchPolicy {
    static func action(claudeSelected: Bool, watchRunning: Bool) -> ClaudeCredentialWatchAction {
        switch (claudeSelected, watchRunning) {
        case (true, false): return .start
        case (true, true): return .keep
        case (false, true): return .stop
        case (false, false): return .none
        }
    }
}
