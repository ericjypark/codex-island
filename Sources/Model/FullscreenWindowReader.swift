import AppKit
import CoreGraphics

enum FullscreenWindowReader {
    @MainActor
    static func read(targetDisplayID: CGDirectDisplayID) -> Bool? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        // CGDisplayBounds and window bounds both use top-left display coordinates.
        // No window titles, pixels, or Accessibility permissions are needed.
        return isFullscreen(windows: windows, targetBounds: CGDisplayBounds(targetDisplayID),
                            foregroundPID: app.processIdentifier)
    }

    static func isFullscreen(windows: [[String: Any]], targetBounds: CGRect,
                             foregroundPID: pid_t) -> Bool {
        guard foregroundPID > 0, valid(targetBounds) else { return false }
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == foregroundPID,
                  window[kCGWindowIsOnscreen as String] as? Bool == true,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha.isFinite, alpha > 0,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary), valid(bounds) else { return false }
            // Match all edges, not just a large overlap: maximized work-area
            // windows and oversized windows spanning displays must not qualify.
            let tolerance: CGFloat = 2
            return abs(bounds.minX - targetBounds.minX) <= tolerance
                && abs(bounds.minY - targetBounds.minY) <= tolerance
                && abs(bounds.maxX - targetBounds.maxX) <= tolerance
                && abs(bounds.maxY - targetBounds.maxY) <= tolerance
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}
