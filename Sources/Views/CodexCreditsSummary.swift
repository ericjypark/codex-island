import SwiftUI

/// One line under the Codex charts with the credit balance. The provider's
/// estimate of how many messages it buys stays in the tooltip and the
/// VoiceOver label so the panel shows a single number. Shown only for
/// accounts that hold credits, so the common no-credits account sees no change.
struct CodexCreditsSummary: View {
    let credits: CodexCredits

    // Floor so a remaining figure never reads higher than the real balance.
    private var amountText: String? {
        if credits.unlimited { return L10n.tr("Unlimited") }
        guard let balance = credits.balance else { return nil }
        return DisplayNumber.money(balance.rounded(.down), wholeUnits: true, locale: L10n.locale)
    }

    private var captionText: String? {
        var parts: [String] = []
        if let local = credits.localMessages {
            parts.append(L10n.tr("≈ %@ local messages", rangeText(local)))
        }
        if let cloud = credits.cloudMessages {
            parts.append(L10n.tr("≈ %@ cloud messages", rangeText(cloud)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func rangeText(_ range: ClosedRange<Int>) -> String {
        let low = DisplayNumber.count(range.lowerBound, locale: L10n.locale)
        let high = DisplayNumber.count(range.upperBound, locale: L10n.locale)
        return low == high ? low : low + "–" + high
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.tr("Credits"))
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 8)
            if let amountText {
                Text(amountText)
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(captionText ?? amountText ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel([amountText.map { L10n.tr("%@ Codex credits remaining", $0) }, captionText]
            .compactMap { $0 }.joined(separator: ". "))
    }
}
