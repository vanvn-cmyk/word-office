import Foundation

/// Thin adapter over `MetadataStoring.dueReminderIDs(before:)`.
/// Kept as its own type so recurring reminders / snooze logic (Phase 2+) grow
/// here without touching the metadata store or its DIP contract.
final class RemindScheduler: RemindScheduling {
    private let metadata: MetadataStoring

    init(metadata: MetadataStoring) {
        self.metadata = metadata
    }

    func dueReminderIDs(at moment: Date) async throws -> [String] {
        try await metadata.dueReminderIDs(before: moment)
    }
}
