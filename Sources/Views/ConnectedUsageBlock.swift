import SwiftUI

struct ConnectedUsageBlock: View {
    let provider: IslandProvider
    @ObservedObject private var connections = ProviderConnectionStore.shared
    @ObservedObject private var preferences = ProviderQuotaPreferences.shared
    @ObservedObject private var style = StylePref.shared

    var body: some View {
        let snapshot = connections.snapshot(provider)
        let limits = connections.limits(provider)
        Group {
            if !snapshot.needsLogin && limits.contains(where: { $0.usedFraction != nil }) {
                UsageChartsRow(color: provider.color, style: style.style, seed: provider == .grok ? 5 : 7,
                    metrics: limits.map { limit in
                        UsageChartMetric(id: limit.id, label: limit.label, window: limit.window,
                                         historyKey: snapshot.historyKey(provider: provider, limit: limit))
                    })
                    .help(limits.first?.groupLabel ?? provider.name)
            } else {
                ProviderUsageEmptyState(provider: provider, snapshot: snapshot,
                                        loading: connections.loading.contains(provider))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, IslandPanelLayout.columnInset)
    }
}

struct ProviderUsageEmptyState: View {
    let provider: IslandProvider
    let snapshot: ConnectedUsage
    var loading = false

    var body: some View {
        VStack(spacing: 5) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: snapshot.hasNoActiveSubscription ? "creditcard" : "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(provider.color.opacity(0.85))
                    .accessibilityHidden(true)
            }
            Text(L10n.tr(snapshot.hasNoActiveSubscription ? "No active subscription"
                : snapshot.needsLogin ? "Connect your account" : "Usage unavailable"))
                .font(Typography.rowTitle).foregroundStyle(.white.opacity(0.85))
            Text(L10n.tr(snapshot.hasNoActiveSubscription
                ? "Connect a subscribed account or choose another provider."
                : snapshot.needsLogin ? "Sign in to see your usage limits."
                : "This provider hasn't reported usage limits."))
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.tr("Open provider settings")) {
                UserDefaults.standard.set("providers", forKey: "Settings.activeTab")
                SettingsWindowController.shared.show()
            }
            .font(Typography.label)
            .foregroundStyle(.white.opacity(0.8))
            .buttonStyle(PressableButtonStyle(scale: 0.97))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct ProviderDataUnavailable: View {
    let message: String
    var body: some View {
        Text(L10n.tr(message))
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.horizontal, IslandPanelLayout.columnInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
