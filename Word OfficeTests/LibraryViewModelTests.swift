import Foundation
import Testing
@testable import Word_Office

/// Unit tests for `LibraryViewModel`. The VM is `@MainActor`, and its 4 injected
/// services are protocol-typed — this suite exercises the orchestrator with
/// hand-written mocks + a real `LibraryStore` (which is a simple observable
/// container, so faking it would only obscure the assertions).
///
/// All mocks are `@unchecked Sendable`: every test drives the VM on `@MainActor`
/// and never touches mock state from a background thread, so the shared-state
/// hazard the checker would flag doesn't happen here.
@Suite("LibraryViewModel")
@MainActor
struct LibraryViewModelTests {
    let store: LibraryStore
    let bookmarks: MockBookmarkStore
    let scanner: MockScanner
    let metadata: MockMetadataStore
    let reminders: MockReminders
    let importer: MockImporter
    let creator: MockDocumentCreator
    let renamer: MockDocumentRenamer
    let zipper: MockDocumentZipper
    let vm: LibraryViewModel
    let folderURL: URL

    init() throws {
        self.store = LibraryStore()
        self.bookmarks = MockBookmarkStore()
        self.scanner = MockScanner()
        self.metadata = MockMetadataStore()
        self.reminders = MockReminders()
        self.importer = MockImporter()
        self.creator = MockDocumentCreator()
        self.renamer = MockDocumentRenamer()
        self.zipper = MockDocumentZipper()
        self.folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordoffice-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        self.vm = LibraryViewModel(
            store: store,
            bookmarkStore: bookmarks,
            scanner: scanner,
            metadataStore: metadata,
            reminders: reminders,
            importer: importer,
            documentCreator: creator,
            documentRenamer: renamer,
            documentZipper: zipper,
            documentsURL: folderURL
        )
    }

    // MARK: - loadLibrary state transitions

    @Test("loadLibrary sets .notGranted when no bookmark saved")
    func loadLibraryNoBookmark() async {
        bookmarks.savedBookmark = nil
        // Session 20 seeder auto-grant fallback (`LibraryViewModel.loadLibrary`
        // treats no-bookmark + seeded flag as `.granted` on the app's own
        // Documents/) would otherwise flip this test to `.granted`. Explicit
        // clear ensures the classic "no bookmark ever saved" path is the
        // one under test.
        UserDefaults.standard.set(false, forKey: SampleFileSeeder.didSeedDefaultsKey)

        await vm.loadLibrary()

        #expect(store.folderPermissionState == .notGranted)
        #expect(store.entries.isEmpty)
    }

    @Test("loadLibrary sets .revoked when resolve throws")
    func loadLibraryResolveFails() async {
        bookmarks.savedBookmark = makeBookmark()
        bookmarks.resolveResult = .failure(FolderBookmarkError.revoked)
        store.entries = [makeEntry(id: "prev-1")] // seed to verify it gets cleared

        await vm.loadLibrary()

        #expect(store.folderPermissionState == .revoked)
        #expect(store.entries.isEmpty)
    }

    @Test("loadLibrary populates entries on happy path")
    func loadLibraryHappyPath() async {
        bookmarks.savedBookmark = makeBookmark()
        bookmarks.resolveResult = .success(folderURL)
        scanner.entries = [
            makeScanEntry(name: "a.pdf"),
            makeScanEntry(name: "b.pdf")
        ]

        await vm.loadLibrary()

        #expect(store.folderPermissionState == .granted)
        #expect(store.entries.count == 2)
    }

    @Test("loadLibrary joins existing metadata + creates defaults for new files")
    func loadLibraryJoinsMetadata() async throws {
        bookmarks.savedBookmark = makeBookmark()
        bookmarks.resolveResult = .success(folderURL)
        let existingScan = makeScanEntry(name: "existing.pdf")
        let newScan = makeScanEntry(name: "new.pdf")
        scanner.entries = [existingScan, newScan]

        let existingID = existingScan.document.url.documentID(within: folderURL)
        metadata.storage[existingID] = DocumentMetadata(
            id: existingID,
            status: .signed,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastModifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        await vm.loadLibrary()

        #expect(store.entries.count == 2)
        let signed = store.entries.first { $0.metadata.status == .signed }
        let draft  = store.entries.first { $0.metadata.status == .draft }
        #expect(signed != nil)
        #expect(draft != nil)
    }

    @Test("loadLibrary sorts due-reminder entries to the top")
    func loadLibrarySortsDueFirst() async {
        bookmarks.savedBookmark = makeBookmark()
        bookmarks.resolveResult = .success(folderURL)
        let dueScan = makeScanEntry(name: "due.pdf")
        let plainScan = makeScanEntry(name: "plain.pdf")
        scanner.entries = [plainScan, dueScan]
        let dueID = dueScan.document.url.documentID(within: folderURL)
        reminders.dueIDs = [dueID]

        await vm.loadLibrary()

        #expect(store.entries.first?.id == dueID)
    }

    // MARK: - Mutations

    @Test("setStatus updates entry + persists to metadata store")
    func setStatusPersists() async {
        store.entries = [makeEntry(id: "doc-1", status: .draft)]

        await vm.setStatus(.signed, for: "doc-1")

        #expect(store.entries.first?.metadata.status == .signed)
        #expect(metadata.storage["doc-1"]?.status == .signed)
    }

    @Test("setStatus is a no-op for unknown id")
    func setStatusUnknownID() async {
        store.entries = [makeEntry(id: "doc-1", status: .draft)]

        await vm.setStatus(.signed, for: "bogus")

        #expect(store.entries.first?.metadata.status == .draft)
        #expect(metadata.storage["bogus"] == nil)
    }

    @Test("setReminder updates remindAt + persists")
    func setReminderPersists() async {
        store.entries = [makeEntry(id: "doc-1", status: .draft)]
        let target = Date(timeIntervalSince1970: 1_800_000_000)

        await vm.setReminder(target, for: "doc-1")

        #expect(store.entries.first?.metadata.remindAt == target)
        #expect(metadata.storage["doc-1"]?.remindAt == target)
    }

    @Test("recordOpen bumps lastOpenedAt")
    func recordOpenBumps() async {
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        var entry = makeEntry(id: "doc-1", status: .draft)
        entry.metadata.lastOpenedAt = oldDate
        store.entries = [entry]

        await vm.recordOpen("doc-1")

        let updated = store.entries.first?.metadata.lastOpenedAt
        #expect(updated != oldDate)
    }

    @Test("recordOpen does NOT change status (arch trap #2)")
    func recordOpenPreservesStatus() async {
        store.entries = [makeEntry(id: "doc-1", status: .draft)]

        await vm.recordOpen("doc-1")

        #expect(store.entries.first?.metadata.status == .draft)
    }

    // MARK: - Import (§4.5 v2)

    @Test("importFiles delegates to importer and drains the queue")
    func importFilesDelegates() async {
        let url = folderURL.appendingPathComponent("incoming.pdf")
        let successRef = DocumentRef(
            name: "incoming.pdf",
            url: url,
            modifiedAt: Date(),
            kind: .pdf
        )
        // Session 19 shape: `ImportOutcome.result` is now
        // `Result<ImportResult, ImportError>`; success wraps
        // `.imported(DocumentRef)` (was plain `DocumentRef`).
        importer.outcomes = [ImportOutcome(sourceURL: url, result: .success(.imported(successRef)))]

        // Session 19 change: `importFiles(from:)` now orchestrates a
        // queue and returns `Void` (was `[ImportOutcome]`). The test
        // observes success via the mock's captured resolutions +
        // the entry landing in the store.
        await vm.importFiles(from: [url])

        #expect(importer.lastResolutions.map(\.url) == [url])
        #expect(vm.store.entries.contains { $0.document.url == url })
    }

    @Test("importFiles sets errorMessage on any failure")
    func importFilesSurfacesError() async {
        let url = folderURL.appendingPathComponent("blocked.pdf")
        importer.outcomes = [
            ImportOutcome(sourceURL: url, result: .failure(.securityScopeAccessDenied))
        ]

        await vm.importFiles(from: [url])

        #expect(vm.errorMessage != nil)
    }

    // MARK: - Fixture builders

    private func makeBookmark() -> FolderBookmark {
        FolderBookmark(bookmarkData: Data([0x01, 0x02]), displayPath: folderURL.path)
    }

    private func makeScanEntry(name: String) -> LibraryScanEntry {
        let url = folderURL.appendingPathComponent(name)
        let ref = DocumentRef(
            name: name,
            url: url,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: DocumentKind.fromUTI(url: url) ?? .pdf
        )
        return LibraryScanEntry(document: ref, downloadState: .local)
    }

    private func makeEntry(id: String, status: DocumentStatus = .draft) -> LibraryEntry {
        let now = Date()
        return LibraryEntry(
            document: DocumentRef(
                name: "\(id).pdf",
                url: folderURL.appendingPathComponent("\(id).pdf"),
                modifiedAt: now,
                kind: .pdf
            ),
            metadata: DocumentMetadata(
                id: id,
                status: status,
                lastOpenedAt: now,
                lastModifiedAt: now
            ),
            downloadState: .local
        )
    }
}

// MARK: - Mocks

/// Simple, sync-safe mocks. See suite doc for the isolation contract.

final class MockBookmarkStore: FolderBookmarkResolving, @unchecked Sendable {
    var savedBookmark: FolderBookmark?
    var resolveResult: Result<URL, Error> = .failure(FolderBookmarkError.revoked)

    func loadSaved() -> FolderBookmark? { savedBookmark }
    func resolve(_ bookmark: FolderBookmark) throws -> URL { try resolveResult.get() }
    func save(_ bookmark: FolderBookmark) throws { savedBookmark = bookmark }
    func delete() throws { savedBookmark = nil }
}

final class MockScanner: DocumentLibraryScanning, @unchecked Sendable {
    var entries: [LibraryScanEntry] = []

    func scan(folder: URL) async -> [LibraryScanEntry] { entries }
}

final class MockMetadataStore: MetadataStoring, @unchecked Sendable {
    var storage: [String: DocumentMetadata] = [:]
    var upsertLog: [String] = []

    func fetch(id: String) async throws -> DocumentMetadata? { storage[id] }

    func upsert(_ metadata: DocumentMetadata) async throws {
        storage[metadata.id] = metadata
        upsertLog.append(metadata.id)
    }

    func fetchMany(ids: [String]) async throws -> [String: DocumentMetadata] {
        var result: [String: DocumentMetadata] = [:]
        for id in ids {
            if let m = storage[id] { result[id] = m }
        }
        return result
    }

    func delete(id: String) async throws { storage.removeValue(forKey: id) }

    func draftCount() async throws -> Int {
        storage.values.filter { $0.status == .draft }.count
    }

    func dueReminderIDs(before moment: Date) async throws -> [String] {
        storage.values
            .compactMap { entry -> (String, Date)? in
                guard let remindAt = entry.remindAt else { return nil }
                return (entry.id, remindAt)
            }
            .filter { $0.1 <= moment }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    func reset() async throws {
        storage.removeAll()
        upsertLog.removeAll()
    }
}

final class MockReminders: RemindScheduling, @unchecked Sendable {
    var dueIDs: [String] = []

    func dueReminderIDs(at moment: Date) async throws -> [String] { dueIDs }
}

final class MockImporter: DocumentImporting, @unchecked Sendable {
    var outcomes: [ImportOutcome] = []
    var lastImportedURLs: [URL]?
    /// Preconfigured conflict lookup — key is `url.lastPathComponent`.
    /// Empty map → `nameConflict(for:)` always returns nil (no-conflict
    /// fast path in `LibraryViewModel.processNextPendingImport`).
    var conflictsByFilename: [String: URL] = [:]
    /// Session 19 — mirrors the new `importOne` contract added when the
    /// conflict-resolution flow shipped. Consumes `outcomes` FIFO so
    /// existing tests that hand it a single outcome (`outcomes = [x]`)
    /// keep passing through `importFiles(from:)`'s per-URL loop
    /// without special-casing the multi-URL batches new tests may add.
    var lastResolutions: [(url: URL, resolution: ImportConflictResolution)] = []

    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        lastImportedURLs = urls
        return outcomes
    }

    func nameConflict(for url: URL) async -> URL? {
        conflictsByFilename[url.lastPathComponent]
    }

    func importOne(url: URL, resolution: ImportConflictResolution) async -> ImportOutcome {
        lastResolutions.append((url, resolution))
        // Pop the first configured outcome (test authors typically
        // stage one per expected import). Fall back to a synthesised
        // skipped outcome if the test forgot to configure — matches
        // the safer "do-nothing on stub gap" semantic that legacy
        // tests relied on for pass-through.
        if !outcomes.isEmpty {
            return outcomes.removeFirst()
        }
        return ImportOutcome(sourceURL: url, result: .success(.skipped(sourceURL: url)))
    }
}

final class MockDocumentCreator: DocumentCreating, @unchecked Sendable {
    var createdRequests: [(name: String, kind: DocumentKind)] = []
    var result: Result<DocumentRef, Error>?

    func create(name: String, kind: DocumentKind) async throws -> DocumentRef {
        createdRequests.append((name, kind))
        if let result { return try result.get() }
        return DocumentRef(
            name: "\(name).\(kind.rawValue)",
            url: FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).\(kind.rawValue)"),
            modifiedAt: Date(),
            kind: kind
        )
    }
}

final class MockDocumentRenamer: DocumentRenaming, @unchecked Sendable {
    /// Records every rename call in order so tests can assert on it.
    var renameRequests: [(url: URL, newFilename: String)] = []
    /// If set, `rename` throws this error instead of doing the move — lets
    /// tests exercise the failure branch of `LibraryViewModel.rename`.
    var error: Error?

    func rename(_ url: URL, to newFilename: String) async throws -> URL {
        renameRequests.append((url, newFilename))
        if let error { throw error }
        return url.deletingLastPathComponent().appendingPathComponent(newFilename)
    }
}

final class MockDocumentZipper: DocumentZipping, @unchecked Sendable {
    var zipRequests: [(url: URL, folder: URL)] = []
    var error: Error?

    func zip(_ url: URL, into folder: URL) async throws -> URL {
        zipRequests.append((url, folder))
        if let error { throw error }
        return folder.appendingPathComponent(
            "\(url.deletingPathExtension().lastPathComponent).zip"
        )
    }
}
