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
    let vm: LibraryViewModel
    let folderURL: URL

    init() throws {
        self.store = LibraryStore()
        self.bookmarks = MockBookmarkStore()
        self.scanner = MockScanner()
        self.metadata = MockMetadataStore()
        self.reminders = MockReminders()
        self.importer = MockImporter()
        self.folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordoffice-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        self.vm = LibraryViewModel(
            store: store,
            bookmarkStore: bookmarks,
            scanner: scanner,
            metadataStore: metadata,
            reminders: reminders,
            importer: importer
        )
    }

    // MARK: - loadLibrary state transitions

    @Test("loadLibrary sets .notGranted when no bookmark saved")
    func loadLibraryNoBookmark() async {
        bookmarks.savedBookmark = nil

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

    @Test("importFiles delegates to importer and returns outcomes")
    func importFilesDelegates() async {
        let url = folderURL.appendingPathComponent("incoming.pdf")
        let successRef = DocumentRef(
            name: "incoming.pdf",
            url: url,
            modifiedAt: Date(),
            kind: .pdf
        )
        importer.outcomes = [ImportOutcome(sourceURL: url, result: .success(successRef))]

        let result = await vm.importFiles(from: [url])

        #expect(result.count == 1)
        #expect(importer.lastImportedURLs == [url])
    }

    @Test("importFiles sets errorMessage on any failure")
    func importFilesSurfacesError() async {
        let url = folderURL.appendingPathComponent("blocked.pdf")
        importer.outcomes = [
            ImportOutcome(sourceURL: url, result: .failure(.securityScopeAccessDenied))
        ]

        _ = await vm.importFiles(from: [url])

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

    func importFiles(from urls: [URL]) async -> [ImportOutcome] {
        lastImportedURLs = urls
        return outcomes
    }
}
