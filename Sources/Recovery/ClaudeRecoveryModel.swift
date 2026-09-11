import Combine
import Foundation

@MainActor
final class ClaudeRecoveryModel: ObservableObject {
    @Published var timeZoneID = "" {
        didSet { if timeZoneID != oldValue { invalidatePreview() } }
    }
    @Published private(set) var projects: [URL] = []
    @Published private(set) var preferences: [URL] = []
    @Published private(set) var preview: ClaudeUsageRecovery.Preview?
    @Published private(set) var outcome: ClaudeUsageRecovery.Outcome?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isScanning = false
    @Published private(set) var isSaving = false

    private let ledger: UsageLedger
    private let defaultRoots: [URL]?
    private let defaultPreferences: [URL]?
    private let onSaved: () -> Void
    private var scanTask: Task<Void, Never>?

    init(ledger: UsageLedger = .shared, defaultRoots: [URL]? = nil, defaultPreferences: [URL]? = nil,
         onSaved: @escaping () -> Void = {}) {
        self.ledger = ledger
        self.defaultRoots = defaultRoots
        self.defaultPreferences = defaultPreferences
        self.onSaved = onSaved
    }

    var isWorking: Bool { isScanning || isSaving }
    var canSave: Bool { !isWorking && outcome == nil && preview?.hasChanges == true }

    func addSources(_ urls: [URL], arePreferences: Bool) {
        guard !isWorking else { return }
        if arePreferences { preferences = Array(Set(preferences + urls)).sorted { $0.path < $1.path } }
        else { projects = Array(Set(projects + urls)).sorted { $0.path < $1.path } }
        invalidatePreview()
    }

    func removeSource(_ url: URL, isPreference: Bool) {
        guard !isWorking else { return }
        if isPreference { preferences.removeAll { $0 == url } } else { projects.removeAll { $0 == url } }
        invalidatePreview()
    }

    func scan() {
        guard !isSaving else { return }
        invalidatePreview()
        var options = ClaudeUsageRecovery.Options()
        options.projects = projects
        options.preferences = preferences
        if !timeZoneID.isEmpty {
            guard let zone = TimeZone(identifier: timeZoneID) else {
                errorMessage = "Choose a valid timezone, then scan again."
                return
            }
            options.timeZone = zone
        }
        let selected = options
        let ledger = ledger, roots = defaultRoots, preferences = defaultPreferences
        isScanning = true
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ClaudeUsageRecovery.prepare(options: selected, ledger: ledger,
                                                        defaultRoots: roots, defaultPreferences: preferences) }
            }.value
            guard !Task.isCancelled, let self else { return }
            isScanning = false
            switch result {
            case .success(let value): preview = value
            case .failure(let error): errorMessage = ClaudeUsageRecovery.userMessage(for: error)
            }
            scanTask = nil
        }
    }

    func save() {
        guard canSave, let preview else { return }
        let ledger = ledger
        isSaving = true
        errorMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ClaudeUsageRecovery.apply(preview, ledger: ledger) }
            }.value
            isSaving = false
            switch result {
            case .success(let value):
                outcome = value
                if value.didSave { onSaved() }
            case .failure(let error):
                self.preview = nil
                errorMessage = ClaudeUsageRecovery.userMessage(for: error)
            }
        }
    }

    func cancelPreview() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func invalidatePreview() {
        cancelPreview()
        preview = nil
        outcome = nil
        errorMessage = nil
    }
}

extension Notification.Name {
    static let codexIslandUsageHistoryRecovered = Notification.Name("CodexIsland.usageHistoryRecovered")
}
