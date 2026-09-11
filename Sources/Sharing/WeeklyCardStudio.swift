import AppKit
import SwiftUI

struct WeeklyCardStudio: View {
    @ObservedObject private var store = CostStore.shared
    @StateObject private var history = WeeklyCardHistoryStore()
    @AppStorage("WeeklyCard.format") private var formatRaw = WeeklyCardFormat.feed.rawValue
    @AppStorage("WeeklyCard.metric") private var metricRaw = WeeklyCardMetric.apiValue.rawValue
    @State private var period = WeeklyCardPeriod.lastSevenDays
    @State private var included = Set(IslandProvider.allCases)
    @State private var signature = ""
    @State private var now = Date()
    @State private var exporting = false
    @State private var status: String?
    @State private var exportError: String?
    @State private var showingCardDetails = false
    @State private var actualSize = false

    private let surface = Color(red: 0.020, green: 0.020, blue: 0.027)
    private let canvas = Color(red: 0.065, green: 0.067, blue: 0.080)
    private var tier: WeeklyCardTier { snapshot.tier(for: metric) }
    private var format: WeeklyCardFormat { WeeklyCardFormat(rawValue: formatRaw) ?? .feed }
    private var metric: WeeklyCardMetric { WeeklyCardMetric(rawValue: metricRaw) ?? .apiValue }
    private var usesFullHistory: Bool {
        !AppEnvironment.isDemo && period.needsExtendedHistory(now: now, calendar: .current)
    }
    private var isLoading: Bool { usesFullHistory ? history.isLoading || history.buckets == nil : store.loading }
    private var historySaveError: String? {
        let errors = usesFullHistory ? history.saveErrors : store.historySaveErrors
        return IslandProvider.allCases.filter { included.contains($0) }.compactMap { errors[$0] }.first
    }
    private var snapshot: WeeklyUsageSnapshot {
        WeeklyUsageSnapshot.make(
            buckets: usesFullHistory ? history.buckets ?? [:] : Dictionary(uniqueKeysWithValues: IslandProvider.allCases.map {
                ($0, store.cost(for: $0).dailyTokens)
            }), included: included, period: period, now: now,
            isDemo: AppEnvironment.isDemo,
            hasPartialRecords: usesFullHistory ? !included.isDisjoint(with: history.partialProviders)
                : included.contains { store.localNotices[$0]?.hasPrefix("Some") == true }
        )
    }
    private var canExport: Bool {
        !isLoading && !exporting && snapshot.totalTokens > 0
            && (metric == .tokens || snapshot.hasPricedUsage)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            HStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvas)
                Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    essentialControls.padding(.bottom, 20)
                    rule
                    ScrollView {
                        controls.padding(.vertical, 20)
                    }
                    rule
                    exportActions.padding(.top, 16)
                }
                .padding(20)
                .frame(width: 280)
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(surface)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: signature) { value in
            signature = String(value.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(32))
            status = nil
        }
        .onChange(of: formatRaw) { _ in status = nil }
        .onChange(of: metricRaw) { _ in status = nil }
        .onChange(of: period) { _ in
            status = nil
            if usesFullHistory { history.loadIfNeeded() }
        }
        .onChange(of: included) { _ in status = nil }
        .onChange(of: store.lastUpdated) { _ in
            now = Date()
            status = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexIslandUsageHistoryRecovered)) { _ in
            status = nil
            if usesFullHistory { history.refresh() }
        }
        .alert(L10n.tr("Could not export card"), isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button(L10n.tr("OK"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var rule: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.tr("Usage card"))
                .font(Typography.rowTitle)
                .foregroundStyle(.white.opacity(0.90))
            Spacer()
            Button { refresh() } label: {
                Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
            }
            .disabled(isLoading || exporting)
            .help(L10n.tr("Refresh records"))
            .accessibilityLabel(L10n.tr("Refresh records"))
            Button { showingCardDetails.toggle() } label: {
                Image(systemName: "info.circle").frame(width: 28, height: 28)
            }
            .help(L10n.tr("About this card"))
            .accessibilityLabel(L10n.tr("About this card"))
            .popover(isPresented: $showingCardDetails, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("About this card")).font(Typography.providerTitle)
                    Text(L10n.tr("API value estimates your usage at API rates in USD, not your subscription bill. Tokens include cache reads and writes."))
                    Text(L10n.tr("The card includes daily usage, provider totals, active days, and your signature. It does not include prompts or conversations."))
                    Text(L10n.tr("Last 7 days includes today and the previous six days. Month and year also run through today. All time includes all saved usage records on this Mac."))
                    Text(L10n.tr("Captured token counts are saved on this Mac even if provider logs are removed. Records deleted before capture may still be missing."))
                }
                .font(Typography.tabLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .frame(width: 300)
            }
        }
        .font(Typography.tabLabel)
        .foregroundStyle(.white.opacity(0.65))
        .buttonStyle(.borderless)
        .padding(.leading, 96)
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if isLoading {
                    placeholder(icon: "", title: "Gathering your usage…",
                                detail: "Reading usage records on this Mac.", loading: true)
                } else if snapshot.totalTokens == 0 {
                    placeholder(icon: "chart.bar.xaxis", title: "A fresh page for your usage.",
                                detail: "No recorded tokens in this period. Try another period or include more providers.")
                } else if metric == .apiValue && !snapshot.hasPricedUsage {
                    placeholder(icon: "dollarsign.circle", title: "Your tokens need a price.",
                                detail: "Refresh records to load API prices, or switch the spotlight to tokens.")
                } else if actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        card.padding(24)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                } else {
                    let available = CGSize(width: max(1, geometry.size.width - 48),
                                           height: max(1, geometry.size.height - 48))
                    let scale = min(available.width / format.size.width,
                                    available.height / format.size.height)
                    card
                        .scaleEffect(scale)
                        .frame(width: format.size.width * scale, height: format.size.height * scale)
                        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            HStack(spacing: 8) {
                Text(format.pixelLabel).font(Typography.caption)
                Spacer()
                Button { actualSize.toggle() } label: {
                    Label(L10n.tr(actualSize ? "Fit" : "Actual size"),
                          systemImage: actualSize ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .font(Typography.label)
                .disabled(snapshot.totalTokens == 0 || isLoading)
            }
            .foregroundStyle(.white.opacity(0.60))
            .padding(.horizontal, 24)
            .frame(height: 40)
        }
    }

    private var card: some View {
        WeeklyUsageCard(snapshot: snapshot, format: format, signature: signature, metric: metric)
    }

    private func placeholder(icon: String, title: String, detail: String, loading: Bool = false) -> some View {
        VStack(spacing: 14) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.tr(title)).font(.system(size: 20, weight: .medium))
            Text(L10n.tr(detail))
                .font(Typography.tabLabel)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            if !loading {
                Button(L10n.tr("Refresh records")) { refresh() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var essentialControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                controlLabel("Spotlight")
                SegmentedControl(
                    items: WeeklyCardMetric.allCases.map(\.rawValue),
                    selected: $metricRaw,
                    label: { WeeklyCardMetric(rawValue: $0)?.title ?? $0 },
                    accessibilityPrefix: "Spotlight",
                    labelFont: Typography.tabLabel
                )
            }
            HStack {
                controlLabel("Period")
                Spacer()
                Picker(L10n.tr("Period"), selection: $period) {
                    ForEach(WeeklyCardPeriod.allCases) { option in
                        Text(L10n.tr(option.title)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .controlSize(.regular)
        .disabled(exporting)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                controlLabel("Format")
                Spacer()
                Picker(L10n.tr("Format"), selection: $formatRaw) {
                    ForEach(WeeklyCardFormat.allCases) { option in
                        Text(L10n.tr(option.title)).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                controlLabel("Signature")
                TextField(L10n.tr("Name or @handle (optional)"), text: $signature)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.tabLabel)
                    .accessibilityLabel(L10n.tr("Name or handle on card"))
            }
            VStack(alignment: .leading, spacing: 12) {
                controlLabel("Providers")
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                    ForEach(IslandProvider.allCases) { provider in
                        Toggle(isOn: Binding(
                            get: { included.contains(provider) },
                            set: { if $0 { included.insert(provider) } else { included.remove(provider) } }
                        )) {
                            HStack(spacing: 5) {
                                Circle().fill(provider.color).frame(width: 5, height: 5)
                                Text(provider.name).font(Typography.tabLabel)
                            }
                        }
                        .toggleStyle(WeeklyCardCheckboxStyle())
                        .accessibilityLabel(provider.name)
                    }
                }
            }
            if let historySaveError {
                Label(L10n.tr(historySaveError), systemImage: "exclamationmark.triangle")
                    .font(Typography.label)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshot.hasRecoveredHistory {
                Text(L10n.tr("Includes recovered daily totals. Their original dates are preserved; historical records may be incomplete."))
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshot.hasPartialRecords {
                Label(L10n.tr("Some local records could not be read. Totals may be incomplete."),
                      systemImage: "exclamationmark.triangle")
                    .font(Typography.label)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if metric == .apiValue && snapshot.hasPartialPricing {
                Text(L10n.tr("Some tokens have no known price. The + marks a partial value."))
                    .font(Typography.label)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(exporting)
    }

    private func controlLabel(_ title: String) -> some View {
        Text(L10n.tr(title)).font(Typography.label).foregroundStyle(.white.opacity(0.60))
    }

    private var exportActions: some View {
        VStack(spacing: 10) {
            if let status {
                Text(status)
                    .font(Typography.label)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(status)
            }
            HStack(spacing: 8) {
                WeeklyCardShareButton(enabled: canExport, content: {
                    status = nil
                    let card = snapshot
                    let png = try WeeklyCardExporter.png(snapshot: card, format: format,
                                                          signature: signature, metric: metric)
                    return try WeeklyCardShareContent(png: png, caption: card.shareText(metric: metric))
                }, onError: { error in
                    exportError = error.localizedDescription
                })
                .frame(height: 32)
                Menu {
                    Button { export(save: false) } label: {
                        Label(L10n.tr("Copy image"), systemImage: "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button { export(save: true) } label: {
                        Label(L10n.tr("Save PNG…"), systemImage: "arrow.down.to.line")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    Divider()
                    Button { copyCaption() } label: {
                        Label(L10n.tr("Copy caption"), systemImage: "text.alignleft")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Typography.providerTitle)
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                .help(L10n.tr("More export options"))
                .accessibilityLabel(L10n.tr("More export options"))
                .disabled(!canExport)
            }
        }
    }

    private func refresh() {
        now = Date()
        status = nil
        if usesFullHistory { history.refresh() } else { store.refresh() }
    }

    private func copyCaption() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(snapshot.shareText(metric: metric), forType: .string) {
            status = L10n.tr("Caption copied. Add it to your post.")
        } else {
            exportError = L10n.tr("Could not copy the caption. Try again.")
        }
    }

    private func export(save: Bool) {
        guard canExport else { return }
        exporting = true
        status = nil
        do {
            let data = try WeeklyCardExporter.png(snapshot: snapshot,
                                                  format: format, signature: signature, metric: metric)
            if save {
                let filename = "CodexIsland-\(period.rawValue)-\(snapshot.filenameDate)-\(metric.rawValue)-\(tier.rawValue)-\(format.rawValue).png"
                WeeklyCardExporter.save(data, filename: filename, window: WeeklyCardWindowController.shared.window) { result in
                    exporting = false
                    switch result {
                    case .success(let url):
                        if url != nil { status = L10n.tr("PNG saved. Your card is ready to share.") }
                    case .failure(let error): exportError = error.localizedDescription
                    }
                }
            } else {
                try WeeklyCardExporter.copyImage(data)
                exporting = false
                status = L10n.tr("Image copied. Paste it into your post.")
            }
        } catch {
            exporting = false
            exportError = error.localizedDescription
        }
    }
}

private struct WeeklyCardCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(configuration.isOn ? 0.14 : 0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    }
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                        }
                    }
                    .frame(width: 15, height: 15)
                configuration.label
                    .foregroundStyle(.white.opacity(configuration.isOn ? 0.85 : 0.55))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
