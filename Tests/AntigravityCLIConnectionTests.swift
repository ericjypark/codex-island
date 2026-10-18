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
                // The backend gates Gemini and Argon on the CLI client profile.
                return Data((request.value(forHTTPHeaderField: "User-Agent") == "antigravity/cli/1.4.2"
                    ? cliQuota : legacyQuota).utf8)
            default: fatalError("Unexpected endpoint")
            }
        }
        precondition(requests.count == 2 && requests.allSatisfy { $0.url?.host == "daily-cloudcode-pa.googleapis.com" },
                     "Both requests must use agy's backend to avoid reporting an unrelated, unused quota")
        precondition(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" })
        precondition(usage.limits.count == 5, "The CLI profile must return Gemini, Claude/GPT, and Argon quotas")
        precondition(usage.accountID == "fixture-project" && usage.plan == "AI Pro")
        precondition(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "antigravity/cli/1.4.2" },
                     "Both account loading and quota retrieval must identify the CLI client")
        precondition(usage.limits[1].kind == .session && usage.limits[1].usedFraction == 0.25)
        print("PASS CLI session fetches project-scoped quota without a desktop process")
        let argon = usage.limits.filter { $0.groupID == "Gemini 4 Argon" }
        precondition(argon.count == 1 && argon[0].id == "gemini-argon-wtu-weekly" && argon[0].kind == .weekly,
                     "Argon keeps its own weekly bucket without a synthetic five-hour window")
        precondition(argon[0].usedFraction == 0 && argon[0].resetAt != nil,
                     "A real unused Argon quota and its reset time must survive parsing")
        print("PASS Gemini, Claude/GPT, and weekly-only Argon retain separate quota identities")
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

    private static let legacyQuota = #"{"groups":[{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","remainingFraction":0.5},{"bucketId":"3p-5h","displayName":"Five Hour Limit Remaining","remainingFraction":0.75}]}]}"#
    private static let cliQuota = #"""
    {"groups":[
      {"displayName":"Gemini Models","buckets":[
        {"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","remainingFraction":1},
        {"bucketId":"gemini-5h","displayName":"Five Hour Limit Remaining","remainingFraction":0.75}]},
      {"displayName":"Claude and GPT models","buckets":[
        {"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","remainingFraction":0.5},
        {"bucketId":"3p-5h","displayName":"Five Hour Limit Remaining","remainingFraction":0.75}]},
      {"displayName":"Gemini 4 Argon","buckets":[
        {"bucketId":"gemini-argon-wtu-weekly","displayName":"Gemini 4 Argon Weekly Limit","remainingFraction":1,"resetTime":"2099-01-01T00:00:00Z"}]}
    ]}
    """#
}
