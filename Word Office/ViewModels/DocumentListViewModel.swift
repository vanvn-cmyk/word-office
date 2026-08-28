import Foundation
import Observation

@Observable
@MainActor
final class DocumentListViewModel {
    private(set) var documents: [DocumentRef] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?
    var sortOrder: DocumentSortOrder = .modifiedDescending

    private let lister: any DocumentListing
    private let creator: any DocumentCreating

    init(lister: any DocumentListing, creator: any DocumentCreating) {
        self.lister = lister
        self.creator = creator
    }

    var sortedDocuments: [DocumentRef] {
        switch sortOrder {
        case .nameAscending:      documents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending:     documents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .modifiedAscending:  documents.sorted { $0.modifiedAt < $1.modifiedAt }
        case .modifiedDescending: documents.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await lister.list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(name: String, kind: DocumentKind) async -> DocumentRef? {
        do {
            let ref = try await creator.create(name: name, kind: kind)
            documents.append(ref)
            return ref
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ ref: DocumentRef) async {
        do {
            try await lister.delete(ref)
            documents.removeAll { $0.id == ref.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ ref: DocumentRef, to newName: String) async {
        do {
            try await lister.rename(ref, to: newName)
            await load() // Simplest: reload. Optimise later if needed.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
