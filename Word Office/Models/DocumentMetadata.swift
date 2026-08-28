import Foundation

struct DocumentMetadata: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var status: DocumentStatus
    var lastOpenedAt: Date
    var lastModifiedAt: Date
    var remindAt: Date?

    init(id: String,
         status: DocumentStatus = .draft,
         lastOpenedAt: Date = Date(),
         lastModifiedAt: Date = Date(),
         remindAt: Date? = nil) {
        self.id = id
        self.status = status
        self.lastOpenedAt = lastOpenedAt
        self.lastModifiedAt = lastModifiedAt
        self.remindAt = remindAt
    }
}
