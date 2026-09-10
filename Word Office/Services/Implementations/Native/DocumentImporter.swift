import Foundation

/// Copies external files (Files app / iCloud) into app's Documents/ sandbox.
/// See Phase0-Implementation-Logic.md §5.1–§5.4 for the full contract.
///
/// Session 19 (2026-09-09) — added `nameConflict(for:)` + `importOne(url:resolution:)`
/// so the FAB import flow can prompt the user (Keep both / Replace / Skip)
/// on name collision instead of silently auto-suffixing. Legacy
/// `importFiles(from:)` still auto-suffixes for callers that don't need
/// the interactive path.
final class DocumentImporter: DocumentImporting {
    private let documentsURL: URL
    private let iCloudImporter: ICloudPlaceholderImporter
    private let fileManager = FileManager.default

    init(documentsURL: URL, iCloudImporter: ICloudPlaceholderImporter) {
        self.documentsURL = documentsURL
        self.iCloudImporter = iCloudImporter
    }

    // MARK: - Legacy batch import (auto-suffix on conflict)

    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        var outcomes: [ImportOutcome] = []
        for url in urls {
            let outcome = await importOne(url: url, resolution: .keepBoth)
            outcomes.append(outcome)
            // Continue batch even if one fails (§5.3).
        }
        return outcomes
    }

    // MARK: - Conflict check

    func nameConflict(for url: URL) async -> URL? {
        let destination = documentsURL.appendingPathComponent(url.lastPathComponent)
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    // MARK: - Single import with explicit resolution

    func importOne(url: URL, resolution: ImportConflictResolution) async -> ImportOutcome {
        if resolution == .skip {
            return ImportOutcome(sourceURL: url, result: .success(.skipped(sourceURL: url)))
        }

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

        do {
            try ensureDocumentsExists()
        } catch {
            return ImportOutcome(sourceURL: url, result: .failure(.copyFailed(underlying: error.localizedDescription)))
        }

        // Resolve the destination URL per the user's choice. `.replace` is
        // only meaningful when a conflict exists; on a no-conflict URL it
        // degrades gracefully to `.keepBoth`'s no-suffix path.
        let sameNameDestination = documentsURL.appendingPathComponent(url.lastPathComponent)
        let existsAtSameName = fileManager.fileExists(atPath: sameNameDestination.path)

        do {
            let landed: URL
            switch resolution {
            case .keepBoth:
                let destination = fileManager.nonConflictingURL(for: url.lastPathComponent, in: documentsURL)
                try fileManager.copyItem(at: url, to: destination)
                landed = destination

            case .replace:
                if existsAtSameName {
                    // Two-step swap (atomic isn't available for a source
                    // that lives outside `documentsURL`): copy the import
                    // to a fresh temp URL, then `replaceItemAt` swaps the
                    // existing file with the temp. This lets the OS handle
                    // the delete-old + install-new pair atomically on the
                    // destination volume.
                    //
                    // Session 20 code-review #1 — coordinate the staging
                    // read with NSFileCoordinator so a Files-provider
                    // placeholder is force-materialized before we copy.
                    // Without this, `iCloudImporter.downloadIfNeeded` at
                    // the top of the method returning success is not
                    // enough — a stale placeholder still returns "reads
                    // OK" to `copyItem` and lands zero-byte placeholder
                    // bytes over the previously-imported real content.
                    // `.forUploading` triggers the provider's own
                    // materialization pass immediately before the block
                    // runs; the `coordinator.coordinate(writingItemAt:)`
                    // on the destination pairs it with the atomic swap.
                    let staging = fileManager.temporaryDirectory
                        .appendingPathComponent("wordoffice-import-\(UUID().uuidString)-\(url.lastPathComponent)")
                    defer { try? fileManager.removeItem(at: staging) }

                    let coordinator = NSFileCoordinator()
                    var coordError: NSError?
                    var innerError: Error?
                    var swapResultURL: URL?
                    coordinator.coordinate(
                        readingItemAt: url,
                        options: [.forUploading],
                        writingItemAt: sameNameDestination,
                        options: [.forReplacing],
                        error: &coordError
                    ) { readURL, writeURL in
                        do {
                            try fileManager.copyItem(at: readURL, to: staging)
                            let replaced = try fileManager.replaceItemAt(writeURL, withItemAt: staging)
                            swapResultURL = replaced ?? writeURL
                        } catch {
                            innerError = error
                        }
                    }
                    if let coordError { throw coordError }
                    if let innerError { throw innerError }
                    landed = swapResultURL ?? sameNameDestination
                } else {
                    // No conflict — fall back to a plain copy under the
                    // requested filename. Same happy path as `.keepBoth`
                    // when the destination is free.
                    try fileManager.copyItem(at: url, to: sameNameDestination)
                    landed = sameNameDestination
                }

            case .skip:
                // Unreachable — early-returned above. Left as a case so
                // adding a fourth resolution is a compile error, matching
                // the exhaustive-switch discipline elsewhere in this
                // module (`PreviewSaveMode`).
                return ImportOutcome(sourceURL: url, result: .success(.skipped(sourceURL: url)))
            }

            let ref = DocumentRef(
                name: landed.lastPathComponent,
                url: landed,
                modifiedAt: Date(),
                kind: kind
            )
            return ImportOutcome(sourceURL: url, result: .success(.imported(ref)))
        } catch {
            return ImportOutcome(sourceURL: url, result: .failure(.copyFailed(underlying: error.localizedDescription)))
        }
    }

    // MARK: - Helpers

    private func ensureDocumentsExists() throws {
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
    }
}
