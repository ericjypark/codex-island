import SwiftUI

/// One line under the Codex charts: the credit balance and the provider's
/// estimate of how many messages it buys. Shown only for accounts that
/// hold credits, so the common no-credits account sees no change.
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
        VStack(alignment: .leading, spacing: 4) {
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
            if let captionText {
                Text(captionText)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(captionText ?? amountText ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel([amountText.map { L10n.tr("%@ Codex credits remaining", $0) }, captionText]
            .compactMap { $0 }.joined(separator: ". "))
    }
}
