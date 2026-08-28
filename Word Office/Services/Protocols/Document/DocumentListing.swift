import Foundation

protocol DocumentListing: Sendable {
    func list() async throws -> [DocumentRef]
    func delete(_ ref: DocumentRef) async throws
    func rename(_ ref: DocumentRef, to newName: String) async throws
}
