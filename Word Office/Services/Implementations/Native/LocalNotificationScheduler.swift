import Foundation
import UserNotifications

/// Manages all three local notification types for the core-loop retention flow:
///
///   A) Re-engagement  — fires at 19:00 on day+3 and day+7 when user is inactive
///                       and draftCount > 0. Rescheduled every time the app
///                       backgrounds; cancelled the moment the app becomes active.
///
///   B) Stale draft    — fires once for the longest-waiting .draft file after
///                       5 days of inactivity. Reschedules to the next candidate
///                       when that file is processed.
///
///   C) Manual reminder — fires at the user-chosen date/time. Highest-priority;
///                        not subject to the 1-notification-per-day cap.
///
/// All notifications fire between 09:00 and 21:00 local time (quiet-hours rule).
/// Re-engagement targets 19:00 exactly. Stale-draft is clamped to that window.
@MainActor
final class LocalNotificationScheduler {
    static let shared = LocalNotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    var isAuthorized: Bool {
        get async { await center.notificationSettings().authorizationStatus == .authorized }
    }

    /// Presents the iOS system authorization dialog. Returns whether granted.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - A: Re-engagement

    /// Cancels any pending re-engagement requests then schedules fresh ones
    /// at 19:00 local time on day+3 and day+7. Safe to call on every app
    /// background — the cancel+reschedule is idempotent.
    func scheduleReEngagement(draftCount: Int) async {
        cancelReEngagement()
        guard draftCount > 0, await isAuthorized else { return }

        let countText = draftCount == 1 ? "1 file" : "\(draftCount) files"

        let day3 = UNMutableNotificationContent()
        day3.title = "\(draftCount == 1 ? "A file is" : "\(draftCount) files are") waiting for you"
        day3.body  = "You have \(countText) that need attention."
        day3.sound = .default

        let day7 = UNMutableNotificationContent()
        day7.title = "Still \(countText) unprocessed"
        day7.body  = "Open the app to get back on track."
        day7.sound = .default

        await add(content: day3, at: evening(daysFromNow: 3), identifier: "reengagement-3")
        await add(content: day7, at: evening(daysFromNow: 7), identifier: "reengagement-7")
    }

    /// Removes both re-engagement notifications — call on every app foreground.
    func cancelReEngagement() {
        center.removePendingNotificationRequests(withIdentifiers: ["reengagement-3", "reengagement-7"])
    }

    // MARK: - B: Stale Draft

    /// Inspects `entries` for the oldest `.draft` file and schedules exactly
    /// one "stale-draft" notification. Call after every `loadLibrary()`.
    ///
    /// - Already-stale files (> 5 days) fire in 60 s — the user is likely
    ///   in the background at this point; the notification arrives shortly
    ///   after they lock the screen.
    /// - Upcoming-stale files are scheduled for the exact moment they cross
    ///   the 5-day threshold, clamped to 09:00–21:00 quiet hours.
    func scheduleOrCancelStaleDraft(entries: [LibraryEntry]) async {
        center.removePendingNotificationRequests(withIdentifiers: ["stale-draft"])
        guard await isAuthorized else { return }

        let threshold: TimeInterval = 5 * 86_400
        let now = Date()
        let drafts = entries.filter { $0.metadata.status == .draft }

        if let alreadyStale = drafts
            .filter({ now.timeIntervalSince($0.metadata.lastModifiedAt) >= threshold })
            .min(by: { $0.metadata.lastModifiedAt < $1.metadata.lastModifiedAt }) {
            // Fire quickly — user is moving to background
            let content = staleDraftContent(name: alreadyStale.document.name)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 90, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "stale-draft", content: content, trigger: trigger))

        } else if let next = drafts
            .filter({ now.timeIntervalSince($0.metadata.lastModifiedAt) < threshold })
            .min(by: { $0.metadata.lastModifiedAt < $1.metadata.lastModifiedAt }) {
            // Schedule for when it crosses the threshold
            let rawFire = next.metadata.lastModifiedAt.addingTimeInterval(threshold)
            let fireClamped = clampToQuietHours(rawFire)
            let interval = fireClamped.timeIntervalSinceNow
            guard interval > 0 else { return }
            let content = staleDraftContent(name: next.document.name)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "stale-draft", content: content, trigger: trigger))
        }
    }

    private func staleDraftContent(name: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = name
        c.body  = "This file has been waiting for 5 days."
        c.sound = .default
        return c
    }

    // MARK: - C: Manual Reminder

    /// Schedules a calendar-pinned reminder for `entry` at `date`.
    /// Replaces any prior reminder for the same entry.
    func scheduleReminder(for entry: LibraryEntry, at date: Date) async {
        guard await isAuthorized else { return }
        let id = reminderID(entry.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let c = UNMutableNotificationContent()
        c.title = entry.document.name
        c.body  = "Your reminder."
        c.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    /// Cancels a pending reminder for the given entry ID.
    func cancelReminder(for entryID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID(entryID)])
    }

    private func reminderID(_ entryID: String) -> String { "reminder-\(entryID)" }

    // MARK: - Helpers

    private func add(content: UNMutableNotificationContent,
                     at components: DateComponents,
                     identifier: String) async {
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Returns DateComponents for 19:00 local time `daysFromNow` days in the future.
    private func evening(daysFromNow: Int) -> DateComponents {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: Date())
        c.day = (c.day ?? 0) + daysFromNow
        c.hour   = 19
        c.minute = 0
        c.second = 0
        return c
    }

    /// Shifts `date` into the 09:00–21:00 window. Dates outside push to 09:00
    /// the same day (before 09:00) or 09:00 the next day (after 21:00).
    private func clampToQuietHours(_ date: Date) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        if hour >= 9 && hour < 21 { return date }
        var c = cal.dateComponents([.year, .month, .day], from: date)
        if hour >= 21 { c.day = (c.day ?? 0) + 1 }
        c.hour = 9; c.minute = 0; c.second = 0
        return cal.date(from: c) ?? date
    }
}
