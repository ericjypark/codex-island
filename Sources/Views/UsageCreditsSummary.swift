import SwiftUI

struct UsageCreditsSummary: View {
    let window: WindowUsage
    let color: Color
    let mode: UsageDisplayMode

    var amountText: String? {
        guard let used = window.usedAmount else { return nil }
        let amount = UsageCreditDisplay.currency(used, code: window.currencyCode)
        guard let limit = window.limitAmount else { return amount }
        return amount + " / " + UsageCreditDisplay.currency(limit, code: window.currencyCode)
    }

    var statusText: String {
        var parts: [String] = []
        if let error = window.error, error != "no data" { parts.append(error) }
        if window.isUnlimitedAmount { parts.append(L10n.tr("Unlimited")) }
        if let reset = window.resetAt {
            parts.append(L10n.tr("resets in %@", Duration.compact(max(0, reset.timeIntervalSinceNow))))
        }
        if parts.isEmpty && !window.hasReading { parts.append(L10n.tr("No recorded reading")) }
        return parts.joined(separator: " · ")
    }

    var reading: QuotaChartReading {
        QuotaChartReading(id: UsageWindow.monthly.rawValue, label: L10n.tr("Credits"),
            value: window.hasPercentageReading
                ? Double(DisplayNumber.percent(window.displayedFraction(mode: mode) * 100)) : nil,
            caption: [window.amountCaption, statusText.isEmpty ? nil : statusText]
                .compactMap { $0 }.joined(separator: " · "),
            amount: window.isUnlimitedAmount ? amountText : nil)
    }

    var body: some View {
        let reading = reading
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title(reading).fixedSize()
                    Spacer(minLength: 8)
                    amount.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    title(reading)
                    amount.fixedSize(horizontal: false, vertical: true)
                }
            }
            if let value = reading.value {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(color).frame(width: geometry.size.width * value / 100)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(reading.caption)
        .modifier(QuotaAccessibility(reading: reading, mode: mode))
    }

    private func title(_ reading: QuotaChartReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reading.label).font(Typography.label).foregroundStyle(.white.opacity(0.7))
            QuotaValue(reading: reading, mode: mode, size: 13)
        }
    }

    private var amount: some View {
        Text(amountText ?? "")
            .font(Typography.caption)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.leading)
    }
}
