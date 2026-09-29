import Foundation
import CryptoKit

struct StoredSample: Decodable { let at: Date; let used: Double }
struct ExportSample: Encodable { let atMilliseconds: Double; let used: Double }
struct ExportSnapshot: Encodable { let schemaVersion: Int; let copiedAt: Double; let sourceKey: String; let sourceSha256: String; let series: [String: [ExportSample]] }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let key = "CodexIsland.usageHistory.v1"
guard let source = UserDefaults(suiteName: "dev.codexisland.CodexIsland")?.data(forKey: key) else {
    fputs("No saved Mac quota samples were found.\n", stderr)
    exit(1)
}
let decoded = try JSONDecoder().decode([String: [StoredSample]].self, from: source)
let supported = Set(["claude.fiveHour", "claude.weekly", "codex.fiveHour", "codex.weekly"])
let series = decoded.filter { supported.contains($0.key) }.mapValues { samples in
    samples.map { ExportSample(atMilliseconds: $0.at.timeIntervalSince1970 * 1000, used: $0.used * 100) }
}
guard series.values.allSatisfy({ $0.allSatisfy { $0.used.isFinite && (0...100).contains($0.used) } }) else {
    throw NSError(domain: "MacQuotaSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "The stored quota readings are invalid."])
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
let encoded = try encoder.encode(ExportSnapshot(schemaVersion: 1, copiedAt: Date().timeIntervalSince1970,
    sourceKey: key, sourceSha256: SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined(), series: series))
try encoded.write(to: destination.appendingPathComponent("mac-quota-samples.json"), options: .atomic)
print("Copied Mac quota observations: " + series.keys.sorted().map { "\($0)=\(series[$0]?.count ?? 0)" }.joined(separator: ", "))
