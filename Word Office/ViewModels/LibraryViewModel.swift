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

    let store: LibraryStore
    private let bookmarkStore: any FolderBookmarkResolving
    private let scanner: any DocumentLibraryScanning
    private let metadataStore: any MetadataStoring
    private let reminders: any RemindScheduling
    private let importer: any DocumentImporting

    init(store: LibraryStore,
         bookmarkStore: any FolderBookmarkResolving,
         scanner: any DocumentLibraryScanning,
         metadataStore: any MetadataStoring,
         reminders: any RemindScheduling,
         importer: any DocumentImporting) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.scanner = scanner
        self.metadataStore = metadataStore
        self.reminders = reminders
        self.importer = importer
    }

    // MARK: - Loading

    func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }

        guard let bookmark = bookmarkStore.loadSaved() else {
            store.folderPermissionState = .notGranted
            store.clear()
            return
        }

        let folderURL: URL
        do {
            folderURL = try bookmarkStore.resolve(bookmark)
        } catch FolderBookmarkError.revoked, FolderBookmarkError.bookmarkStale, FolderBookmarkError.corruptedBookmark {
            // Never silently empty the library — CTA lives in the view (Library-Architecture.md §7 trap #4).
            store.folderPermissionState = .revoked
            store.clear()
            return
        } catch {
            store.folderPermissionState = .revoked
            errorMessage = error.localizedDescription
            store.clear()
            return
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            store.folderPermissionState = .revoked
            store.clear()
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        store.folderPermissionState = .granted

        let scanned = await scanner.scan(folder: folderURL)
        let now = Date()

        do {
            let entries = try await joinWithMetadata(scanned, folderURL: folderURL, now: now)
            let sorted = try await sortByDueReminders(entries, at: now)
            store.replaceAll(sorted)
            errorMessage = nil
        } catch {
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
    /// Note: imports land in app sandbox (`Documents/`), NOT the user-granted
    /// folder — they don't appear in `LibraryView` unless the granted folder
    /// happens to be `Documents/`. Sandbox-file listing is a v2 doc §4.5 concern.
    @discardableResult
    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        let outcomes = await importer.importFiles(from: urls)
        if let firstFailure = outcomes.first(where: {
            if case .failure = $0.result { return true }
            return false
        }), case .failure(let error) = firstFailure.result {
            errorMessage = error.errorDescription
        }
        return outcomes
    }

    // MARK: - Private helpers

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
