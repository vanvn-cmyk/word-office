import Foundation

/// Import files from external sources (Files app, iCloud Drive) into app sandbox.
/// Handles security-scoped resource access, iCloud placeholder download, and duplicate-name resolution.
protocol DocumentImporting: Sendable {
    /// Import multiple URLs. Returns per-URL result — one failure does not stop the batch (§5.3).
    ///
    /// Legacy contract: name collisions auto-suffix (`foo.pdf` → `foo (2).pdf`) with
    /// no user prompt. Kept for existing callers that don't need conflict resolution.
    /// For the Library FAB import flow use the `importOne(url:resolution:)` +
    /// `nameConflict(for:)` pair instead so the user can pick Keep both / Replace /
    /// Skip per file (Session 19 conflict-resolution flow).
    func importFiles(from urls: [URL]) async -> [ImportOutcome]

    /// True when a file with the same `lastPathComponent` already exists in the
    /// library folder. Cheap synchronous check — the FS lookup is a `stat`,
    /// nothing is opened. `nil` return means "no conflict, safe to import as-is";
    /// non-nil is the existing URL the new file would collide with.
    func nameConflict(for url: URL) async -> URL?

    /// Import one file with an explicit resolution for name collisions.
    /// Callers pair this with `nameConflict(for:)` — check first, prompt the
    /// user only if a conflict exists, then commit here with the chosen
    /// `resolution`.
    ///
    /// - `.keepBoth`: same as `importFiles(from:)` on that URL — suffix on
    ///   collision (`foo (2).pdf`). No-op-safe when no conflict exists.
    /// - `.replace` : overwrite the existing file in place via
    ///   `FileManager.replaceItemAt`. The old contents are unrecoverable
    ///   (iOS has no user-visible trash bin — same reality documented in
    ///   `PreviewSaveMode.replaceOriginal`). No-op-safe when no conflict.
    /// - `.skip`    : do nothing, return `.skipped`. The caller already knows
    ///   the user picked skip in the dialog; nothing to write.
    func importOne(url: URL, resolution: ImportConflictResolution) async -> ImportOutcome
}

/// User's choice from the "File already exists" conflict dialog. Mirrors
/// iOS Files.app's own copy-conflict pattern (Keep Both / Replace / Skip)
/// so users land on familiar semantics.
enum ImportConflictResolution: Sendable {
    /// Import with a suffixed name — original stays intact alongside the new
    /// copy. Same behaviour the legacy `importFiles(from:)` gives on any
    /// collision. Safe default: no data loss.
    case keepBoth

    /// Overwrite the existing file with the new content. Destructive — the
    /// original's bytes are gone once the swap completes. Only offered by
    /// the UI when the source has security-scoped access (Files-app or
    /// iCloud picks) — see the LibraryView dialog flow.
    case replace

    /// Don't import this URL. The batch continues with the next URL.
    /// Distinct from `.keepBoth` — skip writes nothing at all, whereas
    /// `keepBoth` on a conflict still creates the suffixed file.
    case skip
}

struct ImportOutcome: Sendable {
    let sourceURL: URL
    let result: Result<ImportResult, ImportError>
}

/// Success payload for an import attempt. `.skipped` distinguishes a
/// user-chosen skip from an actual write so the caller doesn't
/// toast "Imported" for a no-op.
enum ImportResult: Sendable {
    /// File landed in the library folder — either as a new file or by
    /// replacing an existing one. Carries the resulting `DocumentRef`.
    case imported(DocumentRef)
    /// User picked `.skip` in the conflict dialog. Nothing was written.
    case skipped(sourceURL: URL)
}

enum ImportError: Error, Sendable, LocalizedError {
    case securityScopeAccessDenied
    case iCloudDownloadFailed(underlying: String)
    case unsupportedType(extension: String)
    case copyFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .securityScopeAccessDenied:  "Can't access the file — the system blocked permission"
        case .iCloudDownloadFailed(let u):"iCloud download failed: \(u)"
        case .unsupportedType(let ext):   "File type .\(ext) is not supported yet"
        case .copyFailed(let u):          "Couldn't copy the file into the app: \(u)"
        }
    }
}
