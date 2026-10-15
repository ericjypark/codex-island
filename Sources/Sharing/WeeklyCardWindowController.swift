import AppKit
import SwiftUI

@MainActor
final class WeeklyCardWindowController: NSWindowController {
    static let shared = WeeklyCardWindowController()
    private let hosting = NSHostingController(rootView: WeeklyCardStudio())

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = L10n.tr("Usage card")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 780, height: 640)
        window.setContentSize(NSSize(width: 900, height: 740))
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(refresh: Bool = true) {
        if !AppEnvironment.isDemo {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            WeeklyCardLaunchGate(defaults: .standard).complete(version: version)
        }
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        } else if window?.isVisible != true {
            hosting.rootView = WeeklyCardStudio()
            if refresh { CostStore.shared.refresh() }
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }
}

struct WeeklyCardButton: View {
    var body: some View {
        Button { WeeklyCardWindowController.shared.show() } label: {
            Label(L10n.tr("Share usage"), systemImage: "square.and.arrow.up")
                .font(Typography.button)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr("Create your usage card"))
    }
}
