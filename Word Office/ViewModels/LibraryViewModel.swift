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
    var searchText: String = ""

    let store: LibraryStore
    private let bookmarkStore: any FolderBookmarkResolving
    private let scanner: any DocumentLibraryScanning
    private let metadataStore: any MetadataStoring
    private let reminders: any RemindScheduling
    private let importer: any DocumentImporting
    private let documentCreator: any DocumentCreating
    private let documentsURL: URL
    /// Bumped at the start of every `loadLibrary()` call — a scan that finishes
    /// after a newer one has started (e.g. "Change folder…" resets state while
    /// the previous scan is still running) checks its own generation before
    /// writing to `store` and no-ops instead of resurrecting stale results.
    private var loadGeneration = 0

    init(store: LibraryStore,
         bookmarkStore: any FolderBookmarkResolving,
         scanner: any DocumentLibraryScanning,
         metadataStore: any MetadataStoring,
         reminders: any RemindScheduling,
         importer: any DocumentImporting,
         documentCreator: any DocumentCreating,
         documentsURL: URL) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.scanner = scanner
        self.metadataStore = metadataStore
        self.reminders = reminders
        self.importer = importer
        self.documentCreator = documentCreator
        self.documentsURL = documentsURL
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

        guard let bookmark = bookmarkStore.loadSaved() else {
            guard generation == loadGeneration else { return }
            store.folderPermissionState = .notGranted
            store.clear()
            return
        }

        let folderURL: URL
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
        defer { folderURL.stopAccessingSecurityScopedResource() }

        guard generation == loadGeneration else { return }
        store.folderPermissionState = .granted

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

    /// Bump `lastOpenedAt` — best-effort; failure is silent (not user-facing).
    /// Does NOT change status (per §7 trap #2).
    func recordOpen(_ entryID: String) async {
        guard var entry = store.entries.first(where: { $0.id == entryID }) else { return }
        entry.metadata.lastOpenedAt = Date()
        try? await metadataStore.upsert(entry.metadata)
        store.upsert(entry)
    }

    // MARK: - Secondary Add-file flow (§4.5 v2)

    /// Import external files (Mail / AirDrop / iCloud share) into app sandbox.
    /// Batch semantics per §5.3 — one failure never kills the rest.
    /// Sets `errorMessage` to the first failure's message if any URL failed;
    /// caller reads full per-URL outcomes from the return value.
    ///
    /// Each success is upserted into `store` immediately (instant feedback —
    /// the row appears without waiting for the next `loadLibrary()` scan);
    /// `loadLibrary()` also merges sandbox `Documents/` as a second source so
    /// imported files still show up after a relaunch.
    @discardableResult
    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        let outcomes = await importer.importFiles(from: urls)
        let now = Date()

        for outcome in outcomes {
            guard case .success(let ref) = outcome.result else { continue }
            let docID = ref.url.documentID(within: documentsURL)
            let metadata = DocumentMetadata(id: docID, lastOpenedAt: now, lastModifiedAt: ref.modifiedAt)
            try? await metadataStore.upsert(metadata)
            store.upsert(LibraryEntry(document: ref, metadata: metadata, downloadState: .local))
        }

        if let firstFailure = outcomes.first(where: {
            if case .failure = $0.result { return true }
            return false
        }), case .failure(let error) = firstFailure.result {
            errorMessage = error.errorDescription
        }
        return outcomes
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
