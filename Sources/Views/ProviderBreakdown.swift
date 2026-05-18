import SwiftUI

// MARK: - Per-model breakdown
//
// Shown in the half of the panel freed when one provider is toggled off in
// Settings → Providers. Powered by `CostStore`'s `recentByModel` (5h slice)
// and `weekByModel` (7d slice) — the same data the live tiles already
// summarize, so no extra fetch.
//
// One unified `PerModelBreakdown(provider:, metric:)` struct handles both
// the usage page (tokens) and the cost page (dollars). The row layout is
// identical between metrics so a metric swap (cost-page Cmd-click into
// TOKENS style) doesn't reflow the column.
//
// Each row's bar carries TWO meanings via overlapping fills on a single
// track. The bar is normalized PER ROW so the model's own week absolute
// fills the full track, and the 5h fill is a sub-portion of that:
//   - Background, dim brand color: always the full track (= the model's
//     own week activity).
//   - Foreground, bright brand color: `recentAbsolute / weekAbsolute`
//     of the track (= the fraction of the model's week that fell in the
//     last 5h). Always ≤ the dim fill.
// A model heavily used today but only marginally over the week reads as
// a near-full bright bar over a full dim bar (most of the model's week
// is happening now). A model that was used earlier this week but quiet
// now reads as just a dim bar (no bright). A new model used only in
// the last 5h reads as nearly full bright over full dim (5h IS this
// model's whole week).
//
// Cross-row scale is intentionally dropped from the bar (so the heavy
// hitter doesn't pin everyone else to a single pixel) and shown via the
// trailing column's WEEK absolute (tokens or $).
//
// Both intentionally do NOT respect `StylePref.style` (chart-style cycling)
// — the breakdown is a different vocabulary (table, not gauge) and the
// footer chip already communicates which style the live tiles are using.

/// Visual weights mapped by row index — top model dominates, lesser models
/// recede. Independent of fill length so a tiny-but-active row still reads
/// as "live" rather than as a dead row.
private let perModelRowWeights: [Double] = [0.85, 0.55, 0.40, 0.30]

/// Multiplier applied to the weight for the dim (week) fill so it sits
/// behind the bright (5h) fill on the same track. Surfaced as a constant
/// so the legend swatch and the bar fill stay locked together — drift
/// between them is the kind of "looks slightly off" bug visual QA flags
/// last and the implementor sees never.
private let dimFillMultiplier: Double = 0.30

/// Maximum rows shown. Four rows fit comfortably in a ~90pt-tall column
/// alongside one header line at 11pt label / 10pt caption typography.
private let perModelRowLimit = 4

// MARK: - Provider helpers

private func providerBrandColor(_ provider: AlertEngine.Provider) -> Color {
    switch provider {
    case .claude: return IslandColor.claude
    case .codex:  return IslandColor.codex
    }
}

private func providerLowerLabel(_ provider: AlertEngine.Provider) -> String {
    switch provider {
    case .claude: return "Claude"
    case .codex:  return "Codex"
    }
}

@MainActor
private func recentRows(for provider: AlertEngine.Provider, store: CostStore) -> [ModelUsageRow] {
    switch provider {
    case .claude: return store.claude.recentByModel
    case .codex:  return store.codex.recentByModel
    }
}

@MainActor
private func weekRowsList(for provider: AlertEngine.Provider, store: CostStore) -> [ModelUsageRow] {
    switch provider {
    case .claude: return store.claude.weekByModel
    case .codex:  return store.codex.weekByModel
    }
}

// MARK: - Joined row (one model, two windows)

/// One model's data across both windows. `recent` is `nil` when the model
/// had no 5h activity (only week activity); `week` is always non-nil
/// because `weekByModel` is the superset (5h ⊂ wk).
private struct JoinedModelRow {
    let model: String
    let displayName: String
    let recent: ModelUsageRow?
    let week: ModelUsageRow

    /// Absolute (tokens or $) for the chosen metric. The bar uses the
    /// model's own week absolute as its full-track denominator, so 5h
    /// renders as a sub-portion of the week — never longer. Switching
    /// from %-within-window to absolute values is what guarantees the
    /// inclusion property visually (5h is strictly inside week).
    func recentAbsolute(metric: PerModelBreakdown.Metric) -> Double {
        guard let recent else { return 0 }
        switch metric {
        case .tokens:  return Double(recent.tokens)
        case .dollars: return recent.dollars
        }
    }

    func weekAbsolute(metric: PerModelBreakdown.Metric) -> Double {
        switch metric {
        case .tokens:  return Double(week.tokens)
        case .dollars: return week.dollars
        }
    }

    /// Trailing-column figure. Always the WEEK absolute — the bar already
    /// conveys 5h-vs-wk ratio within the row, so the trailing column adds
    /// cross-row scale (which the per-row bar normalization deliberately
    /// drops).
    func trailingValue(metric: PerModelBreakdown.Metric) -> String {
        switch metric {
        case .tokens:  return Self.formatTokens(week.tokens)
        case .dollars: return Self.formatDollars(week.dollars)
        }
    }

    private static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return "\(n / 1_000)K" }
        return "\(n)"
    }

    /// Adaptive precision: under $1 shows two decimals; under $10 shows
    /// one decimal; otherwise round to the nearest dollar.
    private static func formatDollars(_ amount: Double) -> String {
        if amount <= 0 { return "$0" }
        if amount < 1   { return String(format: "$%.2f", amount) }
        if amount < 10  { return String(format: "$%.1f", amount) }
        return String(format: "$%.0f", amount)
    }
}

@MainActor
private func joinedRows(for provider: AlertEngine.Provider, store: CostStore) -> [JoinedModelRow] {
    let week = weekRowsList(for: provider, store: store)
    let recent = recentRows(for: provider, store: store)
    let recentMap = Dictionary(uniqueKeysWithValues: recent.map { ($0.model, $0) })
    return week.map { w in
        JoinedModelRow(
            model: w.model,
            displayName: w.displayName,
            recent: recentMap[w.model],
            week: w
        )
    }
}

// MARK: - The single breakdown

struct PerModelBreakdown: View {
    enum Metric { case tokens, dollars }

    let provider: AlertEngine.Provider
    let metric: Metric

    @ObservedObject private var costStore = CostStore.shared

    private var color: Color { providerBrandColor(provider) }

    /// Joined rows, sorted by the chosen metric within the week window
    /// (week is the bigger sample so it's the more stable rank), trimmed
    /// to the display limit. The `weekByModel` upstream is already
    /// token-sorted so .tokens metric needs no resort; dollars metric
    /// re-sorts by week-dollar.
    private var rows: [JoinedModelRow] {
        let joined = joinedRows(for: provider, store: costStore)
        let sorted: [JoinedModelRow] = {
            switch metric {
            case .tokens:
                return joined  // already sorted by week tokens desc
            case .dollars:
                return joined.sorted { $0.week.dollars > $1.week.dollars }
            }
        }()
        return Array(sorted.prefix(perModelRowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if rows.isEmpty {
                Spacer(minLength: 0)
                Text(L10n.tr("no %@ activity in last 5h or this week", providerLowerLabel(provider)))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.element.model) { idx, row in
                        PerModelRow(
                            displayName: row.displayName,
                            recentAbsolute: row.recentAbsolute(metric: metric),
                            weekAbsolute: row.weekAbsolute(metric: metric),
                            trailingValue: row.trailingValue(metric: metric),
                            color: color,
                            weight: perModelRowWeights[min(idx, perModelRowWeights.count - 1)]
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Header: title + tiny legend. The legend is the load-bearing UI
    /// element here — it's how the user learns that the bright section
    /// of each bar is "5h" and the dim section is "week". Without it the
    /// dual-fill bars are a riddle. Swatch opacities are computed against
    /// the top-row weight (0.85) and the shared dim multiplier so the
    /// legend reads exactly like the top row's bar — no drift.
    private var header: some View {
        let topWeight = perModelRowWeights[0]
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.tr("BY MODEL"))
                .font(Typography.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Capsule()
                    .fill(color.opacity(topWeight))
                    .frame(width: 8, height: 4)
                Text(L10n.tr("5h"))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.trailing, 4)
                Capsule()
                    .fill(color.opacity(topWeight * dimFillMultiplier))
                    .frame(width: 8, height: 4)
                Text(L10n.tr("week"))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.50))
            }
        }
    }
}

// MARK: - Row + overlapping bar

private struct PerModelRow: View {
    let displayName: String
    /// Absolute (tokens or $) for the model in the last 5h. Always ≤
    /// `weekAbsolute`. Drives the bright fill length within this row.
    let recentAbsolute: Double
    /// Absolute (tokens or $) for the model over the rolling 7d window.
    /// Defines the row's full track width — bar is normalized per row so
    /// the dim fill always covers the entire track and the bright fill
    /// is a strict sub-portion.
    let weekAbsolute: Double
    /// Pre-formatted week-absolute (e.g. "12K", "$24.50").
    let trailingValue: String
    let color: Color
    let weight: Double

    /// Fixed column widths — keep digits from dancing as polling delivers
    /// new values. `nameWidth` sized for the longest realistic display
    /// name in either provider's catalog (`o4-mini-high` at 11pt medium
    /// ≈ 70pt); 84pt buys a small safety margin without starving the bar.
    /// `trailingWidth` sized for "$24.50" / "1.5M" worst case.
    private static let nameWidth: CGFloat = 84
    private static let trailingWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: Self.nameWidth, alignment: .leading)
                .lineLimit(1)

            OverlapBar(
                recentAbsolute: recentAbsolute,
                weekAbsolute: weekAbsolute,
                color: color,
                weight: weight
            )

            Text(trailingValue)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(weekAbsolute > 0 ? 0.55 : 0.32))
                .frame(width: Self.trailingWidth, alignment: .trailing)
        }
    }
}

/// Single-track bar with TWO overlapping fills, normalized PER ROW. The
/// model's own week absolute defines the full track width, so:
///   - Dim fill (week)      = full track width whenever the model had
///                            any week activity (the "100% of this
///                            model's week" baseline).
///   - Bright fill (5h)     = `recentAbsolute / weekAbsolute` of the
///                            track. Always ≤ the dim fill because
///                            `recent ≤ week` (5h is a strict subset of
///                            the rolling 7-day window).
///
/// Drawing order matters: track → week (dim, behind) → 5h (bright, on
/// top). When 5h is small, the dim bar peeks out behind the bright tip
/// and trails to the right edge. When the model has only week activity
/// (no 5h), only the dim bar shows.
///
/// Per-row normalization deliberately drops cross-row scale; the heavy
/// hitter doesn't pin everyone else to a single pixel, and the trailing
/// column carries the absolute scale (4.1M vs 27K vs 184) so the user
/// can still compare across rows.
private struct OverlapBar: View {
    let recentAbsolute: Double
    let weekAbsolute: Double
    let color: Color
    /// Modulates both fill opacities so the top model dominates and
    /// lesser rows recede. Independent of value so a tiny-but-active
    /// row still reads as "live".
    let weight: Double

    /// Slim track (5pt) — keeps the row line height to ~14pt so 4 rows
    /// fit vertically alongside the header in ~90pt.
    private static let barHeight: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Row-local fraction: 5h as a portion of THIS model's week.
            // Clamp to [0, 1]; in practice recent ≤ week always, but
            // float division makes the explicit clamp cheap insurance.
            let recentFrac: CGFloat = weekAbsolute > 0
                ? CGFloat(min(1.0, max(0.0, recentAbsolute / weekAbsolute)))
                : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.06))
                    .frame(height: Self.barHeight)
                if weekAbsolute > 0 {
                    // Floor the dim opacity so the 4th-row track baseline
                    // stays visible — without this, row 3's weight 0.30
                    // would render the dim fill at 0.09 opacity, below the
                    // perceptual threshold against the panel black. The
                    // 0.15 floor keeps the week-baseline readable at every
                    // row index without making the top-row bars feel any
                    // less dominant (top row = weight 0.85 → 0.255, well
                    // above the floor).
                    let dimOpacity = max(weight * dimFillMultiplier, 0.15)
                    Capsule()
                        .fill(color.opacity(dimOpacity))
                        .frame(width: w, height: Self.barHeight)
                }
                if recentFrac > 0 {
                    Capsule()
                        .fill(color.opacity(weight))
                        .frame(
                            width: max(2, w * recentFrac),
                            height: Self.barHeight
                        )
                        .animation(.strongEaseOut, value: recentFrac)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
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
            Text(L10n.tr("Both providers hidden"))
                .font(Typography.providerTitle)
                .foregroundStyle(.white.opacity(0.45))
            Text(L10n.tr("Re-enable in Settings → Providers"))
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.32))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
