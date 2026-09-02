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

    nonisolated init(id: String,
         status: DocumentStatus = .draft,
         lastOpenedAt: Date = Date(),
         lastModifiedAt: Date = Date(),
         remindAt: Date? = nil,
         isFavourite: Bool = false) {
        self.id = id
        self.status = status
        self.lastOpenedAt = lastOpenedAt
        self.lastModifiedAt = lastModifiedAt
        self.remindAt = remindAt
        self.isFavourite = isFavourite
    }
}
