import Foundation

/// A single billable unit of token consumption parsed from a local session log.
/// Both `ClaudeLogReader` and `CodexLogReader` emit these so the cost pipeline
/// downstream is provider-agnostic.
struct TokenEvent {
    enum Provider {
        case claude
        case codex
    }

    let provider: Provider
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    /// Tokens written to the prompt cache during this turn. Anthropic-only.
    let cacheCreationTokens: Int
    /// Tokens served from the prompt cache during this turn. Both providers
    /// (Codex calls these "cached_input_tokens" — they are billed at a
    /// discount but still draw from the input bucket).
    let cacheReadTokens: Int
}
