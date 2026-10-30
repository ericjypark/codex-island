import AppKit
import Combine

@main
@MainActor
struct FullscreenPlacementTests {
    static func main() async {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                exit(1)
            }
            checks += 1
        }
        let displayChange = NSApplication.didChangeScreenParametersNotification
        for fallbackFullscreen in [true, false] {
            for storeFirst in [true, false] {
                let suite = "CodexIsland.FullscreenPlacementTests.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Test defaults") }
                defer { defaults.removePersistentDomain(forName: suite) }
                let placementEvents = NotificationCenter()
                var spaces = ["0.0": true, "2000.0": fallbackFullscreen]
                var reads: [String?] = []
                DisplayInfo.target = DisplayInfo(screen: NSScreen(
                    frame: NSRect(x: 0, y: 0, width: 900, height: 360)
                ))
                DisplayInfo.positionedDisplay = ("0.0", 0)
                let store = FullscreenStore(
                    defaults: defaults, workspaceCenter: NotificationCenter(),
                    sessionCenter: NotificationCenter(),
                    detectionContext: { FullscreenDetectionContext.current() },
                    readFullscreen: {
                        let id = DisplayInfo.positionedDisplay?.stableID
                        reads.append(id)
                        // Exercise a slow snapshot: timer delays are minimums,
                        // so a fixed sleep cannot establish quiescence.
                        if reads.count == 3 { Thread.sleep(forTimeInterval: 0.15) }
                        return id.flatMap { spaces[$0] }
                    }
                )
                let controller = IslandWindowController(fullscreen: store, applicationCenter: placementEvents)
                controller.show()
                await waitForReads(reads.count + 2, count: { reads.count })
                let window = controller.window
                check(!window.isVisible && window.ignoresMouseEvents, "Initial fullscreen target is hidden and cannot accept input")
                let fronts = window.frontRequests
                let activations = NSApp.activations
                let keys = window.keyRequests
                let readsBeforeChange = reads.count
                spaces.removeValue(forKey: "0.0")
                DisplayInfo.target = DisplayInfo(screen: NSScreen(
                    frame: NSRect(x: 2000, y: 0, width: 900, height: 360)
                ))
                NSEvent.mouseLocation = NSPoint(x: 2450, y: 350)

                // Split delivery forces either observer order independently of
                // NotificationCenter's unspecified callback iteration order.
                if storeFirst {
                    NotificationCenter.default.post(name: displayChange, object: nil)
                    await settle()
                    check(window.frontRequests == fronts && !window.isVisible && window.ignoresMouseEvents,
                          "An early store display notification cannot reveal or enable input on a vanished target")
                    check(reads.count == readsBeforeChange, "Only placement may sample a display reconfiguration")
                }
                placementEvents.post(name: displayChange, object: nil)
                check(DisplayInfo.positionedDisplay?.stableID == "2000.0",
                      "Display callback updates placement before yielding to queued work")
                await waitForReads(reads.count + 2, count: { reads.count })
                if !storeFirst {
                    NotificationCenter.default.post(name: displayChange, object: nil)
                    await settle()
                }
                check(window.frame.minX == 2000 && DisplayInfo.positionedDisplay?.stableID == "2000.0",
                      "Fallback placement and detector target move together")
                check(reads.dropFirst(readsBeforeChange).allSatisfy { $0 == "2000.0" },
                      "Every post-disconnect read uses the fallback, never the vanished display")
                check(window.isVisible == !fallbackFullscreen && window.ignoresMouseEvents == fallbackFullscreen,
                      "Fullscreen fallback stays hidden; desktop fallback restores stationary click access")
                check(window.frontRequests == fronts + (fallbackFullscreen ? 0 : 1),
                      "No transient reveal occurs before the final fallback state")
                check(NSApp.activations == activations && window.keyRequests == keys,
                      "Display fallback never steals application or keyboard focus")
                let settledReads = reads.count
                await settle()
                check(reads.count == settledReads, "Settled placement does not poll")
            }
        }
        print("PASS \(checks) integrated fullscreen placement checks")
    }

    private static func settle() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private static func waitForReads(_ expected: Int, count: () -> Int) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while count() < expected && clock.now < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard count() == expected else {
            FileHandle.standardError.write(Data("FAIL: Expected \(expected) settled reads, received \(count())\n".utf8))
            exit(1)
        }
    }
}
