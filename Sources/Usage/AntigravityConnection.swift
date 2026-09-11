import Foundation

enum AntigravityConnection {
    struct Credential {
        let accessToken: String
    }

    private struct StoredCredential: Decodable {
        let token: Token
        struct Token: Decodable {
            let access_token: String
            let expiry: String
        }
    }

    static func credential(from data: Data, now: Date = Date()) throws -> Credential {
        guard data.count <= 1_048_576 else { throw ProviderConnectionError.invalidResponse }
        var payload = data
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.hasPrefix("go-keyring-base64:") {
            guard let decoded = Data(base64Encoded: String(raw.dropFirst("go-keyring-base64:".count))) else {
                throw ProviderConnectionError.invalidResponse
            }
            payload = decoded
        }
        let stored = try JSONDecoder().decode(StoredCredential.self, from: payload)
        guard !stored.token.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderConnectionError.signIn
        }
        guard let expiry = ProviderPayload.date(stored.token.expiry) else {
            throw ProviderConnectionError.invalidResponse
        }
        guard expiry > now else { throw ProviderConnectionError.expired }
        return Credential(accessToken: stored.token.access_token)
    }

    static func fetch() async throws -> ConnectedUsage {
        let data = try await Task.detached(priority: .utility) { try readCLICredential() }.value
        try Task.checkCancellation()
        return try await fetch(credentialData: data, send: send)
    }

    static func fetch(credentialData: Data,
                      send: (URLRequest) async throws -> Data) async throws -> ConnectedUsage {
        let credential = try credential(from: credentialData)
        let loadRequest = try request("loadCodeAssist", token: credential.accessToken,
                                     body: LoadRequest(metadata: Metadata(ideType: "ANTIGRAVITY")))
        let load = try JSONDecoder().decode(LoadResponse.self, from: await send(loadRequest))
        guard let project = load.cloudaicompanionProject, !project.isEmpty else {
            throw ProviderConnectionError.invalidResponse
        }
        try Task.checkCancellation()
        let quotaRequest = try request("retrieveUserQuotaSummary", token: credential.accessToken,
                                      body: QuotaRequest(project: project))
        var usage = try parse(await send(quotaRequest))
        usage.accountID = project
        usage.plan = load.paidTier?.name ?? load.currentTier?.name
        return usage
    }

    // agy owns token refresh and writes. Match its exact Keychain item, never the desktop app's storage.
    private static func readCLICredential() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0, !data.isEmpty else { throw ProviderConnectionError.signIn }
        return data
    }

    private struct Metadata: Encodable { let ideType: String }
    private struct LoadRequest: Encodable { let metadata: Metadata }
    private struct QuotaRequest: Encodable { let project: String }
    private struct LoadResponse: Decodable {
        let cloudaicompanionProject: String?
        let currentTier: Tier?
        let paidTier: Tier?
    }

    private static func request<Body: Encodable>(_ method: String, token: String, body: Body) throws -> URLRequest {
        // Match agy's backend; the production host can return an unrelated, unused quota.
        guard let url = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:\(method)") else {
            throw ProviderConnectionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.1.25", forHTTPHeaderField: "User-Agent")
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

    static func parse(_ data: Data) throws -> ConnectedUsage {
        let root = try JSONDecoder().decode(Response.self, from: data)
        let groups = root.response?.groups ?? root.summary?.groups ?? root.groups ?? []
        var limits: [ConnectedLimit] = []
        for group in groups {
            let groupID = group.groupId ?? group.displayName ?? "default"
            for bucket in group.buckets ?? [] where bucket.disabled != true {
                let remaining = bucket.remainingFraction ?? bucket.remaining?.fraction
                let used = ProviderPayload.fraction(remaining).map { 1 - $0 }
                let label = bucket.displayName ?? bucket.bucketId ?? "Usage"
                let kind = limitKind(label)
                limits.append(ConnectedLimit(id: bucket.bucketId ?? label, label: shortLabel(label, kind: kind),
                    usedFraction: used, resetAt: ProviderPayload.date(bucket.resetTime),
                    groupID: groupID, groupLabel: group.displayName, kind: kind))
            }
        }
        let status = root.userStatus
        if limits.isEmpty {
            for model in status?.cascadeModelConfigData?.clientModelConfigs ?? [] {
                guard let quota = model.quotaInfo else { continue }
                let identity = model.modelOrAlias?.model ?? model.label ?? "model"
                limits.append(ConnectedLimit(id: identity, label: "Usage",
                    usedFraction: ProviderPayload.fraction(quota.remainingFraction).map { 1 - $0 },
                    resetAt: ProviderPayload.date(quota.resetTime),
                    groupID: identity, groupLabel: model.label ?? identity))
            }
        }
        var seen: Set<String> = []
        limits = limits.filter { seen.insert("\($0.groupID)|\($0.id)").inserted }
        guard !limits.isEmpty else { throw ProviderConnectionError.invalidResponse }
        return ConnectedUsage(limits: limits, account: status?.email, accountID: status?.email,
            plan: status?.userTier?.name ?? status?.planStatus?.planInfo?.planName, updatedAt: Date())
    }

    private static func limitKind(_ label: String) -> ConnectedLimitKind {
        let value = label.lowercased()
        if value.contains("week") || value.contains("7d") { return .weekly }
        if value.contains("five") || value.contains("5h") || value.contains("5 hour") { return .session }
        return .other
    }

    private static func shortLabel(_ label: String, kind: ConnectedLimitKind) -> String {
        switch kind {
        case .session: return "5h"
        case .weekly: return "week"
        default: return label
        }
    }

    private struct Response: Decodable {
        let response: Summary?
        let summary: Summary?
        let groups: [Group]?
        let userStatus: Status?
    }
    private struct Summary: Decodable { let groups: [Group]? }
    private struct Group: Decodable { let groupId: String?; let displayName: String?; let buckets: [Bucket]? }
    private struct Bucket: Decodable {
        let bucketId: String?
        let displayName: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let remaining: Remaining?
        let resetTime: String?
    }
    private struct Remaining: Decodable {
        let remainingFraction: Double?
        let `case`: String?
        let value: Double?
        var fraction: Double? { remainingFraction ?? (`case` == "remainingFraction" ? value : nil) }
    }
    private struct Status: Decodable {
        let email: String?
        let userTier: Tier?
        let planStatus: PlanStatus?
        let cascadeModelConfigData: Models?
    }
    private struct Tier: Decodable { let name: String? }
    private struct PlanStatus: Decodable { let planInfo: PlanInfo? }
    private struct PlanInfo: Decodable { let planName: String? }
    private struct Models: Decodable { let clientModelConfigs: [Model]? }
    private struct Model: Decodable { let label: String?; let modelOrAlias: ModelAlias?; let quotaInfo: Quota? }
    private struct ModelAlias: Decodable { let model: String? }
    private struct Quota: Decodable { let remainingFraction: Double?; let resetTime: String? }
}
