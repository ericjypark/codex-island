import Foundation

struct CodexResetCredit: Identifiable, Equatable {
    let id: String
    let status: String
    let expiresAt: Date
    let title: String
    let description: String

    var isAvailable: Bool {
        status.lowercased() == "available"
    }
}

struct CodexResetCredits: Equatable {
    var availableCount: Int
    var credits: [CodexResetCredit]

    static let empty = CodexResetCredits(availableCount: 0, credits: [])

    /// Status alone isn't enough: with 30-minute polling a credit can lapse
    /// mid-cycle while the last snapshot still reports it "available".
    var availableCredits: [CodexResetCredit] {
        credits.filter { $0.isAvailable && $0.expiresAt > Date() }
            .sorted { $0.expiresAt < $1.expiresAt }
    }
}
