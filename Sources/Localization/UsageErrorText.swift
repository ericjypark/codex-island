import Foundation

enum UsageErrorText {
    static func display(_ error: String) -> String {
        switch error {
        case "no data":
            return L10n.tr("No usage data")
        case "no codex auth":
            return L10n.tr("No Codex authentication")
        case "auth expired — codex login":
            return L10n.tr("Codex authentication expired — run codex login")
        case "auth required — run claude":
            return L10n.tr("Claude authentication required — run claude")
        case "rate limited":
            return L10n.tr("Rate limited")
        case "parse error":
            return L10n.tr("Unable to parse usage response")
        case UsageFetcher.claudeReauthRequiredMessage:
            return L10n.tr("Claude re-authentication required — run claude /login")
        default:
            if error.hasPrefix("http ") {
                let status = String(error.dropFirst("http ".count))
                return L10n.tr("HTTP %@", status)
            }
            return error
        }
    }
}
