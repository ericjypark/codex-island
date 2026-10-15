import Foundation
import CryptoKit
import Darwin

enum MuseConnection {
    struct Failure: Error {
        let credentialID: String
        let underlying: Error
    }

    private struct AuthFile: Decodable {
        let providers: [String: StoredCredential]?
    }

    private struct StoredCredential: Decodable {
        let access_token: String?
        let mechanism: String?
    }

    static func credential(authData: Data?, keychain: () throws -> Data) throws -> String {
        if let authData {
            guard authData.count <= 1_048_576 else { throw ProviderConnectionError.invalidResponse }
            let record = try JSONDecoder().decode(AuthFile.self, from: authData).providers?["meta"]
            if let token = record?.access_token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return try deviceToken(token)
            }
            if let mechanism = record?.mechanism, mechanism.lowercased() != "oauth" {
                throw ProviderConnectionError.signIn
            }
        }
        let data = try keychain()
        guard data.count <= 1_048_576 else { throw ProviderConnectionError.invalidResponse }
        return try deviceToken(JSONDecoder().decode(StoredCredential.self, from: data).access_token)
    }

    private static func deviceToken(_ raw: String?) throws -> String {
        let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard token.hasPrefix("dca:"), token.count > 4,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ProviderConnectionError.signIn
        }
        return token
    }

    static func fetch() async throws -> ConnectedUsage {
        let token = try await Task.detached(priority: .utility) { try readCredential() }.value
        try Task.checkCancellation()
        return try await fetch(token: token, send: send, currentToken: {
            try await Task.detached(priority: .utility) { try readCredential() }.value
        })
    }

    static func fetch(token: String, send: (URLRequest) async throws -> Data,
                      currentToken: () async throws -> String) async throws -> ConnectedUsage {
        let token = try deviceToken(token)
        let identity = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let response: Result<ConnectedUsage, Error>
        do {
            response = .success(try parse(await send(request(token: token))))
        } catch {
            response = .failure(error)
        }
        do {
            try Task.checkCancellation()
            guard (try? await currentToken()) == token else { throw ProviderConnectionError.signIn }
            var usage = try response.get()
            usage.credentialID = identity
            return usage
        } catch {
            throw Failure(credentialID: identity, underlying: error)
        }
    }

    private static func readCredential() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let config = environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        let url = environment["MUSE_AUTH_PATH"].map { URL(fileURLWithPath: $0) }
            ?? config.appendingPathComponent("muse/auth.json")
        let data = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        return try credential(authData: data) {
            // Read the CLI-owned item only. Never persist the key returned by the quota endpoint.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "ai.meta.dev.credentials", "-a", "meta", "-w"]
            let pipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
            let result = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0, !result.isEmpty else { throw ProviderConnectionError.signIn }
            return result
        }
    }

    static func request(token: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.meta.ai/muse-code/key") else {
            throw ProviderConnectionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(try deviceToken(token))", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "x-api-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")
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

    private struct Response: Decodable {
        let is_subs_active: Bool?
        let require_payment: Bool?
        let subs_tier_name: String?
        let user_email: String?
        let subs_usage: Usage?
    }
    private struct Usage: Decodable {
        let window: Limit?
        let weekly: Limit?
    }
    private struct Limit: Decodable {
        let used_percent: Double?
        let resets_at: Double?
        let window_duration_mins: Int?
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> ConnectedUsage {
        guard data.count <= 2_097_152 else { throw ProviderConnectionError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.is_subs_active != nil || response.require_payment == true else {
            throw ProviderConnectionError.invalidResponse
        }
        let email = response.user_email?.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ConnectedUsage(account: email?.isEmpty == false ? email : nil,
            accountID: email?.isEmpty == false ? email?.lowercased() : nil,
            plan: response.subs_tier_name, updatedAt: now, subscriptionActive: response.is_subs_active)
        if response.require_payment == true {
            result.message = "Finish Muse Code billing setup at dev.meta.ai."
            return result
        }
        guard response.is_subs_active == true else {
            result.message = "No active Muse Code subscription. API keys use separate pay-as-you-go billing."
            return result
        }
        if let window = response.subs_usage?.window, let percent = try percentage(window.used_percent) {
            guard let minutes = window.window_duration_mins, minutes > 0, minutes <= 525_600 else {
                throw ProviderConnectionError.invalidResponse
            }
            result.limits.append(ConnectedLimit(id: "session", label: minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m",
                usedFraction: percent, resetAt: reset(window.resets_at), kind: .session))
        }
        if let weekly = response.subs_usage?.weekly, let percent = try percentage(weekly.used_percent) {
            result.limits.append(ConnectedLimit(id: "weekly", label: "week",
                usedFraction: percent, resetAt: reset(weekly.resets_at), kind: .weekly))
        }
        if result.limits.isEmpty {
            result.message = "Muse Code did not include usage limits in this response. Try again after using Muse Code."
        }
        return result
    }

    private static func percentage(_ value: Double?) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, value >= 0 else { throw ProviderConnectionError.invalidResponse }
        return min(1, value / 100)
    }

    private static func reset(_ seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite, seconds > 0, seconds <= 64_092_211_200 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func failedSnapshot(previous: ConnectedUsage?, failure: Failure?, message: String,
                               needsLogin: Bool) -> ConnectedUsage {
        if !needsLogin, let failure, var previous, previous.credentialID == failure.credentialID {
            previous.message = message
            previous.refreshFailed = true
            return previous
        }
        return ConnectedUsage(message: message, needsLogin: needsLogin)
    }
}
