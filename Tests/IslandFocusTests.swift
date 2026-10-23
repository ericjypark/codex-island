import AppKit

@main
@MainActor
struct IslandFocusTests {
    static func main() {
        setbuf(stdout, nil)
        let previousApp = NSWorkspace.shared.frontmostApplication
        let previousCursor = NSEvent.mouseLocation
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = IslandWindowController()
        controller.show()
        // Keep fixture events away from the installed island and physical notch.
        if let screen = NSScreen.main {
            controller.window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - controller.window.frame.width / 2,
                y: screen.visibleFrame.midY - controller.window.frame.height / 2
            ))
        }
        var testsPassed = false

        Task { @MainActor in
            @MainActor func moveCursor(to point: NSPoint) async {
                let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
                CGWarpMouseCursorPosition(CGPoint(x: point.x, y: displayHeight - point.y))
                if let event = NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: NSPoint(x: point.x - controller.window.frame.minX,
                                      y: point.y - controller.window.frame.minY),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: controller.window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0
                ) {
                    app.postEvent(event, atStart: false)
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            defer {
                let displayHeight = CGDisplayBounds(CGMainDisplayID()).height
                CGWarpMouseCursorPosition(CGPoint(x: previousCursor.x,
                                                 y: displayHeight - previousCursor.y))
                previousApp?.activate(options: [.activateIgnoringOtherApps])
            }

            guard let previousApp, previousApp.processIdentifier != getpid() else {
                print("FAIL: a different foreground app is required for the focus fixture")
                app.stop(nil)
                return
            }
            let frame = controller.window.frame
            await moveCursor(to: NSPoint(x: frame.minX, y: frame.minY))
            previousApp.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp.processIdentifier else {
                print("FAIL: could not establish the foreground-app baseline")
                app.stop(nil)
                return
            }

            var passed = true
            for state in [IslandModel.State.compact, .peek, .expanded] {
                controller.model.setState(state)
                await moveCursor(to: NSPoint(x: frame.midX, y: frame.maxY - 10))
                let retainsFocus = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == previousApp.processIdentifier && !controller.window.isKeyWindow
                let capturesMouse = !controller.window.ignoresMouseEvents
                print("\(retainsFocus && capturesMouse ? "PASS" : "FAIL") \(state) hover preserves foreground app and mouse access (foreground=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"), key=\(controller.window.isKeyWindow), mouse=\(capturesMouse))")
                passed = passed && retainsFocus && capturesMouse
                await moveCursor(to: NSPoint(x: frame.minX, y: frame.minY))
                passed = passed && controller.window.ignoresMouseEvents
            }
            controller.model.setState(.peek)
            await moveCursor(to: NSPoint(x: frame.midX, y: frame.maxY - 10))
            let clickPoint = CGPoint(x: frame.midX,
                                     y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + 10)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: clickPoint, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let clickWorks = controller.window.isKeyWindow && controller.model.state == .expanded
            print("\(clickWorks ? "PASS" : "FAIL") first click focuses and expands the island (key=\(controller.window.isKeyWindow), state=\(controller.model.state))")
            passed = passed && clickWorks
            controller.model.showScreen(.usage)
            if let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.window.windowNumber, context: nil,
                characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
                isARepeat: false, keyCode: 124
            ) {
                app.postEvent(event, atStart: false)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let keyboardWorks = ScreenPref.shared.screen == .cost
            print("\(keyboardWorks ? "PASS" : "FAIL") keyboard page navigation after click")
            passed = passed && keyboardWorks
            print(passed ? "PASS island hover focus regression" : "FAIL island hover focus regression")
            testsPassed = passed
            app.stop(nil)
        }
        app.run()
        exit(testsPassed ? 0 : 1)
    }
}
