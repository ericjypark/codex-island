import Foundation
import Darwin

enum FullscreenSpaceReader {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    static func read(targetDisplayID: String?) -> Bool? {
        // AppKit's presentation options can omit another app's fullscreen state.
        // Resolve these read-only, undocumented symbols optionally; fail open if
        // macOS removes them or changes the returned shape.
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let spacesSymbol = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)()
        let copySpaces = unsafeBitCast(spacesSymbol, to: CopySpaces.self)
        guard let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        return isFullscreen(displays: displays, targetDisplayID: targetDisplayID)
    }

    static func isFullscreen(displays: [[String: Any]], targetDisplayID: String?) -> Bool? {
        guard let targetDisplayID else { return nil }
        let matches = displays.filter { display in
            guard let identifier = display["Display Identifier"] as? String else { return false }
            // A single "Main" entry represents the shared Space when displays
            // do not have separate Spaces.
            return identifier == targetDisplayID || (displays.count == 1 && identifier == "Main")
        }
        guard matches.count == 1,
              let current = matches[0]["Current Space"] as? [String: Any],
              let type = current["type"] as? Int else { return nil }
        switch type {
        case 0: return false
        case 4: return true
        default: return nil
        }
    }
}
