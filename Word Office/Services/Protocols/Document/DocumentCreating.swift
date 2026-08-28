import Foundation

protocol DocumentCreating: Sendable {
    func create(name: String, kind: DocumentKind) async throws -> DocumentRef
}
