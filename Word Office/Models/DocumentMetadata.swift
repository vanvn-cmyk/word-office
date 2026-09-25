import Foundation

struct DocumentMetadata: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var status: DocumentStatus
    var lastOpenedAt: Date
    var lastModifiedAt: Date
    var remindAt: Date?
    /// User-set pin, independent of `status` — a separate filter axis (Library-Home-v10
    /// mockup). Never auto-inferred, same "no auto-suggestion" rule as `status`.
    var isFavourite: Bool
    /// Set when the user taps "Still in progress" on the editor Done sheet —
    /// surfaces this file in the "Continue Working" section at the top of Home.
    /// Cleared on next open (`recordOpen`) or any manual status change (`setStatus`).
    var isContinueWorking: Bool

    nonisolated init(id: String,
         status: DocumentStatus = .draft,
         lastOpenedAt: Date = Date(),
         lastModifiedAt: Date = Date(),
         remindAt: Date? = nil,
         isFavourite: Bool = false,
         isContinueWorking: Bool = false) {
        self.id = id
        self.status = status
        self.lastOpenedAt = lastOpenedAt
        self.lastModifiedAt = lastModifiedAt
        self.remindAt = remindAt
        self.isFavourite = isFavourite
        self.isContinueWorking = isContinueWorking
    }
}
