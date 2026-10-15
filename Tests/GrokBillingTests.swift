import Foundation

@main
struct GrokBillingTests {
    static func data(_ text: String) -> Data { Data(text.utf8) }

    static func main() async throws {
        let credential = data(#"{"https://auth.x.ai::fixture":{"key":"fixture-token","user_id":"fixture-user","expires_at":"2099-01-01T00:00:00Z"}}"#)
        let weekly = data(#"{"config":{"creditUsagePercent":42.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2099-01-08T00:00:00Z"},"onDemandUsed":{"val":25},"onDemandCap":{"val":100}}}"#)
        let monthly = data(#"{"config":{"monthlyLimit":{"val":"2000"},"used":{"val":"500"},"billingPeriodEnd":"2099-02-01T00:00:00Z"}}"#)
        let parsed = try GrokConnection.parse(weekly)
        precondition(parsed.primary?.usedFraction == 0.425 && parsed.primary?.kind == .weekly)
        precondition(parsed.limits.count == 1, "Extra spending must not become a subscription metric")
        let monthlyParsed = try GrokConnection.parse(monthly)
        precondition(monthlyParsed.primary?.usedFraction == 0.25 && monthlyParsed.primary?.label == "month")
        precondition(monthlyParsed.primary?.resetAt == ProviderPayload.date("2099-02-01T00:00:00Z"))
        for payload in [
            #"{"config":{"onDemandUsed":{"val":25},"onDemandCap":{"val":100}}}"#,
            #"{"config":{"currentPeriod":{"end":"2099-01-08T00:00:00Z"}}}"#,
            #"{"config":{"monthlyLimit":{"val":0},"used":{"val":0}}}"#,
            #"{"config":{"monthlyLimit":{"val":100},"used":{"val":-1}}}"#
        ] {
            let unknown = try GrokConnection.parse(data(payload))
            precondition(unknown.primary == nil)
        }
        var paths: [String] = []
        let fetched = try await GrokConnection.fetch(credentialData: credential) { request in
            precondition(request.url?.host == "cli-chat-proxy.grok.com")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            precondition(request.value(forHTTPHeaderField: "x-userid") == "fixture-user")
            precondition(request.value(forHTTPHeaderField: "x-grok-client-mode") == "cli")
            let path = request.url?.absoluteString ?? ""
            paths.append(path)
            if path.hasSuffix("billing?format=credits") {
                return data(#"{"config":{"isUnifiedBillingUser":true,"currentPeriod":{"end":"2099-01-08T00:00:00Z"}}}"#)
            }
            if path.hasSuffix("/billing") { return monthly }
            return data(#"{"subscription_tier_display":"SuperGrok"}"#)
        }
        precondition(paths.count == 3 && fetched.limits.count == 1)
        precondition(fetched.primary?.usedFraction == 0.25 && fetched.plan == "SuperGrok")
        let retained = try await GrokConnection.fetch(credentialData: credential) { request in
            if request.url?.query == "format=credits" {
                return data(#"{"config":{"creditUsagePercent":42.5,"isUnifiedBillingUser":true,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}"#)
            }
            throw ProviderConnectionError.http(503)
        }
        precondition(retained.primary?.usedFraction == 0.425)
        do {
            _ = try await GrokConnection.fetch(credentialData: credential) { request in
                if request.url?.query == "format=credits" { return data(#"{"config":{}}"#) }
                throw ProviderConnectionError.http(503)
            }
            fatalError("Failed monthly fetch must not invent full remaining quota")
        } catch ProviderConnectionError.http(503) {}
        print("PASS Grok subscription parsing, monthly fallback, request identity, and partial failure handling")
    }
}
