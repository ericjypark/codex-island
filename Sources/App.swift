import SwiftUI
import AppKit
import Combine

@main
enum CodexIslandEntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--recover-claude" {
            exit(ClaudeUsageRecovery.run(arguments: Array(CommandLine.arguments.dropFirst(2))))
        }
        CodexIslandApp.main()
    }
}

struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // Placeholder scene — `App` requires at least one `Scene`. We never
        // trigger the system Settings menu (we're a `.accessory` app with
        // no menu bar), so this stays inert. Settings is shown via our own
        // SettingsWindowController.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var island: IslandWindowController?
    private var settingsShortcutMonitor: Any?
    private var weeklyCardLaunchObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let appPreferences = Bundle.main.bundleIdentifier
            .flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        let existingInstallation = appPreferences.keys.contains { $0.hasPrefix("MacIsland.") }
        let launchGate = WeeklyCardLaunchGate(defaults: .standard)
        let offerWeeklyCard = !AppEnvironment.isDemo
            && launchGate.prepare(version: version, existingInstallation: existingInstallation)

        // Before any window or store exists: the first cost scan must price
        // against the cached catalog, not fall back to the seed and then
        // silently change its numbers a moment later.
        PricingCatalog.loadFromDisk()

        NSApp.setActivationPolicy(.accessory)
        island = IslandWindowController()
        island?.show()

        // Route Cmd+, to our hand-rolled Settings window. Without this, the
        // inert `Settings { EmptyView() }` scene below claims the shortcut and
        // opens a blank window. Consuming the event (returning nil) keeps that
        // empty scene from ever surfacing.
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.show()
                return nil
            }
            return event
        }

        // Start fetching at app launch — NOT on view appear — so the panel
        // already has cached values the first time the user hovers, instead
        // of flashing "0%" while the first request lands.
        UsageStore.shared.startAutoRefresh()
        CostStore.shared.startAutoRefresh()
        PricingCatalog.startAutoRefresh()
        CurrencyStore.shared.startAutoRefresh()

        if offerWeeklyCard {
            let costs = CostStore.shared
            weeklyCardLaunchObservation = Publishers.CombineLatest3(
                costs.$claudeLoading, costs.$codexLoading, costs.$connectedLoading
            )
            .filter { !$0 && !$1 && $2.isEmpty }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.weeklyCardLaunchObservation = nil
                    guard launchGate.isPending(version: version) else { return }
                    launchGate.complete(version: version)
                    let snapshot = WeeklyUsageSnapshot.make(buckets: Dictionary(
                        uniqueKeysWithValues: IslandProvider.allCases.map { ($0, costs.cost(for: $0).dailyTokens) }
                    ))
                    guard snapshot.totalTokens > 0 else { return }
                    WeeklyCardWindowController.shared.show(refresh: false)
                }
            }
        }

        // Wire the alert engine after the usage store so its initial
        // recompute sees whatever values the first refresh has produced.
        AlertEngine.shared.start()

        // Touch the shared updater so Sparkle starts its background scheduler.
        _ = UpdaterController.shared
    }

    /// Pin the app to the run loop until the user explicitly quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
