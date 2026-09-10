import Foundation

/// `DocumentZipping` backed by `NSFileCoordinator`'s `.forUploading`
/// reading option. `.forUploading` only zips **packages** (bundles like
/// `.rtfd`, `.pages`) — passed a plain regular file (`.pdf`, `.docx`)
/// the coordinator hands back the file URL as-is, so copying that URL
/// out as `<stem>.zip` would produce invalid archive bytes with a `.zip`
/// extension. Code review flagged this shipping bug (F9).
///
/// Workaround: wrap the source file in a fresh temp directory named
/// after the file's stem, then coordinate against the directory —
/// `.forUploading` genuinely zips directories. The destination archive
/// extracts to `<stem>/<original filename>` (one wrapping folder,
/// matching Files.app's own compress behaviour on a single file).
///
/// The zip URL from the coordinator is a temporary file that is auto-
/// deleted when the callback returns, so we must copy it INSIDE the
/// callback — not after. Whole flow hops onto `Task.detached` because
/// `NSFileCoordinator.coordinate` is a synchronous blocking call.
final class NSFileCoordinatorZipper: DocumentZipping {
    func zip(_ url: URL, into folder: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let stem = url.deletingPathExtension().lastPathComponent
            let destination = fm.nonConflictingURL(for: "\(stem).zip", in: folder)

            // Staging directory: `/tmp/wordoffice-zip-<uuid>/<stem>/`.
            // Deleted on exit regardless of success/failure so tmpfs
            // doesn't accumulate stale wrappers.
            let stagingParent = fm.temporaryDirectory
                .appendingPathComponent("wordoffice-zip-\(UUID().uuidString)")
            let stagingDir = stagingParent.appendingPathComponent(stem)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingParent) }

            try fm.copyItem(
                at: url,
                to: stagingDir.appendingPathComponent(url.lastPathComponent)
            )

            var readError: NSError?
            var writeError: NSError?
            var innerError: Error?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                readingItemAt: stagingDir,
                options: [.forUploading],
                error: &readError
            ) { tempZipURL in
                // Nested writing coordination for the destination — matters
                // once `documentsURL` becomes iCloud- or File-Provider-
                // backed (planned per `LocalFileServiceImpl` header). A raw
                // `copyItem` would escape the coordination layer and race
                // Spotlight indexing / File Provider sync (F13). Same
                // coordinator handle so intents nest cleanly.
                coordinator.coordinate(
                    writingItemAt: destination,
                    options: [.forReplacing],
                    error: &writeError
                ) { writeURL in
                    do {
                        try fm.copyItem(at: tempZipURL, to: writeURL)
                    } catch {
                        innerError = error
                    }
                }
            }

            if let readError { throw readError }
            if let writeError { throw writeError }
            if let innerError { throw innerError }
            return destination
        }.value
    }
}
