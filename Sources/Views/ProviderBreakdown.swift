import SwiftUI

// MARK: - Per-model breakdown
//
// Shown in the half of the panel freed when one provider is toggled off in
// Settings → Providers. Powered by `CostStore`'s `recentByModel` rolling
// 5-hour window — the same data both pages already consume, so no extra
// fetch.
//
// Two flavors share row layout, capsule bar, and header:
//   - `PerModelTokenBreakdown` (usage page): trailing column is token volume.
//   - `PerModelCostBreakdown`  (cost page):  trailing column is dollar spend.
//
// Both intentionally do NOT respect `StylePref.style` (chart-style cycling)
// — the breakdown is a different vocabulary (table, not gauge) and the
// footer chip already communicates which style the live tiles are using.

/// Visual weights mapped by row index — top model dominates, lesser models
/// recede. Independent of % share so a single-active-model run still reads
/// as "the active row" rather than four faded peers.
private let perModelRowWeights: [Double] = [0.85, 0.55, 0.40, 0.30]

/// Maximum rows shown — beyond this the column gets crowded at 96pt height.
/// Surplus models are still summed into the cost-page footer total so the
/// dollar figure stays honest; the usage-page footer just shows the reset
/// countdown so the omission is invisible there.
private let perModelRowLimit = 3

private func providerBrandColor(_ provider: AlertEngine.Provider) -> Color {
    switch provider {
    case .claude: return IslandColor.claude
    case .codex:  return IslandColor.codex
    }
}

private func providerLowerLabel(_ provider: AlertEngine.Provider) -> String {
    switch provider {
    case .claude: return "claude"
    case .codex:  return "codex"
    }
}

@MainActor
private func recentRows(for provider: AlertEngine.Provider, store: CostStore) -> [ModelUsageRow] {
    switch provider {
    case .claude: return store.claude.recentByModel
    case .codex:  return store.codex.recentByModel
    }
}

// MARK: - Shared header

private struct PerModelHeader: View {
    /// "5h" on the usage page, "5h $" on the cost page — a single-glyph
    /// hint so the user knows at a glance which metric the trailing column
    /// is showing.
    let trailingHint: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("BY MODEL")
                .font(Typography.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            Text("·")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.32))
            Text(trailingHint)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.lowercase)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared capsule bar

private struct PerModelBar: View {
    let percent: Int
    let color: Color
    let weight: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.06))
                    .frame(height: 5)
                if percent > 0 {
                    Capsule()
                        .fill(color.opacity(weight))
                        .frame(
                            width: max(2, geo.size.width * CGFloat(percent) / 100),
                            height: 5
                        )
                        .animation(.strongEaseOut, value: percent)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Token-flavored breakdown (usage page)

struct PerModelTokenBreakdown: View {
    let provider: AlertEngine.Provider
    /// 5h window for the live provider. Used to step out of the way when
    /// the API errored — the live tile in the other half already surfaces
    /// the real error text; we don't fabricate a model breakdown over it.
    let window: WindowUsage

    @ObservedObject private var costStore = CostStore.shared

    private var rows: [ModelUsageRow] {
        Array(recentRows(for: provider, store: costStore).prefix(perModelRowLimit))
    }
    private var color: Color { providerBrandColor(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PerModelHeader(trailingHint: "5h")

            if let err = window.error, err != "no data" {
                Spacer(minLength: 0)
            } else if rows.isEmpty {
                Spacer(minLength: 0)
                Text("no \(providerLowerLabel(provider)) activity in last 5h")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.element.model) { idx, row in
                        PerModelTokenRow(
                            name: row.displayName,
                            percent: Int((row.percent * 100).rounded()),
                            tokens: Self.formatTokens(row.tokens),
                            color: color,
                            weight: perModelRowWeights[min(idx, perModelRowWeights.count - 1)]
                        )
                    }
                }
                Spacer(minLength: 0)
                PerModelTokenFooter(resetAt: window.resetAt)
            }
        }
    }

    /// 12_345 → "12K", 1_234_567 → "1.2M". Matches the CostBlock short-form
    /// vocabulary so the panel uses one set of unit suffixes.
    private static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return "\(n / 1_000)K" }
        return "\(n)"
    }
}

private struct PerModelTokenRow: View {
    let name: String
    let percent: Int
    let tokens: String
    let color: Color
    let weight: Double

    /// Fixed column widths — the whole point of the table is that the digits
    /// don't dance when polling delivers a new value. SF Mono helps within
    /// a column but not across them. `nameWidth` is sized for the longest
    /// realistic display name in either provider's catalog (`o4-mini-high`
    /// at 11pt medium ≈ 70pt); 76pt buys a small safety margin without
    /// starving the bar.
    private static let nameWidth: CGFloat = 76
    private static let percentWidth: CGFloat = 30
    private static let tokensWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: Self.nameWidth, alignment: .leading)
                .lineLimit(1)

            PerModelBar(percent: percent, color: color, weight: weight)

            Text("\(percent)%")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(percent == 0 ? 0.32 : 0.55))
                .frame(width: Self.percentWidth, alignment: .trailing)

            Text(tokens)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(percent == 0 ? 0.32 : 0.40))
                .frame(width: Self.tokensWidth, alignment: .trailing)
        }
    }
}

/// Footer: live reset countdown only. The prototype's "burn rate" line was
/// a hand-coded stub; without a rolling buffer in UsageStore we can't
/// compute a real one, and shipping a fabricated number undermines the
/// rest of the panel.
private struct PerModelTokenFooter: View {
    let resetAt: Date?

    var body: some View {
        // 30s tick is fine — `Duration.compact` only changes at minute /
        // hour boundaries.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack(spacing: 6) {
                Text(resetCaption(now: ctx.date))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
        }
    }

    private func resetCaption(now: Date) -> String {
        guard let r = resetAt else { return "5h window" }
        let delta = max(0, r.timeIntervalSince(now))
        return "resets in \(Duration.compact(delta))"
    }
}

// MARK: - Cost-flavored breakdown (cost page)

struct PerModelCostBreakdown: View {
    let provider: AlertEngine.Provider

    @ObservedObject private var costStore = CostStore.shared

    /// Full set of rows for the footer total — must include models past
    /// the display limit so "total · 5h" stays honest. Without this, a
    /// fourth-and-beyond model that burned real dollars would silently
    /// disappear from the sum and the footer figure would diverge from
    /// the cost-page Today figure (when today equals last 5h).
    private var allRows: [ModelUsageRow] {
        recentRows(for: provider, store: costStore)
    }
    private var displayedRows: [ModelUsageRow] {
        Array(allRows.prefix(perModelRowLimit))
    }
    private var color: Color { providerBrandColor(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PerModelHeader(trailingHint: "5h $")

            if allRows.isEmpty {
                Spacer(minLength: 0)
                Text("no \(providerLowerLabel(provider)) activity in last 5h")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(displayedRows.enumerated()), id: \.element.model) { idx, row in
                        PerModelCostRow(
                            name: row.displayName,
                            dollars: row.dollars,
                            color: color,
                            weight: perModelRowWeights[min(idx, perModelRowWeights.count - 1)]
                        )
                    }
                }
                Spacer(minLength: 0)
                PerModelCostFooter(allRows: allRows, displayedCount: displayedRows.count)
            }
        }
    }
}

/// Cost-page row drops the capsule bar that the token row uses. The bar's
/// fill metric on the usage page (token share) doesn't translate to the
/// cost page — a cache-read-heavy model can have ~0 billable tokens but
/// non-zero dollars, which would render as a near-empty bar next to a
/// sizable dollar number. The dollar string itself encodes magnitude
/// unambiguously, so the bar is just visual noise here. Removing it also
/// frees ~bar width to widen the model-name column for longer ids
/// (`o4-mini-high` etc.). The brand-tinted dollar caption preserves the
/// row's color identity.
private struct PerModelCostRow: View {
    let name: String
    let dollars: Double
    let color: Color
    let weight: Double

    /// Wider than the token row's 64pt — needed for OpenAI reasoning
    /// models like `o4-mini-high` and Claude composite ids that
    /// `prettyModelName` can't shorten further. Stays the same on usage
    /// rows for visual rhythm; widening only here is fine because the
    /// usage row has three trailing columns to balance, the cost row
    /// only one.
    private static let nameWidth: CGFloat = 100
    private static let dollarsWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: Self.nameWidth, alignment: .leading)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(formatDollars(dollars))
                .font(Typography.bodyNumber)
                .foregroundStyle(color.opacity(dollars > 0 ? max(0.55, weight) : 0.32))
                .frame(width: Self.dollarsWidth, alignment: .trailing)
        }
    }

    /// Adaptive precision: under $1 shows two decimals (1¢ resolution);
    /// under $10 shows one decimal; otherwise round to the nearest dollar
    /// so the column stays narrow and readable at a glance.
    private func formatDollars(_ amount: Double) -> String {
        if amount <= 0 { return "$0" }
        if amount < 1   { return String(format: "$%.2f", amount) }
        if amount < 10  { return String(format: "$%.1f", amount) }
        return String(format: "$%.0f", amount)
    }
}

private struct PerModelCostFooter: View {
    /// All rows (not just the displayed top-N) so the total stays honest
    /// when a 4th+ model contributed real dollars in the window.
    let allRows: [ModelUsageRow]
    let displayedCount: Int

    var body: some View {
        let total = allRows.reduce(0.0) { $0 + $1.dollars }
        // Label adapts: "total · 5h" when every model is on screen,
        // "all 5 · 5h" when the displayed top-N is hiding rows, so the
        // user knows the figure isn't just the visible rows summed.
        let label = allRows.count > displayedCount
            ? "all \(allRows.count)"
            : "total"
        HStack(spacing: 6) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(formatTotal(total))
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.78))
            Text("· last 5h")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.32))
            Spacer(minLength: 0)
        }
    }

    private func formatTotal(_ amount: Double) -> String {
        if amount <= 0 { return "$0" }
        if amount < 10  { return String(format: "$%.2f", amount) }
        return String(format: "$%.0f", amount)
    }
}

// MARK: - Both-providers-hidden empty state

/// Shown on usage and cost pages when the user has toggled both providers
/// off in Settings. Reads as "intentionally quiet" rather than "broken
/// page", and points the user back at the affordance that got them here.
struct BothHiddenPlaceholder: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("Both providers hidden")
                .font(Typography.providerTitle)
                .foregroundStyle(.white.opacity(0.45))
            Text("Re-enable in Settings → Providers")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.32))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
