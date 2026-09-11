import Foundation

@main
struct ProviderSessionRecoveryTests {
    static func main() async throws {
        for error in [ProviderConnectionError.expired, .http(401)] {
            var attempts = 0
            var renewals = 0
            let usage = try await ProviderSessionRecovery.fetch {
                attempts += 1
                if attempts == 1 { throw error }
                return ConnectedUsage(plan: "recovered")
            } renew: { renewals += 1 }
            precondition(attempts == 2 && renewals == 1 && usage.plan == "recovered")
        }
        for error in [ProviderConnectionError.signIn, .http(403), .http(429), .unavailable] {
            var renewals = 0
            do {
                _ = try await ProviderSessionRecovery.fetch { throw error } renew: { renewals += 1 }
                fatalError("Expected failure")
            } catch { precondition(renewals == 0) }
        }
        var attempts = 0
        var renewals = 0
        do {
            _ = try await ProviderSessionRecovery.fetch {
                attempts += 1
                throw ProviderConnectionError.expired
            } renew: { renewals += 1 }
            fatalError("Expected failure after one retry")
        } catch { precondition(attempts == 2 && renewals == 1) }
        do {
            _ = try await ProviderSessionRecovery.fetch {
                throw ProviderConnectionError.expired
            } renew: { throw CancellationError() }
            fatalError("Expected cancellation")
        } catch is CancellationError { }
        let credential = try GrokConnection.credential(from: Data(#"{"https://auth.x.ai::a":{"key":"old","expires_at":"2000-01-01T00:00:00Z"},"https://auth.x.ai::b":{"key":"current","expires_at":"2099-01-01T00:00:00Z"}}"#.utf8))
        precondition(credential.key == "current")
        print("PASS session renewal, bounded retry, error classification, cancellation, and valid Grok credential selection")
    }
}
