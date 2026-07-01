import SwiftUI
import AppKit

/// Hairline divider + chip + cmd-click hint + page indicator + live-status
/// group. Lives outside `PagedContent` so it stays fixed while the data
/// area swipes between pages.
///
/// Two things change with the active screen:
///   1. The chip — shows the current chart-style label on the usage page
///      (since cmd-click cycles styles there), the current cost mode on
///      the cost page, and a static year label on the overview page.
///   2. The live-status group — reflects whichever store powers the
///      currently visible page (UsageStore on usage, CostStore on cost
///      and overview), so "syncing…" / "synced 5s ago" describes the
///      data the user sees.
struct PanelFooter: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var costPref = CostStylePref.shared
    @ObservedObject private var screenPref = ScreenPref.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var costStore = CostStore.shared
    @State private var liveStatusHovered = false

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white.opacity(0.06), .white.opacity(0.06), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)
            .opacity(screenPref.screen == .overview ? 0 : 1)

            ZStack(alignment: .center) {
                HStack(spacing: 10) {
                    chip

                    if !activeStyleCycled {
                        HStack(spacing: 5) {
                            Image(systemName: "command")
                                .font(Typography.micro)
                            Text(L10n.tr("click to cycle"))
                                .font(Typography.label)
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(cycleHintAccessibilityLabel)
                    }

                    Spacer()

                    if screenPref.screen == .usage {
                        CodexResetStatus()
                    }

                    liveStatus
                }

                // Centered horizontally over the row regardless of how
                // wide the chip + tip on the left or the live-status on
                // the right grow. Independent of those widths so the dots
                // sit at true bottom-center of the panel.
                PageIndicator(model: model)
            }
            .frame(height: 24, alignment: .center)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .animation(.strongEaseOut, value: pref.hasCycledStyle)
            .animation(.strongEaseOut, value: costPref.hasCycledStyle)
            .animation(.strongEaseOut, value: screenPref.screen)
        }
    }

    private var activeStyleCycled: Bool {
        switch screenPref.screen {
        case .usage: return pref.hasCycledStyle
        case .cost:  return costPref.hasCycledStyle
        case .overview: return true
        }
    }

    private var cycleHintAccessibilityLabel: String {
        switch screenPref.screen {
        case .overview: return L10n.tr("Overview shows %@ usage history", currentYearString)
        case .usage, .cost: return L10n.tr("Tip: Command-click to cycle visualization")
        }
    }

    @ViewBuilder
    private var chip: some View {
        let label: String = {
            switch screenPref.screen {
            case .usage: return pref.style.label.uppercased()
            case .cost:  return costPref.style.label
            case .overview: return currentYearString
            }
        }()
        Text(label)
            .font(Typography.chip)
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .contentTransition(.opacity)
            .animation(.strongEaseOut, value: pref.style)
            .animation(.strongEaseOut, value: costPref.style)
            .animation(.strongEaseOut, value: screenPref.screen)
    }

    private var activeLoading: Bool {
        switch screenPref.screen {
        case .usage: return usageStore.loading
        case .cost, .overview: return costStore.loading
        }
    }

    private var activeLastUpdated: Date? {
        switch screenPref.screen {
        case .usage: return usageStore.lastUpdated
        case .cost, .overview: return costStore.lastUpdated
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        // Click anywhere on the group → trigger a refetch of whichever
        // store powers the active page. Existing `if loading` guards inside
        // each store's refresh() prevent click-spam from stacking fetches.
        Button(action: triggerRefresh) {
            HStack(spacing: 6) {
                LiveDot(active: activeLastUpdated != nil && !activeLoading)
                if activeLoading {
                    Text(L10n.tr("Syncing…"))
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(0.55))
                } else if let updated = activeLastUpdated {
                    Text(L10n.tr("Synced"))
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(liveStatusHovered ? 0.85 : 0.55))
                    Text(relative(updated))
                        .font(Typography.bodyNumber)
                        .foregroundStyle(.white.opacity(liveStatusHovered ? 0.95 : 0.72))
                } else {
                    Text(L10n.tr("Idle"))
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(liveStatusHovered ? 0.7 : 0.4))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(liveStatusHovered && !activeLoading ? 0.05 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(activeLoading)
        .onHover { h in
            liveStatusHovered = h
            if h && !activeLoading {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(L10n.tr("Refresh now"))
        .animation(.easeOut(duration: 0.12), value: liveStatusHovered)
        .animation(.easeOut(duration: 0.12), value: activeLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(liveStatusSpoken)
        .accessibilityHint(L10n.tr("Click to refresh now"))
        .accessibilityAddTraits(.isButton)
    }

    private func triggerRefresh() {
        switch screenPref.screen {
        case .usage: usageStore.refresh()
        case .cost, .overview: costStore.refresh()
        }
    }

    private var liveStatusSpoken: String {
        if activeLoading { return L10n.tr("Syncing") }
        if let updated = activeLastUpdated { return L10n.tr("Synced %@", relative(updated)) }
        return L10n.tr("Idle")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = L10n.locale
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relative(_ d: Date) -> String {
        Self.relativeFormatter.localizedString(for: d, relativeTo: Date())
    }

    private var currentYearString: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)"
    }
}
