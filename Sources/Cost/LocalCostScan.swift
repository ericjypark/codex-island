import Foundation

struct LocalCostScan {
    var events: [TokenEvent] = []
    var unreadableFiles = 0
    var skippedRecords = 0

    var notice: String? {
        if unreadableFiles > 0 { return "Some local records could not be read" }
        if skippedRecords > 0 { return "Some local records have no usage data" }
        if events.isEmpty { return "No local usage records yet" }
        return nil
    }
}
