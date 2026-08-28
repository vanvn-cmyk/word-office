import Foundation

struct DocumentRef: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let url: URL
    var modifiedAt: Date
    let kind: DocumentKind

    init(id: UUID = UUID(), name: String, url: URL, modifiedAt: Date, kind: DocumentKind) {
        self.id = id
        self.name = name
        self.url = url
        self.modifiedAt = modifiedAt
        self.kind = kind
    }
}
