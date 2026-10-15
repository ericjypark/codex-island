import Foundation

@main
struct AntigravityCLIConnectionTests {
    static func main() async throws {
        let credential = Data(#"{"token":{"access_token":"fixture-only","expiry":"2099-01-01T00:00:00Z"},"auth_method":"consumer"}"#.utf8)
        var requests: [URLRequest] = []
        let usage = try await AntigravityConnection.fetch(credentialData: credential) { request in
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "v1internal:loadCodeAssist":
                return Data(#"{"cloudaicompanionProject":"fixture-project","paidTier":{"name":"AI Pro"}}"#.utf8)
            case "v1internal:retrieveUserQuotaSummary":
                let payload = try JSONDecoder().decode(ProjectRequest.self, from: request.httpBody ?? Data())
                precondition(payload.project == "fixture-project", "Quota requires the account project from loadCodeAssist")
                return Data(#"{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"weekly","displayName":"Weekly Limit Remaining","remainingFraction":1},{"bucketId":"session","displayName":"Five Hour Limit Remaining","remainingFraction":0.75}]}]}"#.utf8)
            default: fatalError("Unexpected endpoint")
            }
        }
        precondition(requests.count == 2 && requests.allSatisfy { $0.url?.host == "daily-cloudcode-pa.googleapis.com" },
                     "Both requests must use agy's backend to avoid reporting an unrelated, unused quota")
        precondition(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" })
        precondition(usage.limits.count == 2 && usage.accountID == "fixture-project" && usage.plan == "AI Pro")
        precondition(usage.limits[1].kind == .session && usage.limits[1].usedFraction == 0.25)
        print("PASS CLI session fetches project-scoped quota without a desktop process")
        let encoded = Data(("go-keyring-base64:" + credential.base64EncodedString() + "\n").utf8)
        _ = try AntigravityConnection.credential(from: encoded)
        print("PASS CLI keyring base64 wrapper is decoded")
        do {
            _ = try await AntigravityConnection.fetch(credentialData: Data(#"{"token":{"access_token":"fixture-only","expiry":"2000-01-01T00:00:00Z"},"auth_method":"consumer"}"#.utf8)) { _ in
                fatalError("Expired credentials must not call the API")
            }
            fatalError("Expected expired credential rejection")
        } catch ProviderConnectionError.expired { print("PASS expired CLI tokens remain owned by agy") }
        do {
            _ = try await AntigravityConnection.fetch(credentialData: credential) { _ in
                Data(#"{"currentTier":{"name":"Free"}}"#.utf8)
            }
            fatalError("Missing project must not issue an unscoped quota request")
        } catch ProviderConnectionError.invalidResponse { print("PASS missing project cannot become a false login error") }
    }
    private struct ProjectRequest: Decodable { let project: String }
}
