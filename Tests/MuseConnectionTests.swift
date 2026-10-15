import Foundation

@main
struct MuseConnectionTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") }
        else { failures += 1; print("FAIL \(label)") }
    }
    static func data(_ text: String) -> Data { Data(text.utf8) }
    static func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); expect(false, label) } catch { expect(true, label) }
    }

    static func main() async throws {
        var keychainReads = 0
        let keychain = { keychainReads += 1; return data(#"{"access_token":"dca:keychain"}"#) }
        let inline = try MuseConnection.credential(authData: data(#"{"providers":{"meta":{"access_token":"dca:inline"}}}"#), keychain: keychain)
        expect(inline == "dca:inline" && keychainReads == 0, "inline login selects the account without reading Keychain")
        let stored = try MuseConnection.credential(authData: data(#"{"providers":{"meta":{"mechanism":"oauth"}}}"#), keychain: keychain)
        expect(stored == "dca:keychain" && keychainReads == 1, "OAuth metadata falls back to CLI Keychain")
        let keychainOnly = try MuseConnection.credential(authData: nil, keychain: keychain)
        expect(keychainOnly == "dca:keychain", "Keychain-only CLI login is supported")
        for token in ["LLM|example", "LLM_example", "dca:", "dca:a\nb"] {
            let encoded = try JSONSerialization.data(withJSONObject: ["providers": ["meta": ["access_token": token]]])
            rejects("reject inference or malformed credential") {
                _ = try MuseConnection.credential(authData: encoded, keychain: keychain)
            }
        }
        rejects("API-key login does not silently select a stale Keychain account") {
            _ = try MuseConnection.credential(authData: data(#"{"providers":{"meta":{"mechanism":"api_key"}}}"#), keychain: keychain)
        }
        rejects("malformed auth file does not select another account") {
            _ = try MuseConnection.credential(authData: data("broken"), keychain: keychain)
        }
        let request = try MuseConnection.request(token: "dca:test")
        expect(request.url?.absoluteString == "https://api.meta.ai/muse-code/key" && request.httpMethod == "POST", "quota request uses fixed Meta origin")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dca:test"
            && request.value(forHTTPHeaderField: "x-api-version") == "1.0.0"
            && request.httpBody == data("{}"), "request carries the device credential and no inference prompt")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let full = data(#"{"is_subs_active":true,"subs_tier_name":"Power Usage","user_email":"Person@example.test","api_key":"discard-this","payment_method":{"last_four":"1234"},"subs_usage":{"window":{"used_percent":38,"window_duration_mins":300,"resets_at":1800007200},"weekly":{"used_percent":62,"resets_at":1800086400}}}"#)
        let usage = try MuseConnection.parse(full, now: now)
        expect(usage.limits.map(\.label) == ["5h", "week"], "renders actual session and weekly windows")
        expect(usage.limits.map(\.usedFraction) == [0.38, 0.62], "percentages normalize once")
        expect(usage.limits.first?.resetAt == now.addingTimeInterval(7200), "reset epochs are seconds")
        expect(usage.accountID == "person@example.test" && usage.plan == "Power Usage" && usage.updatedAt == now, "identity plan and observation time are retained")
        let weekly = try MuseConnection.parse(data(#"{"is_subs_active":true,"subs_usage":{"weekly":{"used_percent":0}}}"#))
        expect(weekly.limits.count == 1 && weekly.primary?.kind == .weekly && weekly.primary?.usedFraction == 0, "weekly-only real zero never creates a five-hour window")
        let over = try MuseConnection.parse(data(#"{"is_subs_active":true,"subs_usage":{"window":{"used_percent":125,"window_duration_mins":90,"resets_at":1e100}}}"#))
        expect(over.primary?.usedFraction == 1 && over.primary?.label == "90m" && over.primary?.resetAt == nil, "over-quota is full and invalid reset does not erase usage")
        for payload in [#"{"is_subs_active":true}"#, #"{"is_subs_active":true,"subs_usage":null}"#, #"{"is_subs_active":true,"subs_usage":{"window":{"resets_at":1800007200}}}"#] {
            let absent = try MuseConnection.parse(data(payload))
            expect(absent.limits.isEmpty && absent.message != nil && !absent.hasNoActiveSubscription, "missing quota stays unknown on an active subscription")
        }
        let inactive = try MuseConnection.parse(data(#"{"is_subs_active":false,"subs_usage":{"weekly":{"used_percent":50}}}"#))
        expect(inactive.hasNoActiveSubscription && inactive.limits.isEmpty, "inactive subscription ignores stale payload quota")
        let billing = try MuseConnection.parse(data(#"{"require_payment":true}"#))
        expect(billing.limits.isEmpty && billing.message?.contains("billing") == true, "billing setup has an actionable state")
        for payload in ["{}", #"{"is_subs_active":"true"}"#, #"{"is_subs_active":true,"subs_usage":{"weekly":{"used_percent":-1}}}"#, #"{"is_subs_active":true,"subs_usage":{"window":{"used_percent":5,"window_duration_mins":0}}}"#] {
            rejects("malformed quota cannot become zero") { _ = try MuseConnection.parse(data(payload)) }
        }

        let fetched = try await MuseConnection.fetch(token: "dca:test", send: { _ in full }, currentToken: { "dca:test" })
        expect(fetched.credentialID != nil && fetched.credentialID != "dca:test", "snapshot keeps only a credential fingerprint")
        do {
            _ = try await MuseConnection.fetch(token: "dca:test", send: { _ in full }, currentToken: { "dca:other" })
            expect(false, "account switch discards in-flight result")
        } catch let failure as MuseConnection.Failure {
            if case ProviderConnectionError.signIn = failure.underlying { expect(true, "account switch discards in-flight result") }
            else { expect(false, "account switch discards in-flight result") }
        }
        do {
            _ = try await MuseConnection.fetch(token: "dca:test", send: { _ in throw ProviderConnectionError.http(503) },
                currentToken: { "dca:other" })
            expect(false, "failed request also checks for an account switch")
        } catch let failure as MuseConnection.Failure {
            if case ProviderConnectionError.signIn = failure.underlying { expect(true, "failed request also checks for an account switch") }
            else { expect(false, "failed request also checks for an account switch") }
        }
        do {
            _ = try await MuseConnection.fetch(token: "dca:test", send: { _ in full },
                currentToken: { throw ProviderConnectionError.invalidResponse })
            expect(false, "unverifiable login cannot accept an old-account response")
        } catch let failure as MuseConnection.Failure {
            if case ProviderConnectionError.signIn = failure.underlying { expect(true, "unverifiable login cannot accept an old-account response") }
            else { expect(false, "unverifiable login cannot accept an old-account response") }
        }
        let failure = MuseConnection.Failure(credentialID: fetched.credentialID ?? "", underlying: ProviderConnectionError.http(503))
        let stale = MuseConnection.failedSnapshot(previous: fetched, failure: failure, message: "Offline", needsLogin: false)
        expect(stale.limits.count == 2 && stale.refreshFailed && stale.updatedAt == fetched.updatedAt, "same-account failure preserves timestamp and readings with an error")
        let other = MuseConnection.failedSnapshot(previous: fetched,
            failure: MuseConnection.Failure(credentialID: "another-account", underlying: ProviderConnectionError.http(503)),
            message: "Offline", needsLogin: false)
        expect(other.limits.isEmpty, "failed fetch for another account cannot inherit quota")
        let loggedOut = MuseConnection.failedSnapshot(previous: fetched, failure: failure, message: "Sign in", needsLogin: true)
        expect(loggedOut.limits.isEmpty && loggedOut.needsLogin, "expired login cannot retain displayed quota")
        expect(usage.storageScope(provider: .muse) != usage.storageScope(provider: .grok), "Muse history scope cannot overlap another provider")
        print("Muse tests: \(failures) failures")
        if failures != 0 { exit(1) }
    }
}
