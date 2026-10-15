import Foundation

@main
struct ProviderConnectionTests {
    static var failures = 0
    static func expect(_ value: Bool, _ label: String) {
        if value { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
    }
    static func data(_ text: String) -> Data { Data(text.utf8) }

    @MainActor
    static func main() throws {
        var unsubscribed = ConnectedUsage(limits: [
            ConnectedLimit(id: "credits", label: "Credits", usedFraction: nil, resetAt: Date())
        ], plan: " FREE ", updatedAt: Date())
        expect(unsubscribed.hasNoActiveSubscription, "free account without a reading shows subscription state")
        unsubscribed.limits[0] = ConnectedLimit(id: "credits", label: "Credits", usedFraction: 0, resetAt: nil)
        expect(!unsubscribed.hasNoActiveSubscription, "real zero usage remains visible even on free plans")
        unsubscribed.limits = []
        unsubscribed.plan = "SuperGrok"
        expect(!unsubscribed.hasNoActiveSubscription, "missing paid-plan data is not an inactive subscription")
        unsubscribed.plan = nil
        expect(!unsubscribed.hasNoActiveSubscription, "unknown plans are not treated as unsubscribed")
        unsubscribed.plan = "free"
        unsubscribed.needsLogin = true
        expect(!unsubscribed.hasNoActiveSubscription, "sign-in failures take precedence over subscription state")
        expect(!ConnectedUsage(plan: "free").hasNoActiveSubscription, "subscription state requires a successful fetch")
        let suite = "CodexIsland.ProviderTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot create test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        var store = ProviderVisibilityStore(defaults: defaults)
        expect(store.selected == [.claude, .codex], "new install preserves the existing two providers")
        store.set(nil, at: 0)
        expect(store.selected.count == 2, "left slot cannot be removed")
        store.set(nil, at: 1)
        store.set(.codex, at: 0)
        expect(store.left == .codex && store.right == nil, "single Codex occupies left slot")
        store.swap()
        expect(store.selected == [.codex], "single provider swap is a no-op")
        store.set(.codex, at: 1)
        expect(store.selected == [.codex], "adding duplicate cannot consume second slot")
        store.set(.antigravity, at: 1)
        store.swap()
        expect(store.selected == [.antigravity, .codex], "swap changes both positions")
        store.set(.grok, at: 1)
        expect(store.selected == [.antigravity, .grok], "replacing a slot keeps the other intact")
        store.set(.grok, at: 0)
        expect(store.selected == [.grok, .antigravity], "choosing occupied provider swaps slots")
        store = ProviderVisibilityStore(defaults: defaults)
        expect(store.selected == [.grok, .antigravity], "order survives relaunch")
        for left in IslandProvider.allCases {
            for right in IslandProvider.allCases {
                store.set(left, at: 0)
                store.set(right, at: 1)
                expect((1...2).contains(store.selected.count) && Set(store.selected).count == store.selected.count,
                       "valid selection for \(left) / \(right)")
            }
        }
        defaults.removeObject(forKey: ProviderVisibilityStore.selectionKey)
        defaults.set(false, forKey: "MacIsland.claudeVisible")
        defaults.set(true, forKey: "MacIsland.codexVisible")
        store = ProviderVisibilityStore(defaults: defaults)
        expect(store.selected == [.codex], "migrates Codex-only preference to left")
        defaults.removeObject(forKey: ProviderVisibilityStore.selectionKey)
        defaults.set(false, forKey: "MacIsland.codexVisible")
        store = ProviderVisibilityStore(defaults: defaults)
        expect(store.selected == [.claude], "migrates both hidden to one provider")
        defaults.set(["unknown", "grok", "grok", "antigravity", "codex"], forKey: ProviderVisibilityStore.selectionKey)
        store = ProviderVisibilityStore(defaults: defaults)
        expect(store.selected == [.grok, .antigravity], "repairs invalid, duplicate, and over-capacity preferences")

        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let credential = try GrokConnection.credential(from: data(#"{"https://accounts.x.ai/sign-in":{"key":"legacy"},"https://auth.x.ai::test":{"key":"oidc","expires_at":"2099-01-01T00:00:00Z"}}"#), now: now)
        expect(credential.key == "oidc", "prefers SuperGrok OAuth over legacy session")
        do {
            _ = try GrokConnection.credential(from: data(#"{"https://auth.x.ai::test":{"key":"expired","expires_at":"2020-01-01T00:00:00Z"}}"#), now: now)
            expect(false, "expired token rejected")
        } catch ProviderConnectionError.expired { expect(true, "expired token rejected") }
        let zero = try GrokConnection.parse(data(#"{"config":{"creditUsagePercent":0}}"#))
        expect(zero.primary?.usedFraction == 0, "zero credits is a real reading")
        let unknown = try GrokConnection.parse(data(#"{"config":{"currentPeriod":{"end":"2099-01-01T00:00:00Z"}}}"#))
        expect(unknown.primary == nil && unknown.message != nil, "period-only billing does not invent zero")
        let ratio = try GrokConnection.parse(data(#"{"config":{"onDemandUsed":{"val":25},"onDemandCap":{"val":100}}}"#))
        expect(ratio.primary == nil, "extra spending cannot substitute for subscription usage")
        let invalid = try GrokConnection.parse(data(#"{"config":{"creditUsagePercent":-10}}"#))
        expect(invalid.primary == nil, "negative quota is not a reading")

        let summary = try AntigravityConnection.parse(data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"displayName":"Five hours","remaining":{"case":"remainingFraction","value":0.7}},{"displayName":"Weekly","remainingFraction":0},{"disabled":true,"remainingFraction":1}]}]}}"#))
        expect(summary.limits.count == 2, "reads quota groups and excludes disabled buckets")
        expect(abs((summary.primary?.usedFraction ?? 0) - 0.3) < 0.0001, "remaining converts to used")
        expect(summary.limits[1].usedFraction == 1, "zero remaining means fully used")
        let missing = try AntigravityConnection.parse(data(#"{"groups":[{"displayName":"Gemini","buckets":[{"displayName":"Weekly"}]}]}"#))
        expect(missing.primary == nil, "missing Antigravity fraction stays unknown")
        let legacy = try AntigravityConnection.parse(data(#"{"userStatus":{"email":"fixture@example.test","cascadeModelConfigData":{"clientModelConfigs":[{"label":"Gemini","quotaInfo":{"remainingFraction":0.5,"resetTime":"2099-01-01T00:00:00.000Z"}}]}}}"#))
        expect(legacy.primary?.usedFraction == 0.5 && legacy.account == "fixture@example.test", "legacy model quotas and identity are parsed")
        do {
            _ = try AntigravityConnection.parse(data(#"{"userStatus":{}}"#))
            expect(false, "availability-only response rejected")
        } catch { expect(true, "availability-only response rejected") }
        let defaultsSelection = QuotaSelection()
        let automatic = ProviderQuotaPreferences.resolve(summary, selection: defaultsSelection)
        expect(automatic.map(\.kind) == [.session, .weekly], "Antigravity defaults order session then week")
        var reordered = summary
        reordered.limits.reverse()
        expect(ProviderQuotaPreferences.resolve(reordered, selection: defaultsSelection).map(\.id) == automatic.map(\.id),
               "API ordering cannot change displayed metrics")
        let custom = QuotaSelection(groupID: automatic[0].groupID,
                                    metricIDs: [automatic[1].id, automatic[0].id], primaryID: automatic[1].id)
        let resolved = ProviderQuotaPreferences.resolve(summary, selection: custom)
        expect(resolved.map(\.id) == custom.metricIDs, "custom order is preserved")
        expect(ProviderQuotaPreferences.primary(resolved, selection: custom)?.kind == .weekly,
               "peek and alert select the same custom metric")
        let prefs = ProviderQuotaPreferences(defaults: defaults)
        prefs.save(custom, for: "fixture")
        expect(ProviderQuotaPreferences(defaults: defaults).selection(for: "fixture") == custom,
               "metric preferences survive relaunch")
        expect(ProviderQuotaPreferences.resolve(summary, selection: QuotaSelection(groupID: "removed")).isEmpty,
               "removed pinned group is not silently replaced")
        var otherAccount = summary
        otherAccount.accountID = "another-account"
        expect(summary.historyKey(provider: .antigravity, limit: automatic[0]) !=
               otherAccount.historyKey(provider: .antigravity, limit: automatic[0]), "history is isolated by account")
        expect(ProviderQuotaPreferences.resolve(zero, selection: defaultsSelection).count == 1,
               "Grok gets one real credits metric")
        let tolerant = try GrokConnection.credential(from: data(#"{"unrelated":{"value":true},"https://auth.x.ai::test":{"key":"valid"}}"#))
        expect(tolerant.key == "valid", "unrelated auth entries cannot break Grok session reading")
        if failures > 0 { exit(1) }
    }
}
