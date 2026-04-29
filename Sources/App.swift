import SwiftUI
import AppKit

@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var island: IslandWindowController?
    var splash: SplashWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Start fetching at app launch — NOT on view appear — so the panel
        // already has cached values the first time the user hovers, instead
        // of flashing "0%" while the first request lands.
        UsageStore.shared.startAutoRefresh()

        // Splash first; on completion (after the icons land at the notch
        // position with the frost faded), the island window comes up and
        // the splash closes. Splash icons and island logos render at
        // identical screen positions, so the handoff is invisible.
        splash = SplashWindowController { [weak self] in
            self?.completeSplash()
        }
        splash?.show()
    }

    private func completeSplash() {
        // Bring up the island BEFORE closing splash so there's no empty
        // frame between them. Splash sits at .screenSaver (1000), island
        // at .popUpMenu (101) — island appears underneath the splash, the
        // splash closes, the user sees a continuous transition.
        island = IslandWindowController()
        island?.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            self.splash?.close()
            self.splash = nil
        }
    }
}
