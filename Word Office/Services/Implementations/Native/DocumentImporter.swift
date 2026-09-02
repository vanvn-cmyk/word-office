import Foundation

/// Copies external files (Files app / iCloud) into app's Documents/ sandbox.
/// See Phase0-Implementation-Logic.md §5.1–§5.4 for the full contract.
final class DocumentImporter: DocumentImporting {
    private let documentsURL: URL
    private let iCloudImporter: ICloudPlaceholderImporter
    private let fileManager = FileManager.default

    init(documentsURL: URL, iCloudImporter: ICloudPlaceholderImporter) {
        self.documentsURL = documentsURL
        self.iCloudImporter = iCloudImporter
    }

    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        var outcomes: [ImportOutcome] = []
        for url in urls {
            let outcome = await importOne(url: url)
            outcomes.append(outcome)
            // Continue batch even if one fails (§5.3).
        }
        return outcomes
    }

    // MARK: - Single import

    private func importOne(url: URL) async -> ImportOutcome {
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }

        // Wait for iCloud placeholder to fully download (only iCloud files — §5.2).
        do {
            try await iCloudImporter.downloadIfNeeded(url)
        } catch {
            return ImportOutcome(sourceURL: url, result: .failure(.iCloudDownloadFailed(underlying: error.localizedDescription)))
        }

        // Verify UTI maps to a supported DocumentKind (not extension — §1).
        guard let kind = DocumentKind.fromUTI(url: url) else {
            return ImportOutcome(sourceURL: url, result: .failure(.unsupportedType(extension: url.pathExtension)))
        }

        // Copy into sandbox with duplicate-name handling (§5.4).
        let destination = nonConflictingDestination(for: url.lastPathComponent)
        do {
            try ensureDocumentsExists()
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            return ImportOutcome(sourceURL: url, result: .failure(.copyFailed(underlying: error.localizedDescription)))
        }

        let ref = DocumentRef(
            name: destination.lastPathComponent,
            url: destination,
            modifiedAt: Date(),
            kind: kind
        )
        return ImportOutcome(sourceURL: url, result: .success(ref))
    }

    // MARK: - Helpers

    private func ensureDocumentsExists() throws {
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
    }

    private func nonConflictingDestination(for fileName: String) -> URL {
        fileManager.nonConflictingURL(for: fileName, in: documentsURL)
    }
}
