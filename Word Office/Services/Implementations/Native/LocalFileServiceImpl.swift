import Foundation

/// Local file service backed by FileManager. Conforms to DocumentListing +
/// DocumentCreating for Sprint 0.1. Reads/writes are delegated to per-format
/// Reader/Writer services (SDK/Mock or SDK/Real).
///
/// NSFileCoordinator wrapping arrives Sprint 0.3 when Files Provider extension
/// is added (needed for cross-process safety).
final class LocalFileServiceImpl: DocumentListing, DocumentCreating {
    let documentsURL: URL
    private let fileManager = FileManager.default

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
    }

    // MARK: - DocumentListing

    func list() async throws -> [DocumentRef] {
        try ensureDocumentsExists()
        let contents = try fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let kind = DocumentKind.fromUTI(url: url)
            else { return nil }

            return DocumentRef(
                name: url.lastPathComponent,
                url: url,
                modifiedAt: values.contentModificationDate ?? Date(),
                kind: kind
            )
        }
    }

    func delete(_ ref: DocumentRef) async throws {
        try fileManager.removeItem(at: ref.url)
    }

    func rename(_ ref: DocumentRef, to newName: String) async throws {
        let destination = ref.url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: ref.url, to: destination)
    }

    // MARK: - DocumentCreating

    func create(name: String, kind: DocumentKind) async throws -> DocumentRef {
        try ensureDocumentsExists()
        let fileName = name.hasSuffix(".\(kind.rawValue)") ? name : "\(name).\(kind.rawValue)"
        let url = try nonConflictingURL(for: fileName)

        // Sprint 0.1: create empty file. Rich content templates arrive with real SDK Sprint 0.2.
        try Data().write(to: url)

        return DocumentRef(
            name: url.lastPathComponent,
            url: url,
            modifiedAt: Date(),
            kind: kind
        )
    }

    // MARK: - Helpers

    private func ensureDocumentsExists() throws {
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
    }

    /// Auto-suffix "(2)", "(3)"... when the desired filename already exists.
    /// See Phase0-Implementation-Logic.md §5.4.
    private func nonConflictingURL(for fileName: String) throws -> URL {
        fileManager.nonConflictingURL(for: fileName, in: documentsURL)
    }
}
