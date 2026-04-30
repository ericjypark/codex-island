import Foundation

/// Embedded snapshot of per-million-token API prices in USD. Mirrors LiteLLM's
/// `model_prices_and_context_window.json` for the models we actually expect
/// in Claude Code and Codex CLI sessions, so totals cross-check against
/// `npx ccusage` and `npx @ccusage/codex` to within rounding.
///
/// To refresh: bump `snapshotDate` and re-fetch the four rates per model
/// from `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`.
/// Unknown models silently price to $0 — same behavior as ccusage when
/// LiteLLM has no entry.
enum Pricing {
    static let snapshotDate = "2026-04-30"

    struct Rates {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheCreationPerMillion: Double
        let cacheReadPerMillion: Double
    }

    private static let table: [String: Rates] = [
        // Anthropic — LiteLLM lists Opus 4-5/4-6/4-7 at the same rates
        // (cheaper than the original Opus 4 because Anthropic re-tiered the
        // Opus line in 2025).
        "claude-opus-4-7": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-6": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-5": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-sonnet-4-6": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-sonnet-4-5": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-haiku-4-5": Rates(
            inputPerMillion: 1, outputPerMillion: 5,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.10
        ),

        // OpenAI — Codex CLI tags conversations with the chat-completion
        // model name. cache_creation has no separate rate (OpenAI bills
        // cache writes at the standard input rate).
        "gpt-5.5": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 5, cacheReadPerMillion: 0.50
        ),
        "gpt-5.4": Rates(
            inputPerMillion: 2.5, outputPerMillion: 15,
            cacheCreationPerMillion: 2.5, cacheReadPerMillion: 0.25
        ),
        "gpt-5.4-mini": Rates(
            inputPerMillion: 0.75, outputPerMillion: 4.5,
            cacheCreationPerMillion: 0.75, cacheReadPerMillion: 0.075
        ),
        "gpt-5-codex": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
    ]

    /// Compute the dollar cost of a single TokenEvent. Returns 0 for unknown
    /// models — ccusage parity. Synthetic placeholder models filtered upstream.
    ///
    /// Anthropic's 1M-context tier (2x rate above 200k tokens) is omitted —
    /// it only affects sonnet-4-5 with the 1M flag and is rarely hit in
    /// Claude Code workflows. ccusage's per-bucket threshold check would
    /// disagree with Anthropic's per-position-in-context billing anyway.
    static func cost(for event: TokenEvent) -> Double {
        let lookup = canonicalModel(event.model)
        guard let rates = table[lookup] else { return 0 }

        let input = Double(event.inputTokens) / 1_000_000 * rates.inputPerMillion
        let output = Double(event.outputTokens) / 1_000_000 * rates.outputPerMillion
        let cacheCreate = Double(event.cacheCreationTokens) / 1_000_000 * rates.cacheCreationPerMillion
        let cacheRead = Double(event.cacheReadTokens) / 1_000_000 * rates.cacheReadPerMillion

        return input + output + cacheCreate + cacheRead
    }

    /// Strip Anthropic-style date suffixes (e.g. "claude-haiku-4-5-20251001"
    /// → "claude-haiku-4-5") so the snapshot table doesn't need an entry per
    /// pinned release.
    private static func canonicalModel(_ raw: String) -> String {
        guard raw.count > 9 else { return raw }
        let suffixStart = raw.index(raw.endIndex, offsetBy: -9)
        let suffix = raw[suffixStart...]
        guard suffix.first == "-",
              suffix.dropFirst().allSatisfy({ $0.isNumber })
        else { return raw }
        return String(raw[..<suffixStart])
    }
}
