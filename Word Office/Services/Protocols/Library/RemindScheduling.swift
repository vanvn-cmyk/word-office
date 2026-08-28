import Foundation

/// In-app reminder query. Product decision (product-strategy-changelog): NO push notifications,
/// NO `UNUserNotificationCenter`, NO background task — reminders surface only while app is open.
/// Wraps `MetadataStoring` for future extension (recurring reminders — Phase 2+).
protocol RemindScheduling: Sendable {
    /// documentIDs with `remindAt <= moment`, sorted ascending (oldest reminder first).
    /// Caller (`LibraryViewModel`) uses these to promote entries to the top of `LibraryView`.
    func dueReminderIDs(at moment: Date) async throws -> [String]
}
