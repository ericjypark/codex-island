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

    var availableCredits: [CodexResetCredit] {
        credits.filter(\.isAvailable)
            .sorted { $0.expiresAt < $1.expiresAt }
    }
}
