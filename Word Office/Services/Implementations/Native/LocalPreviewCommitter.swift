// Session 19 (2026-09-09) — see `PreviewCommitting.swift` for the
// full rationale. This is the sole implementation; there is no
// remote/cloud variant.

import Foundation

final class LocalPreviewCommitter: PreviewCommitting {
    func commit(
        stagedURL: URL,
        sourceURL: URL,
        mode: PreviewSaveMode,
        documentsURL: URL
    ) async throws -> PreviewCommitResult {
        // Whole flow off `@MainActor` — cross-volume `replaceItemAt`
        // falls back to a full copy+delete, which for a 40MB scanned
        // PDF is ~1s. Doing that on `@MainActor` visibly hangs the UI
        // (code-review finding #9). `Task.detached` also matches the
        // same pattern `NSFileCoordinatorZipper` already uses for its
        // synchronous `NSFileCoordinator.coordinate` call (F13 zipper
        // history).
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let final: URL

            switch mode {
            case .newFile:
                // Non-conflicting write inside the app's library folder.
                // `moveItem` (not `copyItem`) so the staged temp file
                // vanishes atomically — no stale temp on success.
                let filename = stagedURL.lastPathComponent
                let candidate = fm.nonConflictingURL(for: filename, in: documentsURL)
                try fm.moveItem(at: stagedURL, to: candidate)
                final = candidate

            case .replaceOriginal:
                // 1. Cheap pre-flight: temp files under
                // `FileManager.default.temporaryDirectory` are NOT
                // guaranteed to survive memory pressure or app-suspend
                // (code-review finding #11). If iOS reclaimed it while
                // the user hesitated in the sheet, throw a clear error
                // instead of letting `replaceItemAt` return a generic
                // `NSFileNoSuchFileError`.
                guard fm.fileExists(atPath: stagedURL.path) else {
                    throw PreviewCommitError.stagedFileMissing
                }

                // 2. Security-scoped resource — REQUIRED for URLs that
                // came from `.fileImporter` pointing outside the app
                // sandbox (iCloud Drive, third-party Files providers).
                // The picker grants a transient scope on the picked
                // URL that the app must explicitly claim before
                // reading/writing; the grant does not survive the
                // `Task { await }` hop that `handleFilePicked` uses to
                // dispatch selection, so `SignFlowView` / `FillFormView`
                // can't rely on the original picker grant still being
                // active by the time commit runs. Start/stop pattern
                // matches `DocumentImporter.importOne` (line 28) and
                // `FolderBookmarkStore.resolve` (code-review finding
                // #1/#2).
                //
                // `didStartScope == false` is fine for URLs already
                // inside the app sandbox (no scoping needed) — the
                // guarded stop just becomes a no-op.
                let didStartScope = sourceURL.startAccessingSecurityScopedResource()
                defer { if didStartScope { sourceURL.stopAccessingSecurityScopedResource() } }

                // 3. `NSFileCoordinator` write coordination — matters
                // for any File-Provider-backed source (iCloud Drive,
                // third-party providers). A raw `replaceItemAt` escapes
                // the coordination layer and can race the provider's
                // reader/uploader, manifesting as iCloud `foo 2.pdf`
                // sync-conflict artifacts or lost signed bytes on other
                // devices. Same pattern `NSFileCoordinatorZipper` uses
                // for its destination write (F13 fix, code-review
                // finding #3).
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var replaceError: Error?
                var resultURL: URL?

                coordinator.coordinate(
                    writingItemAt: sourceURL,
                    options: [.forReplacing],
                    error: &coordError
                ) { writeURL in
                    do {
                        // `replaceItemAt` returns the URL the file
                        // lives at post-swap. On a same-volume atomic
                        // swap that's the same as `writeURL`; on a
                        // cross-volume fallback the OS may migrate to
                        // a different URL. Either way it's the URL
                        // the file lives at now.
                        let replaced = try fm.replaceItemAt(writeURL, withItemAt: stagedURL)
                        resultURL = replaced ?? writeURL
                    } catch {
                        replaceError = error
                    }
                }

                if let coordError { throw coordError }
                if let replaceError { throw replaceError }
                final = resultURL ?? sourceURL
            }

            // Path-prefix scope check — decides whether Library should
            // re-scan (fix #5). `standardizedFileURL` normalizes `/private`
            // vs `/var` etc. so the comparison is not tripped by symlinks
            // in the sandbox path.
            // `URL.isInside` (path-component comparison, not raw
            // `path.hasPrefix`) so a sibling directory whose name shares
            // the `documentsURL` prefix — e.g. `Documents-Backup/` —
            // doesn't false-positive as in-library and mis-fire a
            // Library re-scan. Session 19 code-review #5.
            let isInDocs = final.isInside(documentsURL)
            return PreviewCommitResult(finalURL: final, isInDocumentsFolder: isInDocs)
        }.value
    }
}

enum PreviewCommitError: Error, LocalizedError {
    /// The staged temp file was gone by the time commit ran — iOS
    /// reclaimed `temporaryDirectory` under memory pressure while the
    /// user hesitated in the confirmation sheet.
    case stagedFileMissing

    var errorDescription: String? {
        switch self {
        case .stagedFileMissing:
            return "Preview expired — please tap Save again to re-stage."
        }
    }
}
