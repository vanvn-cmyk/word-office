import Foundation
import Observation

/// Coordinator for the Library core loop (§10 v2). Owns no UI state itself —
/// writes into `LibraryStore`; the store is what SwiftUI observes.
///
/// Flow (Library-Architecture.md §4 scenario 3):
///   loadLibrary()  → resolve bookmark → scan folder → join metadata → sort by
///                     due reminders → write into store.
///   setStatus/setReminder → mutate `DocumentMetadata` → persist → upsert store row.
/// 
/// Errors surface via `errorMessage` (never thrown to caller), matching
/// `DocumentListViewModel` convention.
@Observable
@MainActor
final class LibraryViewModel {
    var errorMessage: String?
    private(set) var isLoading: Bool = false

    /// Active type/status filters — see `LibraryViewModel+Filtering.swift`.
    var typeFilter: DocumentTypeFilter = .all
    var statusFilter: DocumentStatus?
    var favouritesOnly: Bool = false

    /// Live text from the `TextField` — updates on every keystroke so the
    /// in-field clear button + collapse-to-Cancel transition react
    /// instantly. Its `didSet` schedules a trailing debounce that promotes
    /// the value into `searchText` after 200 ms of idle typing; the
    /// `searchResults` computed property reads `searchText`, so the O(n)
    /// filter over the library only runs at most once per burst instead
    /// of once per keystroke.
    var searchInput: String = "" {
        didSet {
            guard searchInput != oldValue else { return }
            scheduleDebouncedSearch()
        }
    }
    /// Debounced version of `searchInput` — the filter reads this.
    /// External writes go through `searchInput` (via TextField binding)
    /// or `clearSearch()` (Cancel / × buttons).
    private(set) var searchText: String = ""

    let store: LibraryStore
    private let bookmarkStore: any FolderBookmarkResolving
    private let scanner: any DocumentLibraryScanning
    private let metadataStore: any MetadataStoring
    private let reminders: any RemindScheduling
    private let importer: any DocumentImporting
    private let documentCreator: any DocumentCreating
    private let documentRenamer: any DocumentRenaming
    private let documentZipper: any DocumentZipping
    private let documentsURL: URL
    /// Bumped at the start of every `loadLibrary()` call — a scan that finishes
    /// after a newer one has started (e.g. "Change folder…" resets state while
    /// the previous scan is still running) checks its own generation before
    /// writing to `store` and no-ops instead of resurrecting stale results.
    private var loadGeneration = 0

    /// Handle for the `documentsDidChange` notification observer — released
    /// on deinit. `nonisolated(unsafe)` so `deinit` (which is nonisolated
    /// on this MainActor class) can remove it without a bridging Task —
    /// safe because deinit runs when the last reference drops, so there's
    /// no concurrent access possible.
    nonisolated(unsafe) private var documentsChangeObserver: NSObjectProtocol?

    /// Pending trailing-debounce reload — see `scheduleDebouncedReload()`.
    /// Same `nonisolated(unsafe)` reasoning as the observer above.
    nonisolated(unsafe) private var pendingReloadTask: Task<Void, Never>?

    // MARK: - Import conflict queue (Session 19)

    /// The current name-collision the user is being asked to resolve —
    /// non-nil drives `LibraryView`'s import-conflict `confirmationDialog`.
    /// Set from `importFiles(from:)` when a URL collides with an existing
    /// filename; cleared once the user picks a resolution (or Cancel), then
    /// the queue drains the next URL.
    var pendingImportConflict: PendingImportConflict?

    /// FIFO of URLs the current `importFiles(from:)` batch has yet to
    /// process. Populated by `importFiles(from:)`, drained one URL at a time
    /// by `processNextPendingImport()`. Kept on the VM (not passed as
    /// arguments through the resolve callback) so a swipe-to-dismiss of the
    /// dialog cleanly stops the batch — the closure has no queue to
    /// re-invoke.
    private var pendingImportQueue: [URL] = []

    /// Post-batch counters used by the wrap-up toast so multi-file imports
    /// summarise "3 files imported, 1 skipped" instead of firing 4 separate
    /// toasts. Reset at the start of every `importFiles(from:)` call.
    private var importBatchImportedCount = 0
    private var importBatchSkippedCount = 0
    private var importBatchFailureCount = 0

    /// Batch summary the View reads to fire ONE toast after the whole
    /// import batch settles (either queue drained or user cancelled).
    /// Set from `emitImportBatchSummary()`; the View watches with
    /// `.onChange` and clears it back to nil after showing the toast so
    /// a later batch's identical summary fires again.
    var lastImportBatchSummary: String?

    /// Pending trailing-debounce search — cancelled when a fresh
    /// keystroke arrives, so only the last input in a burst runs the
    /// filter. `nonisolated(unsafe)` same as the other Task handles.
    nonisolated(unsafe) private var pendingSearchTask: Task<Void, Never>?

    /// Trailing debounce window for `documentsDidChange`. A tool op posts
    /// once per successful write; back-to-back posts (user rapid-fires
    /// Merge → Convert, or `.task(id:)` reload races an incoming notif)
    /// collapse into one scan instead of N. `loadLibrary()` is I/O +
    /// metadata join heavy — trailing-only (no leading fire) is the safer
    /// choice; 200 ms is well below the "feels laggy" threshold.
    private static let reloadDebounceInterval: Duration = .milliseconds(200)

    /// Trailing debounce window for search — 200 ms strikes the balance
    /// between "results feel instant" and "typing doesn't re-filter the
    /// library on every character".
    private static let searchDebounceInterval: Duration = .milliseconds(200)

    init(store: LibraryStore,
         bookmarkStore: any FolderBookmarkResolving,
         scanner: any DocumentLibraryScanning,
         metadataStore: any MetadataStoring,
         reminders: any RemindScheduling,
         importer: any DocumentImporting,
         documentCreator: any DocumentCreating,
         documentRenamer: any DocumentRenaming,
         documentZipper: any DocumentZipping,
         documentsURL: URL) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.scanner = scanner
        self.metadataStore = metadataStore
        self.reminders = reminders
        self.importer = importer
        self.documentCreator = documentCreator
        self.documentRenamer = documentRenamer
        self.documentZipper = documentZipper
        self.documentsURL = documentsURL
        subscribeToDocumentsChange()
    }

    deinit {
        if let documentsChangeObserver {
            NotificationCenter.default.removeObserver(documentsChangeObserver)
        }
        pendingReloadTask?.cancel()
        pendingSearchTask?.cancel()
    }

    // MARK: - Search debounce

    /// Trailing debounce: cancel any pending promotion and schedule a
    /// fresh one `searchDebounceInterval` from now. Bursty typing =
    /// single filter run at the end of the burst.
    private func scheduleDebouncedSearch() {
        pendingSearchTask?.cancel()
        let snapshot = searchInput
        pendingSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.searchDebounceInterval)
            guard !Task.isCancelled else { return }
            self?.searchText = snapshot
        }
    }

    /// Clears BOTH `searchInput` and the debounced `searchText`
    /// immediately, and cancels any pending debounce — used by the
    /// Cancel button + in-field × so the user doesn't see the stale
    /// filter linger for the debounce window after tapping clear.
    func clearSearch() {
        pendingSearchTask?.cancel()
        searchInput = ""
        searchText = ""
    }

    /// Wires up a `documentsDidChange` listener so any tool that writes a
    /// file into `documentsURL` (Merge/Split/Convert/Scan/Sign/Fill Form)
    /// triggers a Library reload without the user having to pull-to-refresh.
    /// Handler is delivered on the main queue and dispatches to the
    /// MainActor via `Task { @MainActor }` so `scheduleDebouncedReload()`
    /// (which is `@MainActor`) can run without a bridging warning.
    private func subscribeToDocumentsChange() {
        documentsChangeObserver = NotificationCenter.default.addObserver(
            forName: .documentsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedReload()
            }
        }
    }

    /// Trailing debounce: cancel any pending reload and schedule a fresh
    /// one `reloadDebounceInterval` from now. Multiple notifications within
    /// the window coalesce into a single `loadLibrary()` — cheap when the
    /// tool tab produces one write at a time, but critical when reloads
    /// stack (e.g. an ongoing scan racing a pull-to-refresh while a tool
    /// finishes). `loadGeneration` still guards the merge with any manual
    /// reloads that fire in parallel — this only trims the notif-driven path.
    private func scheduleDebouncedReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.reloadDebounceInterval)
            guard !Task.isCancelled else { return }
            await self?.loadLibrary()
        }
    }

    // MARK: - Loading

    func loadLibrary() async {
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        defer {
            // Gated the same way every `store` write below is — an older call
            // superseded by a newer one (e.g. pull-to-refresh racing the
            // `.task(id:)` reload) must not clear `isLoading` out from under the
            // newer, still-in-flight call; only the call that's still current
            // when it finishes should flip it off.
            if generation == loadGeneration {
                isLoading = false
            }
        }

        // Session 19 auto-grant fallback — when no user bookmark is saved
        // BUT the first-launch sample-file seeder has already run,
        // treat the app's own `Documents/` folder as the primary
        // library source instead of bailing to `.notGranted`. Mirrors
        // the same fallback in `FolderPermissionViewModel.checkExistingPermission`
        // so the two entry points to library-state agree on the
        // no-bookmark + auto-granted case. `documentsURL` (the app's
        // sandbox `Documents/`) needs no security-scope claim —
        // sandbox-owned URLs are always readable — so we skip
        // straight to the shared post-resolve path below.
        let folderURL: URL
        let hasExternalBookmark: Bool
        if let bookmark = bookmarkStore.loadSaved() {
            hasExternalBookmark = true
            do {
                folderURL = try bookmarkStore.resolve(bookmark)
            } catch FolderBookmarkError.revoked, FolderBookmarkError.bookmarkStale, FolderBookmarkError.corruptedBookmark {
                // Never silently empty the library — CTA lives in the view (Library-Architecture.md §7 trap #4).
                guard generation == loadGeneration else { return }
                store.folderPermissionState = .revoked
                store.clear()
                return
            } catch {
                guard generation == loadGeneration else { return }
                store.folderPermissionState = .revoked
                errorMessage = error.localizedDescription
                store.clear()
                return
            }

            guard folderURL.startAccessingSecurityScopedResource() else {
                guard generation == loadGeneration else { return }
                store.folderPermissionState = .revoked
                store.clear()
                return
            }
        } else if UserDefaults.standard.bool(forKey: SampleFileSeeder.didSeedDefaultsKey) {
            folderURL = documentsURL
            hasExternalBookmark = false
        } else {
            guard generation == loadGeneration else { return }
            store.folderPermissionState = .notGranted
            store.clear()
            return
        }

        defer {
            if hasExternalBookmark { folderURL.stopAccessingSecurityScopedResource() }
        }

        guard generation == loadGeneration else { return }
        store.folderPermissionState = .granted
        store.hasExternalFolder = hasExternalBookmark

        // Two sources merged by documentID (Phase0-Implementation-Logic-v2.md §10.1):
        // the granted external folder, and files copied into the sandbox by
        // `importFiles()`. Independent scans — one being slow/empty never blocks the other.
        // Skip the second scan entirely when the granted folder IS `Documents/` —
        // otherwise every load double-scans and double-joins the same file list.
        // `resolvingSymlinksInPath()`, not `standardizedFileURL` — the latter
        // doesn't collapse `/var` vs `/private/var`-style symlink differences,
        // so a bookmark resolved through one form and `documentsURL` through the
        // other would compare unequal even when they're the same physical
        // folder, defeating this skip and duplicating every file in the library.
        let sameFolder = folderURL.resolvingSymlinksInPath().path == documentsURL.resolvingSymlinksInPath().path
        let grantedScanned: [LibraryScanEntry]
        let sandboxScanned: [LibraryScanEntry]
        if sameFolder {
            grantedScanned = await scanner.scan(folder: folderURL)
            sandboxScanned = []
        } else {
            async let grantedScan = scanner.scan(folder: folderURL)
            async let sandboxScan = scanner.scan(folder: documentsURL)
            (grantedScanned, sandboxScanned) = await (grantedScan, sandboxScan)
        }
        let now = Date()

        do {
            let granted = try await joinWithMetadata(grantedScanned, folderURL: folderURL, now: now)
            let sandbox = try await joinWithMetadata(sandboxScanned, folderURL: documentsURL, now: now)
            let merged = mergeSecondSource(sandbox, into: granted)
            let sorted = try await sortByDueReminders(merged, at: now)
            guard generation == loadGeneration else { return }
            store.replaceAll(sorted)
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    /// Change status manually (swipe / menu). Never auto-inferred from behaviour
    /// (Library-Architecture.md §7 trap #2).
    func setStatus(_ status: DocumentStatus, for entryID: String) async {
        guard var entry = store.entries.first(where: { $0.id == entryID }) else { return }
        entry.metadata.status = status
        entry.metadata.lastModifiedAt = Date()
        await persist(entry)
    }

    /// Toggle the pin — independent of `status`, same manual-only rule as above.
    func setFavourite(_ isFavourite: Bool, for entryID: String) async {
        guard var entry = store.entries.first(where: { $0.id == entryID }) else { return }
        entry.metadata.isFavourite = isFavourite
        entry.metadata.lastModifiedAt = Date()
        await persist(entry)
    }

    func setReminder(_ date: Date?, for entryID: String) async {
        guard var entry = store.entries.first(where: { $0.id == entryID }) else { return }
        entry.metadata.remindAt = date
        entry.metadata.lastModifiedAt = Date()
        await persist(entry)
    }

    // MARK: - Delete (kebab menu → "Delete File")

    /// Outcome of a delete attempt — same shape as `RenameOutcome` /
    /// `ConvertToZipOutcome` so `LibraryView` picks a toast from this
    /// instead of sniffing `errorMessage`.
    enum DeleteOutcome: Sendable, Equatable {
        case deleted
        case failed(String)
    }

    /// Permanently removes the file from disk plus its metadata row.
    /// **No undo once this succeeds** — the caller (`LibraryView` /
    /// `FileActionsMenu`) is responsible for confirming with the user
    /// BEFORE calling this.
    func deleteFile(entryID: String) async -> DeleteOutcome {
        guard let entry = store.entries.first(where: { $0.id == entryID }) else {
            return .failed("File not found")
        }

        // Same security-scope requirement as `convertToZip`'s
        // delete-source path (Session 20 code-review #12) — a
        // user-bookmarked EXTERNAL folder needs the claim or
        // `removeItem` fails with NSCocoaError 513. `didStartScope ==
        // false` for sandbox-owned URLs makes the guarded stop a no-op,
        // matching existing behaviour there.
        let didStartScope = entry.document.url.startAccessingSecurityScopedResource()
        defer { if didStartScope { entry.document.url.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.removeItem(at: entry.document.url)
        } catch {
            return .failed(error.localizedDescription)
        }

        // The file is already gone from disk at this point — a
        // metadata-delete failure is drift (an orphaned row), not data
        // loss, so it doesn't flip the reported outcome to `.failed`
        // (same reasoning as the rename path's old-row cleanup above).
        try? await metadataStore.delete(id: entry.id)
        store.remove(id: entry.id)
        return .deleted
    }

    /// Bump `lastOpenedAt` — best-effort; failure is silent (not user-facing).
    /// Does NOT change status (per §7 trap #2).
    func recordOpen(_ entryID: String) async {
        guard var entry = store.entries.first(where: { $0.id == entryID }) else { return }
        entry.metadata.lastOpenedAt = Date()
        try? await metadataStore.upsert(entry.metadata)
        store.upsert(entry)
    }

    // MARK: - Rename (kebab menu → "Rename")

    /// Outcome of a rename attempt — the caller (`LibraryView`) picks a
    /// toast style from this rather than sniffing `errorMessage`. The
    /// `.renamed` case carries the final filename (stem + preserved ext)
    /// so the success toast can display the same string the row now shows.
    enum RenameOutcome: Sendable, Equatable {
        case renamed(newName: String)
        /// Destination file already exists in the folder — the user picked
        /// a name that collides with an existing file. Not auto-suffixed
        /// (per user spec) — the caller shows a "Name already exists" toast
        /// and re-opens the rename input for the user to try again.
        case nameConflict
        /// Empty / whitespace-only stem, or the entry vanished mid-flight.
        case invalidName
        /// Any other file-system error — the localised message is in the
        /// associated value.
        case failed(String)
    }

    /// Rename `entryID` to `newStem` (extension preserved from the current
    /// filename — the kebab menu's rename sheet lets the user edit only the
    /// stem, then this method re-attaches the original extension).
    ///
    /// Metadata migration: APFS's `documentIdentifierKey` is persistent
    /// across rename (see `URL.documentID`), so the `d`-prefixed ID is
    /// usually unchanged and we only need to swap the URL in the store.
    /// The SHA256 fallback (`p` prefix — used when the file is on a volume
    /// without APFS document IDs) changes on rename, so we copy the old
    /// metadata row to the new ID and delete the old row.
    @discardableResult
    func rename(entryID: String, to newStem: String) async -> RenameOutcome {
        let trimmed = newStem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidName }
        // Path-traversal sanitisation (code-review S20 #2). Reject any
        // character that would let the user escape the library folder
        // root through `appendingPathComponent` — a `/` produces a
        // multi-segment path (`a/b` → `folder/a/b.pdf` under any
        // pre-existing `a/` sibling directory), `..` walks up out of
        // the folder, and NUL terminates the path early on some
        // volumes. `moveItem` would happily follow these; blocking
        // them here keeps every library file at the root the scanner
        // enumerates from.
        guard !trimmed.contains(where: { $0 == "/" || $0 == "\\" || $0 == "\0" }),
              trimmed != "..",
              trimmed != "."
        else { return .invalidName }
        guard let entry = store.entries.first(where: { $0.id == entryID }) else { return .invalidName }

        let oldURL = entry.document.url
        let ext = oldURL.pathExtension
        // Strip a duplicated `.<ext>` suffix so a user who habitually
        // types the full filename (`bar.pdf`) doesn't end up with a
        // double-extension file (`bar.pdf.pdf`). Case-insensitive
        // compare so `.PDF` also matches. Code-review S20 #7.
        let stemForFilename: String
        if !ext.isEmpty,
           let dotRange = trimmed.range(of: ".\(ext)", options: [.caseInsensitive, .backwards, .anchored]) {
            stemForFilename = String(trimmed[..<dotRange.lowerBound])
        } else {
            stemForFilename = trimmed
        }
        guard !stemForFilename.isEmpty else { return .invalidName }
        let newFilename = ext.isEmpty ? stemForFilename : "\(stemForFilename).\(ext)"
        let folder = oldURL.deletingLastPathComponent()
        let destination = folder.appendingPathComponent(newFilename)

        // No-op if the user "renamed" to the same name — save the disk hit
        // and don't emit a spurious `.nameConflict` (destination == source).
        if destination.standardizedFileURL == oldURL.standardizedFileURL {
            return .renamed(newName: oldURL.lastPathComponent)
        }

        // Pre-check collision; race is negligible on a single-user sandbox
        // and lets us return the semantic outcome without parsing NSError.
        //
        // Session 20 code-review #5 — case-only rename on the default
        // case-insensitive volume (APFS Case-Insensitive, HFS+) needs
        // to be distinguished from a real collision. `fileExists` returns
        // true for both "foo.pdf" AND "FOO.pdf" because they resolve to
        // the same inode; without this check the user could never change
        // just the capitalisation of a filename. Compare inodes via the
        // fileResourceIdentifier resource value — same identifier =
        // same file, so this is a self-collision (allowed, keep moving);
        // different identifier = real name clash (return .nameConflict).
        if FileManager.default.fileExists(atPath: destination.path) {
            let sourceID = try? oldURL.resourceValues(
                forKeys: [.fileResourceIdentifierKey]
            ).fileResourceIdentifier
            let destID = try? destination.resourceValues(
                forKeys: [.fileResourceIdentifierKey]
            ).fileResourceIdentifier
            let isSameFile: Bool
            if let s = sourceID as? NSObject, let d = destID as? NSObject {
                isSameFile = s.isEqual(d)
            } else {
                isSameFile = false
            }
            if !isSameFile {
                return .nameConflict
            }
            // Same inode — proceed as a case-only rename.
        }

        // Predict the post-rename document ID BEFORE touching disk. APFS's
        // `documentIdentifierKey` survives a rename on the same volume, so
        // the `d`-prefixed ID predicted here matches the post-move file's
        // actual ID; SHA256 fallback (`p` prefix) is a pure function of
        // the destination URL, so it also matches. Predicting first lets
        // us persist metadata BEFORE moving the file, so a metadata store
        // failure can bail without ever touching disk (code-review S20
        // #3 — the old order moved the file first and left disk/store
        // diverged when the upsert threw).
        let predictedNewID = destination.documentID(within: folder)

        if predictedNewID != entry.id {
            // ID will change (non-APFS SHA256 path). Two-phase:
            //   (a) upsert NEW metadata row keyed by predictedNewID
            //   (b) move file
            //   (c) delete old metadata row
            // If (a) fails, disk is untouched, return .failed.
            // If (b) fails after (a), roll back (a) so we don't leak
            //   a metadata row pointing at a file that doesn't exist.
            // If (c) fails after (a) + (b), the OLD row is orphaned but
            //   the new row is correct — user's favourite/status is
            //   preserved on the new file, so rename is still a success.
            //   Log-and-continue rather than swallow silently
            //   (code-review S20 #4 — the earlier `try?` masked every
            //   delete failure and produced silent orphans).
            let migratedMetadata = DocumentMetadata(
                id: predictedNewID,
                status: entry.metadata.status,
                lastOpenedAt: entry.metadata.lastOpenedAt,
                lastModifiedAt: Date(),
                remindAt: entry.metadata.remindAt,
                isFavourite: entry.metadata.isFavourite
            )
            do {
                try await metadataStore.upsert(migratedMetadata)
            } catch {
                return .failed(error.localizedDescription)
            }

            let newURL: URL
            do {
                newURL = try await documentRenamer.rename(oldURL, to: newFilename)
            } catch {
                // Rollback (a) — the just-inserted metadata row is now
                // stale (points at a file that doesn't exist).
                try? await metadataStore.delete(id: predictedNewID)
                return .failed(error.localizedDescription)
            }

            do {
                try await metadataStore.delete(id: entry.id)
            } catch {
                // Old-row cleanup failed — surface as a non-fatal
                // errorMessage but STILL report `.renamed`. The user's
                // file was renamed AND their favourite/status carried
                // over via the new row; the orphan is drift, not loss.
                errorMessage = "Renamed, but couldn't clean up old metadata: \(error.localizedDescription)"
            }

            let newDoc = DocumentRef(
                name: newURL.lastPathComponent,
                url: newURL,
                modifiedAt: Date(),
                kind: entry.document.kind
            )
            store.remove(id: entry.id)
            store.upsert(LibraryEntry(
                document: newDoc,
                metadata: migratedMetadata,
                downloadState: entry.downloadState
            ))
            return .renamed(newName: newURL.lastPathComponent)
        }

        // APFS ID-stable path — metadata ID doesn't change, so a
        // move-then-upsert order is safe: even if the timestamp upsert
        // fails, the metadata row's ID still matches the (renamed) file,
        // and the next scan will merge them correctly.
        let newURL: URL
        do {
            newURL = try await documentRenamer.rename(oldURL, to: newFilename)
        } catch {
            // NOT setting `errorMessage` here — the caller
            // (`LibraryView.performRename`) already toasts this outcome,
            // and `errorMessage` is bound to `.errorAlert` which would
            // fire a second modal on top of the toast (F10).
            return .failed(error.localizedDescription)
        }

        let newDoc = DocumentRef(
            name: newURL.lastPathComponent,
            url: newURL,
            modifiedAt: Date(),
            kind: entry.document.kind
        )
        var updatedMetadata = entry.metadata
        updatedMetadata.lastModifiedAt = Date()
        try? await metadataStore.upsert(updatedMetadata)
        store.upsert(LibraryEntry(
            document: newDoc,
            metadata: updatedMetadata,
            downloadState: entry.downloadState
        ))
        return .renamed(newName: newURL.lastPathComponent)
    }

    // MARK: - Convert to ZIP (kebab menu → "Convert to ZIP")

    /// Outcome of a `convertToZip` call — split into four cases so the
    /// caller can pick an accurate toast copy for each real-world path.
    /// The earlier boolean-plus-error-string return couldn't distinguish
    /// "zip created, source replaced" from "zip created but source
    /// silently left behind because the delete step failed" — the
    /// success toast would then read "The original file was replaced"
    /// while the file was still on disk (code-review P1, session 19).
    enum ConvertToZipOutcome: Sendable, Equatable {
        /// Zip archive written next to the source, source kept — the
        /// `.keepBoth` happy path (deleteSource == false).
        case createdKeepingSource
        /// Zip written AND source successfully removed — the `.replace`
        /// happy path.
        case createdAndReplacedSource
        /// Zip written but the follow-up `removeItem` on the source
        /// failed (permission race, provider file busy, sync conflict).
        /// User still has both files on disk — deliberately reported as
        /// its own case so the toast can avoid the "was replaced" lie
        /// and fall back to a keep-both message.
        case createdButSourceRemains
        /// Zip write itself failed — nothing landed. Localised message
        /// carried for the caller's error toast; `errorMessage` is
        /// deliberately NOT set to avoid a second modal via
        /// `.errorAlert` (F10).
        case failed(String)
    }

    /// Compress `entryID`'s file into a `.zip` in the sandbox `Documents/`.
    /// The new archive appears on the next Library reload — we broadcast
    /// `.documentsDidChange` so the debounced observer picks it up without
    /// requiring a pull-to-refresh (same pattern the PDF Tools use).
    ///
    /// Session 19 (2026-09-09) — added `deleteSource`. When `true`, the
    /// source file is removed AFTER the zip succeeds (Files.app "Replace
    /// with ZIP" semantic). Extensions differ (`.pdf` → `.zip`), so
    /// `replaceItemAt` cannot be used — the swap is a two-step (create
    /// zip, then delete source) with zip-first ordering so an aborted
    /// delete leaves the user with both files (zero data loss) rather
    /// than a broken zip + no source.
    ///
    /// Return moved to a four-case enum in the same session (code-review
    /// P1) so the toast copy can differentiate `.createdAndReplaced` from
    /// `.createdButSourceRemains` — the earlier boolean-plus-error
    /// contract silently reported "replaced" when the delete failed and
    /// both files were still on disk.
    func convertToZip(entryID: String, deleteSource: Bool = false) async -> ConvertToZipOutcome {
        guard let entry = store.entries.first(where: { $0.id == entryID }) else {
            return .failed("The file could not be found.")
        }
        do {
            _ = try await documentZipper.zip(entry.document.url, into: documentsURL)
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)

            guard deleteSource else { return .createdKeepingSource }

            // Delete verification: `try?` still (a raw throw hides the
            // successful zip write from the user), but the follow-up
            // `fileExists` tells us whether the delete actually ran or
            // silently failed. Two-signal approach — try+check — matches
            // the "trust the OS but verify" pattern used elsewhere for
            // FS ops with best-effort semantics.
            //
            // Session 20 code-review #12 — security-scope claim required
            // when the library folder is a user-bookmarked EXTERNAL
            // folder (iCloud Drive, third-party provider). Without the
            // claim, `removeItem` fails with NSCocoaError 513 → the
            // outcome degrades to `.createdButSourceRemains` and the
            // toast lies "keep both" when the user picked Replace.
            // `didStartScope == false` for sandbox-owned URLs (app's
            // own Documents/) — the guarded stop is a no-op there,
            // matching the existing behaviour.
            let didStartScope = entry.document.url.startAccessingSecurityScopedResource()
            defer { if didStartScope { entry.document.url.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: entry.document.url)
            let stillExists = FileManager.default.fileExists(atPath: entry.document.url.path)
            return stillExists ? .createdButSourceRemains : .createdAndReplacedSource
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Secondary Add-file flow (§4.5 v2)

    /// Payload for the "File already exists" dialog. Held as
    /// `pendingImportConflict` while the user picks a resolution; the
    /// dialog reads `filename` for its title, `existingURL` for context if
    /// the copy ever grows to show a preview of the existing file.
    struct PendingImportConflict: Identifiable, Sendable {
        let id = UUID()
        let sourceURL: URL
        let existingURL: URL
        var filename: String { sourceURL.lastPathComponent }
    }

    /// Kick off an interactive import batch — for each URL:
    /// 1. If no name conflict with the library folder, import immediately
    ///    (`.keepBoth` — the no-suffix path since destination is free).
    /// 2. If a conflict exists, park the batch, expose the collision via
    ///    `pendingImportConflict`, and await the user's choice from the
    ///    LibraryView dialog (`resolveImportConflict(_:)` continues the
    ///    drain).
    ///
    /// Session 19 (2026-09-09) rewrote this from the old batch-only
    /// auto-suffix path (which produced the `foo (2).pdf`, `foo (3).pdf`
    /// pile-up shown in the user's screenshot) so multi-file imports now
    /// prompt per file — same UX shape as iOS Files.app's own copy-conflict
    /// flow. Non-conflict URLs still fast-path with no dialog, so a fresh
    /// import from a picker with all-new filenames stays a single tap.
    func importFiles(from urls: [URL]) async {
        importBatchImportedCount = 0
        importBatchSkippedCount = 0
        importBatchFailureCount = 0
        pendingImportQueue = urls
        await processNextPendingImport()
    }

    /// User's dialog choice from `LibraryView`. Applies to the URL sitting
    /// in `pendingImportConflict`, then continues the drain. A nil
    /// `pendingImportConflict` is a no-op — protects against a double-tap
    /// race between the dialog buttons and a stale binding.
    func resolveImportConflict(_ resolution: ImportConflictResolution) async {
        guard let conflict = pendingImportConflict else { return }
        pendingImportConflict = nil
        await performImport(url: conflict.sourceURL, resolution: resolution)
        await processNextPendingImport()
    }

    /// User tapped Cancel — abandon EVERY remaining URL in the batch, not
    /// just the one showing in the dialog. Match iOS Files.app: Cancel is
    /// "stop the whole operation", Skip is "just this file". Wraps up
    /// with the batch toast so the user learns what actually landed
    /// before the cancel.
    func cancelImportBatch() {
        pendingImportConflict = nil
        pendingImportQueue.removeAll()
        emitImportBatchToast()
    }

    /// Take the next URL, check for a name conflict, either import
    /// immediately (fast path) or stop here waiting for the user's
    /// dialog resolution. Called recursively as the queue drains.
    private func processNextPendingImport() async {
        guard !pendingImportQueue.isEmpty else {
            emitImportBatchToast()
            return
        }
        let url = pendingImportQueue.removeFirst()

        if let existing = await importer.nameConflict(for: url) {
            // Park here — user has to pick before we can move on. Dialog
            // action calls `resolveImportConflict(_:)` which re-enters
            // `processNextPendingImport()` after applying the choice.
            pendingImportConflict = PendingImportConflict(sourceURL: url, existingURL: existing)
            return
        }
        await performImport(url: url, resolution: .keepBoth)
        await processNextPendingImport()
    }

    /// Perform one import with an already-chosen resolution and fold the
    /// outcome into the batch counters + `store`. Fatal errors bump the
    /// failure counter and surface via `errorMessage` (bound to
    /// `.errorAlert`); success upserts into the store for instant Library
    /// feedback.
    private func performImport(url: URL, resolution: ImportConflictResolution) async {
        let outcome = await importer.importOne(url: url, resolution: resolution)
        switch outcome.result {
        case .success(.imported(let ref)):
            importBatchImportedCount += 1
            let docID = ref.url.documentID(within: documentsURL)
            let metadata = DocumentMetadata(id: docID, lastOpenedAt: Date(), lastModifiedAt: ref.modifiedAt)
            try? await metadataStore.upsert(metadata)
            store.upsert(LibraryEntry(document: ref, metadata: metadata, downloadState: .local))
        case .success(.skipped):
            importBatchSkippedCount += 1
        case .failure(let error):
            importBatchFailureCount += 1
            // Surface the FIRST failure to `.errorAlert` (matches legacy
            // behaviour). Subsequent failures fold into the summary
            // toast's count.
            if errorMessage == nil {
                errorMessage = error.errorDescription
            }
        }
    }

    /// Fired once per batch — either after the queue drains normally or
    /// when the user cancels. The toast copy IS the batch summary; per-
    /// file toasts would spam the user during a multi-file import. Never
    /// fires when nothing happened (all-cancel with zero URLs processed).
    private func emitImportBatchToast() {
        let imported = importBatchImportedCount
        let skipped = importBatchSkippedCount
        // Failure count is reported via `.errorAlert`, not the toast — so
        // we deliberately leave it out of the summary to avoid the two
        // channels showing conflicting numbers.
        guard imported > 0 || skipped > 0 else { return }
        let title: String
        if skipped == 0 {
            title = imported == 1
                ? "Your document was imported to your Library"
                : "\(imported) documents were imported to your Library"
        } else if imported == 0 {
            title = skipped == 1
                ? "1 file was skipped"
                : "\(skipped) files were skipped"
        } else {
            title = "\(imported) imported, \(skipped) skipped"
        }
        lastImportBatchSummary = title
    }

    // MARK: - Create new (FAB → "Create new")

    enum CreateDocumentOutcome: Sendable, Equatable {
        case created
        /// `.xlsx`/`.pptx` — `MockArtifexDocumentWriter` no-ops those today (real writer
        /// arrives with the Artifex SDK swap). Surfaced honestly instead of leaving a
        /// dead 0-byte file the user can't actually open in Excel/PowerPoint.
        case unsupported
        case failed(String)
    }

    /// Blank document from the FAB "Create new" menu. Only `.docx` produces a real,
    /// openable file today — `DOCXCodec` writes a genuine minimal OOXML package
    /// (same codec Scan's "Export as Word" uses), unlike the legacy `LocalFileServiceImpl
    /// .create` 0-byte stub it's built on top of.
    @discardableResult
    func createBlankDocument(kind: DocumentKind) async -> CreateDocumentOutcome {
        guard kind == .docx else { return .unsupported }
        do {
            let ref = try await documentCreator.create(name: "Untitled", kind: kind)
            try DOCXCodec.write(AttributedString(""), to: ref.url)
            let now = Date()
            let docID = ref.url.documentID(within: documentsURL)
            let metadata = DocumentMetadata(id: docID, lastOpenedAt: now, lastModifiedAt: now)
            try? await metadataStore.upsert(metadata)
            store.upsert(LibraryEntry(document: ref, metadata: metadata, downloadState: .local))
            return .created
        } catch {
            errorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    /// Appends `secondary` entries not already present in `primary` (by documentID).
    /// `primary` (the granted folder) wins on collision — matters when the granted
    /// folder happens to be `Documents/` itself, so the same file isn't scanned twice.
    private func mergeSecondSource(_ secondary: [LibraryEntry], into primary: [LibraryEntry]) -> [LibraryEntry] {
        let primaryIDs = Set(primary.map(\.id))
        return primary + secondary.filter { !primaryIDs.contains($0.id) }
    }

    private func joinWithMetadata(_ scanned: [LibraryScanEntry],
                                  folderURL: URL,
                                  now: Date) async throws -> [LibraryEntry] {
        let ids = scanned.map { $0.document.url.documentID(within: folderURL) }
        let existing = try await metadataStore.fetchMany(ids: ids)

        var entries: [LibraryEntry] = []
        entries.reserveCapacity(scanned.count)

        for scanEntry in scanned {
            let docID = scanEntry.document.url.documentID(within: folderURL)
            let metadata: DocumentMetadata
            if let existingMetadata = existing[docID] {
                metadata = existingMetadata
            } else {
                // First scan encounter — default to `.draft`, persist so counts stay right.
                let created = DocumentMetadata(
                    id: docID,
                    lastOpenedAt: now,
                    lastModifiedAt: scanEntry.document.modifiedAt
                )
                try? await metadataStore.upsert(created)
                metadata = created
            }
            entries.append(LibraryEntry(
                document: scanEntry.document,
                metadata: metadata,
                downloadState: scanEntry.downloadState
            ))
        }
        return entries
    }

    private func sortByDueReminders(_ entries: [LibraryEntry], at moment: Date) async throws -> [LibraryEntry] {
        let dueIDs = Set(try await reminders.dueReminderIDs(at: moment))
        return entries.sorted { lhs, rhs in
            let lhsDue = dueIDs.contains(lhs.id)
            let rhsDue = dueIDs.contains(rhs.id)
            if lhsDue != rhsDue { return lhsDue }   // Due reminders float to top
            return lhs.document.modifiedAt > rhs.document.modifiedAt
        }
    }

    private func persist(_ entry: LibraryEntry) async {
        do {
            try await metadataStore.upsert(entry.metadata)
            store.upsert(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
