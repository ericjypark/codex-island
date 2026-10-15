import AppKit
import SwiftUI

@main
@MainActor
struct MusePresentationTests {
    static func main() throws {
        precondition(AppEnvironment.isDemo, "Presentation fixtures require demo mode")
        precondition(Bundle.main.bundleIdentifier == "dev.codexisland.RenderingBenchmark",
                     "Use the isolated rendering harness, never the installed app")
        NSApplication.shared.setActivationPolicy(.accessory)
        let destination = URL(fileURLWithPath: "notes/muse-code/renders")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        ProviderVisibilityStore.shared.set(.muse, at: 0)
        ProviderVisibilityStore.shared.set(.codex, at: 1)
        ProviderConnectionStore.shared.refresh(.muse)
        let notch = NotchInfo(width: 180, height: 32, hasNotch: true)
        for style in ChartStyle.allCases {
            StylePref.shared.style = style
            let panel = VStack(spacing: 0) {
                PanelHeader(notch: notch)
                UsageView().frame(height: 136)
                Text("SYNTHETIC PREVIEW").font(.system(size: 10)).foregroundStyle(.gray).padding(10)
            }
            .frame(width: 720).background(.black).preferredColorScheme(.dark)
            try render(panel, to: destination.appendingPathComponent("muse-\(style.rawValue).png"), maxHeight: 230)
        }
        try render(ProviderSelectionView().frame(width: 530).background(.black).preferredColorScheme(.dark),
                   to: destination.appendingPathComponent("muse-settings.png"), maxHeight: 600)
        ProviderVisibilityStore.shared.set(nil, at: 1)
        precondition(ProviderVisibilityStore.shared.selected == [.muse])
        precondition(ProviderConnectionStore.shared.primary(.muse)?.usedFraction == 0.38)
        let noLocalHistory = CostStore.shared.cost(for: .muse)
        precondition(noLocalHistory.today.error != nil && noLocalHistory.month.error != nil)
        let noReading = ConnectedUsage(message: "Muse Code did not include usage limits in this response. Try again after using Muse Code.",
                                       updatedAt: Date(), subscriptionActive: true)
        try render(ProviderConnectionSection(provider: .muse, snapshot: noReading, loading: false,
                                              connect: {}, refresh: {}).padding(24).frame(width: 530)
            .background(.black).preferredColorScheme(.dark),
                   to: destination.appendingPathComponent("muse-missing-quota.png"), maxHeight: 260)
        print("PASS Muse presentation: five chart styles, settings, missing quota, single-provider selection, unavailable cost")
    }

    static func render<V: View>(_ view: V, to url: URL, maxHeight: CGFloat) throws {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        precondition(size.height > 0 && size.height <= maxHeight, "Fixture overflow: \(size)")
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: url)
        print("PASS render \(url.lastPathComponent): \(size)")
    }
}
