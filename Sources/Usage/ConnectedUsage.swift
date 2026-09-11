import Foundation
import CryptoKit

enum ConnectedLimitKind: String, Codable {
    case session, weekly, credits, other

    var rank: Int {
        switch self {
        case .session: return 0
        case .weekly: return 1
        case .credits: return 2
        case .other: return 3
        }
    }
}

struct ConnectedLimit: Identifiable {
    let id: String
    let label: String
    let usedFraction: Double?
    let resetAt: Date?
    var groupID = "default"
    var groupLabel: String?
    var kind: ConnectedLimitKind = .other

    var window: WindowUsage {
        guard let usedFraction else { return WindowUsage(usedPercent: 0, resetAt: resetAt, error: "no data") }
        return WindowUsage(usedPercent: usedFraction, resetAt: resetAt, error: nil)
    }
}

struct ConnectedUsage {
    var limits: [ConnectedLimit] = []
    var account: String?
    var accountID: String?
    var plan: String?
    var message: String?
    var needsLogin = false
    var updatedAt: Date?

    var primary: ConnectedLimit? { limits.first { $0.usedFraction != nil } }

    var hasNoActiveSubscription: Bool {
        guard !needsLogin, updatedAt != nil, primary == nil else { return false }
        return plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "free"
    }

    func storageScope(provider: IslandProvider) -> String {
        let identity = accountID ?? account ?? "local-session"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(provider.rawValue).\(hash)"
    }

    func historyKey(provider: IslandProvider, limit: ConnectedLimit) -> String {
        let identity = "\(limit.groupID)|\(limit.id)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "quota.\(storageScope(provider: provider)).\(hash)"
    }
}

enum ProviderConnectionError: Error {
    case signIn, expired, unavailable, invalidResponse, http(Int)
}

enum ProviderPayload {
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func fraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }
}
