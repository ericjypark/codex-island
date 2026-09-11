import SwiftUI

struct ProviderSelectionView: View {
    @ObservedObject private var selection = ProviderVisibilityStore.shared
    @ObservedObject private var connections = ProviderConnectionStore.shared
    @ObservedObject private var usage = UsageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("On your island")).font(.system(size: 15, weight: .semibold))
                Text(L10n.tr("Choose up to two providers."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 10) {
                slot(0, provider: selection.left)
                Button {
                    withAnimation(reduceMotion ? nil : .openMorph) { selection.swap() }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(selection.right == nil)
                .opacity(selection.right == nil ? 0.3 : 1)
                .help(L10n.tr("Swap left and right"))
                .accessibilityLabel(L10n.tr("Swap left and right"))
                slot(1, provider: selection.right)
            }
            Divider().overlay(.white.opacity(0.08))
            ForEach(selection.selected) { provider in
                connectionRow(provider)
            }
        }
        .padding(24)
        .task { connections.refreshSelected() }
    }

    private func slot(_ index: Int, provider: IslandProvider?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr(index == 0 ? "Left" : "Right"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 8) {
                if let provider { ProviderMark(provider: provider) }
                else { Image(systemName: "plus").frame(width: 20, height: 20) }
                Menu {
                    ForEach(IslandProvider.allCases) { candidate in
                        Button {
                            withAnimation(reduceMotion ? nil : .openMorph) { selection.set(candidate, at: index) }
                        } label: {
                            if candidate == provider { Label(candidate.name, systemImage: "checkmark") }
                            else { Text(candidate.name) }
                        }
                        .disabled(index == 1 && selection.right == nil && candidate == selection.left)
                    }
                    if index == 1 {
                        Divider()
                        Button(L10n.tr("None — use one provider")) {
                            withAnimation(reduceMotion ? nil : .openMorph) { selection.set(nil, at: 1) }
                        }
                    }
                } label: {
                    Text(provider?.name ?? L10n.tr("Add provider"))
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(L10n.tr(index == 0 ? "Left provider" : "Right provider"))
                .accessibilityValue(provider?.name ?? L10n.tr("None"))
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func connectionRow(_ provider: IslandProvider) -> some View {
        if provider.usesLegacyUsage {
            let value = provider == .claude ? usage.claude : usage.codex
            VStack(alignment: .leading, spacing: 8) {
                ProviderAccountHeading(provider: provider, plan: value.plan)
                if let error = [value.fiveHour.error, value.weekly.error]
                    .compactMap({ $0 }).first(where: { $0 != "no data" }) {
                    VStack(alignment: .leading, spacing: 8) {
                        if provider == .claude, ClaudeCredentials.isReauthActionable(error) {
                            Label(L10n.tr("Sign-in required"), systemImage: "info.circle")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            if ClaudeCredentials.canPromptReauth() {
                                ReauthButton(title: "Sign in with Claude")
                            } else {
                                Text(L10n.tr("Open Claude Code and run /login."))
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text(L10n.tr(error))
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
                }
            }
        } else {
            ProviderConnectionSection(provider: provider, snapshot: connections.snapshot(provider),
                loading: connections.loading.contains(provider),
                connect: { connections.connect(provider) },
                refresh: { connections.refresh(provider, manually: true) })
        }
    }
}

private struct ProviderAccountHeading: View {
    let provider: IslandProvider
    let plan: String?

    var body: some View {
        HStack(spacing: 8) {
            ProviderMark(provider: provider)
            Text(provider.name).font(.system(size: 13, weight: .semibold))
            if let plan = provider.planDisplayName(plan) {
                Text(plan)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    .lineLimit(1).help(plan)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ProviderConnectionSection: View {
    let provider: IslandProvider
    let snapshot: ConnectedUsage
    let loading: Bool
    let connect: () -> Void
    let refresh: () -> Void

    private var signedIn: Bool { !snapshot.needsLogin && snapshot.updatedAt != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ProviderAccountHeading(provider: provider, plan: snapshot.plan)
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(L10n.tr("Checking connection"))
                } else {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("Refresh connection"))
                    .accessibilityLabel(L10n.tr("Refresh %@ connection", provider.name))
                }
                if signedIn {
                    Menu {
                        Button(L10n.tr(provider == .grok ? "Sign in again…" : "Open agy CLI"), action: connect)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 20, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(L10n.tr("%@ account options", provider.name))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.tr(loading ? "Checking connection" : signedIn ? "Signed in"
                    : snapshot.needsLogin ? "Sign-in required" : "Connection unavailable"),
                    systemImage: signedIn ? "checkmark.circle" : "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                if !loading {
                    if signedIn, snapshot.primary == nil {
                        Text(L10n.tr(provider == .grok ? "Credit usage unavailable" : "Usage unavailable"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    } else if let message = snapshot.message {
                        Text(L10n.tr(message))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if snapshot.needsLogin {
                        Button(L10n.tr(provider == .grok ? "Sign in with Grok CLI" : "Open agy CLI"), action: connect)
                            .controlSize(.small)
                    }
                }
                if !snapshot.limits.isEmpty {
                    ProviderMetricSelection(provider: provider, usage: snapshot)
                }
            }
            .padding(.leading, 28)
        }
    }
}

private struct ProviderMetricSelection: View {
    let provider: IslandProvider
    let usage: ConnectedUsage
    @ObservedObject private var preferences = ProviderQuotaPreferences.shared
    @State private var isExpanded = false

    private var scope: String { usage.storageScope(provider: provider) }
    private var selection: QuotaSelection { preferences.selection(for: scope) }
    private var displayed: [ConnectedLimit] { ProviderQuotaPreferences.resolve(usage, selection: selection) }
    private var groupIDs: [String] { Array(Set(usage.limits.map(\.groupID))).sorted() }
    private var candidates: [ConnectedLimit] {
        let group = selection.groupID ?? displayed.first?.groupID
        return usage.limits.filter { $0.groupID == group }
    }

    var body: some View {
        if usage.limits.count > 1 || selection != QuotaSelection() {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        Text(L10n.tr("Usage display"))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                if isExpanded {
                    controls.padding(.top, 8)
                }
            }
            .font(.system(size: 12))
            .tint(.white.opacity(0.65))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selection != QuotaSelection() {
                HStack {
                    Spacer()
                    Button(L10n.tr("Use defaults")) { preferences.save(QuotaSelection(), for: scope) }
                }
            }
            if groupIDs.count > 1 {
                Picker(L10n.tr("Model group"), selection: Binding(
                    get: { selection.groupID ?? displayed.first?.groupID ?? "" },
                    set: { preferences.save(QuotaSelection(groupID: $0), for: scope) }
                )) {
                    ForEach(groupIDs, id: \.self) { id in
                        Text(usage.limits.first { $0.groupID == id }?.groupLabel ?? id).tag(id)
                    }
                }
            } else if let group = displayed.first?.groupLabel {
                Text(group).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
            if candidates.count > 1 {
                metricPicker(index: 0)
                metricPicker(index: 1)
                if displayed.count > 1 {
                    Picker(L10n.tr("Peek and alerts"), selection: Binding(
                        get: { selection.primaryID ?? displayed.first?.id ?? "" },
                        set: { var next = selection; next.primaryID = $0; preferences.save(next, for: scope) }
                    )) {
                        ForEach(displayed) { Text(L10n.tr($0.label)).tag($0.id) }
                    }
                }
            } else {
                Text(displayed.map { L10n.tr($0.label) }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
            if displayed.isEmpty {
                Text(L10n.tr("Selected metric is unavailable. Use defaults to choose an available metric."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
            }
        }
        .controlSize(.small)
    }

    private func metricPicker(index: Int) -> some View {
        Picker(L10n.tr(index == 0 ? "First metric" : "Second metric"), selection: Binding(
            get: { displayed.indices.contains(index) ? displayed[index].id : "" },
            set: { id in
                var next = selection
                var ids = displayed.map(\.id)
                if id.isEmpty {
                    if ids.indices.contains(index) { ids.remove(at: index) }
                } else if let other = ids.firstIndex(of: id), other != index {
                    if ids.indices.contains(index) { ids.swapAt(index, other) }
                } else if ids.indices.contains(index) { ids[index] = id }
                else { ids.append(id) }
                next.metricIDs = ids
                if let primary = next.primaryID, !ids.contains(primary) { next.primaryID = nil }
                preferences.save(next, for: scope)
            }
        )) {
            ForEach(candidates) { Text(L10n.tr($0.label)).tag($0.id) }
            if index == 1 { Text(L10n.tr("None")).tag("") }
        }
    }
}
