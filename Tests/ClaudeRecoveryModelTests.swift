import Foundation

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
}

@main
@MainActor
struct ClaudeRecoveryModelTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ label: String) {
        guard condition else { print("FAIL \(label)"); exit(1) }
        checks += 1
        print("PASS \(label)")
    }

    static func wait(_ model: ClaudeRecoveryModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isWorking && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(!model.isWorking, "background recovery work finishes")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-model-tests-\(UUID().uuidString)")
        let projects = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = """
        {"type":"assistant","timestamp":"2026-01-09T03:00:00Z","requestId":"request","message":{"id":"message","model":"claude-sonnet-4-6","usage":{"input_tokens":100}}}
        """
        try Data(line.utf8).write(to: projects.appendingPathComponent("session.jsonl"))
        let ledger = UsageLedger(url: root.appendingPathComponent("archive/usage.sqlite3"))
        var refreshed = 0
        let model = ClaudeRecoveryModel(ledger: ledger, defaultRoots: [projects], defaultPreferences: [], onSaved: { refreshed += 1 })
        expect(!model.canSave, "Import is disabled before preview")
        model.save()
        expect(!model.isSaving && !FileManager.default.fileExists(atPath: ledger.url.path), "saving without a preview has no side effects")
        model.scan()
        expect(model.isScanning && !model.canSave, "Import stays disabled during scanning")
        try await wait(model)
        expect(model.preview?.additionalTokens == 100 && model.canSave, "a successful preview enables Import for its exact counts")
        expect(!FileManager.default.fileExists(atPath: ledger.url.path), "the Settings preview leaves the archive untouched")

        model.timeZoneID = "Asia/Seoul"
        expect(model.preview == nil && !model.canSave, "changing timezone invalidates the old preview")
        model.scan()
        model.timeZoneID = "America/Chicago"
        try await Task.sleep(nanoseconds: 200_000_000)
        expect(model.preview == nil && !model.isScanning && !model.canSave, "a cancelled scan cannot restore a stale preview")
        model.scan()
        try await wait(model)
        model.addSources([projects], arePreferences: false)
        expect(model.preview == nil && !model.canSave, "adding a source requires a new preview")
        model.scan()
        try await wait(model)
        model.removeSource(projects, isPreference: false)
        expect(model.preview == nil && !model.canSave, "removing a source requires a new preview")
        model.scan()
        try await wait(model)
        model.save()
        model.save()
        expect(model.isSaving && !model.canSave, "Import cannot start twice while saving")
        try await wait(model)
        expect(model.outcome?.tokens == 100 && model.outcome?.didSave == true && refreshed == 1, "successful import refreshes usage exactly once")
        expect(!model.canSave, "a completed import cannot be replayed from the same screen")
        model.scan()
        try await wait(model)
        expect(model.preview?.additionalTokens == 0 && !model.canSave, "rescanning saved usage shows no additions and disables Import")

        model.timeZoneID = "No/SuchZone"
        model.scan()
        expect(model.errorMessage != nil && !model.isWorking && !model.canSave, "invalid settings show an actionable error instead of an import")
        print("PASS all \(checks) recovery Settings state checks")
    }
}
