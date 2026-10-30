import AppKit
import Sparkle
import SwiftUI

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app
/// can talk to Sparkle without importing it directly. Holds Sparkle's UI
/// driver (alert + download window) too — no extra delegate plumbing needed.
///
/// Auto-check cadence and the "automatically download" preference are stored
/// by Sparkle itself in NSUserDefaults under SU* keys, so we don't duplicate
/// that state here.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController
    let updatesEnabled: Bool

    @Published var automaticallyChecks: Bool {
        didSet {
            guard updatesEnabled else {
                if automaticallyChecks { automaticallyChecks = false }
                return
            }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    private init() {
        updatesEnabled = Bundle.main.object(forInfoDictionaryKey: "CodexIslandLocalBuild") as? Bool != true
        controller = SPUStandardUpdaterController(
            startingUpdater: updatesEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecks = updatesEnabled && controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        guard updatesEnabled else { return }
        controller.checkForUpdates(nil)
    }
}
