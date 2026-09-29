import AppKit
import SwiftUI

@main
@MainActor
struct MacQuotaReference {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: destination.appendingPathComponent("mac-quota-samples.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let series = json?["series"] as? [String: [[String: Double]]]
        guard let samples = series?["codex.weekly"], samples.count >= 6 else {
            throw NSError(domain: "MacQuotaReference", code: 1, userInfo: [NSLocalizedDescriptionKey: "The copied Codex weekly history is unavailable."])
        }
        for remaining in [false, true] {
            let values = samples.compactMap { $0["used"] }.map { remaining ? 100 - $0 : $0 }
            guard let value = values.last else { continue }
            let chart = SparkSVG(value: value, color: IslandColor.codex, seed: 4, history: values)
                .frame(width: 240, height: 50).background(.black)
            let host = NSHostingView(rootView: chart.environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 240, height: 50)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3)); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "MacQuotaReference", code: 2) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "MacQuotaReference", code: 3) }
            try png.write(to: destination.appendingPathComponent(remaining ? "mac-quota-remaining.png" : "mac-quota-used.png"))
            window.close()
        }
        print("Rendered the actual Mac SparkSVG with \(samples.count) copied observations in used and remaining modes.")
    }
}
