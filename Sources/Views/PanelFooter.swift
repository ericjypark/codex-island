import SwiftUI

/// Hairline divider + chip + cmd-click hint + page indicator + live-status
/// group. Lives outside `PagedContent` so it stays fixed while the data
/// area swipes between pages.
///
/// Two things change with the active screen:
///   1. The chip — shows the current chart-style label on the usage page
///      (since cmd-click cycles styles there) and a static "USD" on the
///      cost page (cost bars don't cycle).
///   2. The live-status group — reflects whichever store powers the
///      currently visible page (UsageStore on usage, CostStore on cost),
///      so "syncing…" / "synced 5s ago" describes the data the user sees.
struct PanelFooter: View {
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var costPref = CostStylePref.shared
    @ObservedObject private var screenPref = ScreenPref.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var costStore = CostStore.shared

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white.opacity(0.06), .white.opacity(0.06), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)

            HStack(spacing: 10) {
                chip

                if !activeStyleCycled {
                    HStack(spacing: 5) {
                        Image(systemName: "command")
                            .font(Typography.micro)
                        Text("click to cycle")
                            .font(Typography.label)
                    }
                    .foregroundStyle(.white.opacity(0.42))
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                }

                Spacer()

                PageIndicator(active: screenPref.screen)

                liveStatus
            }
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
        }
    }

    @ViewBuilder
    private var chip: some View {
        let label: String = {
            switch screenPref.screen {
            case .usage: return pref.style.label.uppercased()
            case .cost:  return costPref.style.label
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
        case .cost:  return costStore.loading
        }
    }

    private var activeLastUpdated: Date? {
        switch screenPref.screen {
        case .usage: return usageStore.lastUpdated
        case .cost:  return costStore.lastUpdated
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        HStack(spacing: 6) {
            LiveDot(active: activeLastUpdated != nil && !activeLoading)
            if activeLoading {
                Text("syncing…")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.55))
            } else if let updated = activeLastUpdated {
                Text("synced")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.55))
                Text(relative(updated))
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Text("idle")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
