import Foundation

struct WeeklyCardLaunchGate {
    let defaults: UserDefaults
    private let versionKey = "WeeklyCard.lastLaunchVersion"
    private let pendingKey = "WeeklyCard.pendingLaunchVersion"

    func prepare(version: String, existingInstallation: Bool) -> Bool {
        guard !version.isEmpty else { return false }
        let previous = defaults.string(forKey: versionKey)
        let upgraded = previous.map { version.compare($0, options: .numeric) == .orderedDescending }
            ?? existingInstallation
        if previous == nil || upgraded {
            defaults.set(version, forKey: versionKey)
            if upgraded { defaults.set(version, forKey: pendingKey) }
        }
        return isPending(version: version)
    }

    func isPending(version: String) -> Bool {
        defaults.string(forKey: pendingKey) == version
    }

    func complete(version: String) {
        if isPending(version: version) { defaults.removeObject(forKey: pendingKey) }
    }
}
