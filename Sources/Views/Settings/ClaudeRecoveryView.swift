import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ClaudeRecoveryView: View {
    @StateObject var model: ClaudeRecoveryModel
    @Environment(\.dismiss) private var dismiss
    @State private var backupsExpanded = false
    @State private var detailsExpanded = false

    private static let timeZones = Array(Set(TimeZone.knownTimeZoneIdentifiers + ["UTC"])).sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Recover Claude usage"))
                    .font(.system(size: 21, weight: .semibold))
                Text(L10n.tr("Find saved counts from Claude Code, Cowork, and older local records."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    result
                    sourceOptions
                    if let notices = model.preview?.notices, !notices.isEmpty {
                        DisclosureGroup(L10n.tr("Scan details"), isExpanded: $detailsExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                                    Text(notice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("A backup is saved before importing. Original Claude files stay untouched."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(L10n.tr(model.outcome == nil ? "Cancel" : "Done")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(model.isSaving)
                    Spacer()
                    Button(L10n.tr(model.preview == nil && model.outcome == nil ? "Scan" : "Scan again")) { model.scan() }
                        .disabled(model.isWorking)
                    Button(L10n.tr("Import recovery")) { model.save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canSave)
                        .opacity(model.canSave ? 1 : 0.45)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.isSaving)
        .task { model.scan() }
        .onDisappear { model.cancelPreview() }
    }

    @ViewBuilder
    private var result: some View {
        if model.isWorking {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(L10n.tr(model.isSaving ? "Saving recovered usage…" : "Scanning saved records…"))
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        } else if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.tr("Recovery could not finish"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(L10n.tr(error)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
        } else if let outcome = model.outcome {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.tr(outcome.didSave ? "Recovered usage saved" : "This usage is already saved"), systemImage: "checkmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(L10n.tr("%@ additional tokens saved.", formatted(outcome.additionalTokens)))
                    .font(.system(size: 13))
                Text(L10n.tr("Your usage history now includes the recovered records."))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                if let backup = outcome.backupURL {
                    Button(L10n.tr("Show backup in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                        .controlSize(.small)
                }
            }
        } else if let preview = model.preview {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr(preview.hasChanges ? "Review your recovered usage" : "No additional usage found"))
                    .font(.system(size: 16, weight: .semibold))
                VStack(spacing: 9) {
                    totalRow("Already saved", tokens: preview.before.tokens)
                    totalRow("After recovery", tokens: preview.after.tokens)
                    totalRow("Additional tokens", tokens: preview.additionalTokens, emphasized: true)
                }
                Text(L10n.tr("Messages checked: %@ · Daily records: %@", formatted(preview.messageCount), formatted(preview.dailyCount)))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(L10n.tr("Totals include cache tokens. Daily records without model details remain unpriced."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(L10n.tr("Scan your selection to preview what can be recovered."))
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        }
    }

    private var sourceOptions: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Text(L10n.tr("Original timezone"))
                            .font(.system(size: 13, weight: .medium))
                        RecoveryHelp(
                            title: "Why is the original timezone needed?",
                            explanation: "Older daily totals used your Mac's timezone without saving its name. Choose the timezone used when those totals were recorded so recovery keeps the correct dates and avoids counting usage twice. Individual message records don't need this."
                        )
                    }
                    Spacer(minLength: 16)
                    Picker(L10n.tr("Original timezone"), selection: $model.timeZoneID) {
                        Text(L10n.tr("Not specified")).tag("")
                        ForEach(Self.timeZones, id: \.self) { zone in
                            Text(zone.replacingOccurrences(of: "_", with: " ")).tag(zone)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 265)
                }
                Text(L10n.tr(model.preview?.needsTimeZone == true
                    ? "Some old daily totals need their original timezone. Choose where they were recorded, then scan again."
                    : "Only needed for old daily totals. Leave unspecified if you don't know where they were recorded."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(L10n.tr("Older backups (optional)"), isExpanded: $backupsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("Add an extracted Claude projects folder or an old CodexIsland preferences file."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(L10n.tr("Add projects folder…")) { chooseSources(arePreferences: false) }
                        Button(L10n.tr("Add preferences file…")) { chooseSources(arePreferences: true) }
                    }
                    .controlSize(.small)
                    sourceList(model.projects, isPreference: false)
                    sourceList(model.preferences, isPreference: true)
                }
                .padding(.top, 12)
            }
        }
        .disabled(model.isWorking)
    }

    private func totalRow(_ label: String, tokens: Int, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr(label)).foregroundStyle(emphasized ? .primary : .secondary)
            Spacer()
            Text(formatted(tokens)).monospacedDigit()
        }
        .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
        .accessibilityElement(children: .combine)
    }

    private func sourceList(_ urls: [URL], isPreference: Bool) -> some View {
        ForEach(urls, id: \.self) { url in
            HStack {
                Label(url.lastPathComponent, systemImage: isPreference ? "doc" : "folder")
                    .lineLimit(1).truncationMode(.middle).help(url.path)
                Spacer()
                Button { model.removeSource(url, isPreference: isPreference) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.tr("Remove %@", url.lastPathComponent))
            }
            .font(.system(size: 12))
        }
    }

    private func chooseSources(arePreferences: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !arePreferences
        panel.canChooseFiles = arePreferences
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.title = L10n.tr(arePreferences ? "Choose old CodexIsland preferences" : "Choose a Claude projects folder")
        if arePreferences { panel.allowedContentTypes = [.propertyList] }
        panel.begin { response in
            if response == .OK { model.addSources(panel.urls, arePreferences: arePreferences) }
        }
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = L10n.locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

struct RecoveryHelp: View {
    let title: String
    let explanation: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .help(L10n.tr(explanation))
            .accessibilityLabel(L10n.tr(title))
            .accessibilityHint(L10n.tr(explanation))
    }
}
