// Session 19 (2026-09-09) — extracted from the two identical
// `commitPreview` implementations in `SignatureViewModel` and
// `FillFormViewModel` (code-review finding #6, propagated day-one
// duplication of `.replaceOriginal` logic incl. the trash-bin comment
// error #4). Owns the file-system side of committing a staged preview
// — security-scoped resource access, file coordination, off-main
// dispatch, and reporting whether the final file lands inside the
// library's scan folder.

import Foundation

/// Where the staged preview ended up + whether Library should re-scan.
struct PreviewCommitResult: Sendable {
    /// The URL the file lives at post-commit. For `.newFile` this is a
    /// non-conflicting name inside `documentsURL`; for `.replaceOriginal`
    /// it is `sourceURL` (or a cross-volume migrated URL when
    /// `replaceItemAt` couldn't be atomic).
    let finalURL: URL

    /// True when `finalURL` sits inside the library's scan folder
    /// (`documentsURL`). Callers gate `NotificationCenter.post(name:
    /// .documentsDidChange)` on this — external replaces (e.g. a PDF
    /// picked from iCloud Drive via `.fileImporter`) leave the library
    /// folder unchanged, so posting the notification would trigger a
    /// pointless re-scan and, worse, imply "look in Library" for a
    /// file that never lands there (code-review finding #5).
    let isInDocumentsFolder: Bool
}

/// Commits a staged preview file into its final location per the user's
/// choice from `PreviewConfirmSheet`. Encapsulates the safety plumbing
/// so `SignatureViewModel` / `FillFormViewModel` can't skip any of it.
protocol PreviewCommitting: Sendable {
    /// Move / atomically-replace `stagedURL` into its final destination.
    ///
    /// - `mode` `.newFile`         → move to `documentsURL` under a
    ///   non-conflicting suffix (`foo signed.pdf`, `foo signed (2).pdf`
    ///   ...). Source untouched.
    /// - `mode` `.replaceOriginal` → overwrite `sourceURL` in place via
    ///   `FileManager.replaceItemAt`, wrapped in
    ///   `startAccessingSecurityScopedResource` (Files-provider / iCloud
    ///   URLs come security-scoped from `.fileImporter`) and
    ///   `NSFileCoordinator.coordinate(writingItemAt:)` (matches the
    ///   F13 pattern applied elsewhere in this app for File-Provider-
    ///   backed writes).
    ///
    /// Runs on a background executor (`Task.detached(priority:
    /// .userInitiated)`) so the caller's `@MainActor` isn't blocked
    /// during a cross-volume replacement fallback that copies the whole
    /// file.
    func commit(
        stagedURL: URL,
        sourceURL: URL,
        mode: PreviewSaveMode,
        documentsURL: URL
    ) async throws -> PreviewCommitResult
}
