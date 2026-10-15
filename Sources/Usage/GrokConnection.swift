import Foundation

/// The CLI owns its refresh token. Reading its session never rotates or writes it.
enum GrokConnection {
    struct Credential: Decodable {
        let key: String
        let expires_at: String?
        let email: String?
        let user_id: String?
    }

    private struct OptionalCredential: Decodable {
        let value: Credential?
        init(from decoder: Decoder) throws { value = try? Credential(from: decoder) }
    }

    static func credential(from data: Data, now: Date = Date()) throws -> Credential {
        let entries = try JSONDecoder().decode([String: OptionalCredential].self, from: data)
            .compactMapValues(\.value)
        let scopes = entries.keys.filter { $0.hasPrefix("https://auth.x.ai::") }.sorted()
        let candidates = scopes + entries.keys.filter { $0 == "https://accounts.x.ai/sign-in" }.sorted()
        let credentials = candidates.compactMap { entries[$0] }.filter {
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !credentials.isEmpty else { throw ProviderConnectionError.signIn }
        guard let entry = credentials.first(where: {
            guard let expiry = ProviderPayload.date($0.expires_at) else { return true }
            return expiry > now
        }) else { throw ProviderConnectionError.expired }
        return entry
    }

    static func fetch() async throws -> ConnectedUsage {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        let path = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: path), data.count <= 1_048_576 else {
            throw ProviderConnectionError.signIn
        }
        return try await fetch(credentialData: data, send: send)
    }

    static func fetch(credentialData: Data,
                      send: (URLRequest) async throws -> Data) async throws -> ConnectedUsage {
        let credential = try credential(from: credentialData)
        let billing = try await send(request("billing?format=credits", credential: credential))
        let config = try JSONDecoder().decode(Billing.self, from: billing).config
        var usage = try parse(billing)
        if usage.primary == nil || config.isUnifiedBillingUser == true {
            do {
                let monthly = try parse(await send(request("billing", credential: credential)))
                usage.plan = usage.plan ?? monthly.plan
                for limit in monthly.limits where limit.usedFraction != nil {
                    if let index = usage.limits.firstIndex(where: { $0.id == limit.id }) {
                        if usage.limits[index].usedFraction == nil { usage.limits[index] = limit }
                    } else {
                        usage.limits.append(limit)
                    }
                }
                if usage.primary != nil {
                    usage.limits.removeAll { $0.usedFraction == nil }
                    usage.message = nil
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if usage.primary == nil { throw error }
            }
        }
        usage.account = credential.email
        usage.accountID = credential.user_id ?? credential.email
        if let settings = try? await send(request("settings", credential: credential, timeout: 2)),
           let plan = try? JSONDecoder().decode(Settings.self, from: settings) {
            usage.plan = plan.subscription_tier_display ?? plan.subscription_tier ?? usage.plan
        }
        try Task.checkCancellation()
        usage.updatedAt = Date()
        return usage
    }

    private struct Settings: Decodable {
        let subscription_tier_display: String?
        let subscription_tier: String?
    }
    private struct Billing: Decodable {
        let config: Config
        let subscriptionTier: String?
    }
    private struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
        let billingPeriodEnd: String?
        let monthlyLimit: Amount?
        let used: Amount?
        let isUnifiedBillingUser: Bool?
        let subscriptionTier: String?
    }
    private struct Period: Decodable { let end: String?; let type: String? }
    private struct Amount: Decodable {
        let val: Double?
        private enum CodingKeys: String, CodingKey { case val }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Double.self, forKey: .val) { val = number }
            else if let text = try? container.decode(String.self, forKey: .val) { val = Double(text) }
            else { val = nil }
        }
    }

    static func parse(_ data: Data) throws -> ConnectedUsage {
        let billing = try JSONDecoder().decode(Billing.self, from: data)
        let config = billing.config
        let reset = ProviderPayload.date(config.currentPeriod?.end ?? config.billingPeriodEnd)
        var limits: [ConnectedLimit] = []
        if let fraction = ProviderPayload.fraction(config.creditUsagePercent.map { $0 / 100 }) {
            let weekly = config.currentPeriod?.type == "USAGE_PERIOD_TYPE_WEEKLY"
            let monthly = config.currentPeriod?.type == "USAGE_PERIOD_TYPE_MONTHLY"
            limits.append(ConnectedLimit(id: monthly ? "monthly" : "credits",
                label: weekly ? "week" : monthly ? "month" : "Credits",
                usedFraction: fraction, resetAt: reset, kind: weekly ? .weekly : .credits))
        }
        // On-demand amounts describe extra spending, never the included subscription allowance.
        if !limits.contains(where: { $0.id == "monthly" }),
           let cap = config.monthlyLimit?.val, cap.isFinite, cap > 0,
           let used = config.used?.val, used.isFinite, used >= 0 {
            limits.append(ConnectedLimit(id: "monthly", label: "month",
                usedFraction: min(1, used / cap), resetAt: ProviderPayload.date(config.billingPeriodEnd), kind: .credits))
        }
        if limits.isEmpty {
            limits.append(ConnectedLimit(id: "credits", label: "Credits", usedFraction: nil,
                                         resetAt: reset, kind: .credits))
        }
        return ConnectedUsage(limits: limits, plan: config.subscriptionTier ?? billing.subscriptionTier,
            message: limits.contains { $0.usedFraction != nil } ? nil : "Signed in. Grok did not report subscription usage.")
    }

    private static func request(_ path: String, credential: Credential, timeout: TimeInterval = 12) throws -> URLRequest {
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/\(path)") else {
            throw ProviderConnectionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(credential.key)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credential.user_id, forHTTPHeaderField: "x-userid")
        request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
        return request
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: .ephemeral, delegate: NoProviderRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderConnectionError.invalidResponse }
        guard response.statusCode == 200 else { throw ProviderConnectionError.http(response.statusCode) }
        guard data.count <= 2_097_152 else { throw ProviderConnectionError.invalidResponse }
        return data
    }
}

final class NoProviderRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
