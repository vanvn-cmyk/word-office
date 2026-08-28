import Foundation
import Testing
@testable import Word_Office

/// Unit tests for `MetadataStoreImpl` (GRDB / SQLite).
/// Each test opens a fresh SQLite file at a unique temp path — clean slate per
/// test and safe under parallel execution. Temp files leak; the OS sweeps them.
@Suite("MetadataStoreImpl")
struct MetadataStoreImplTests {
    let store: MetadataStoreImpl
    let dbURL: URL

    init() throws {
        self.dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordoffice-metadata-\(UUID().uuidString).sqlite")
        self.store = try MetadataStoreImpl(databaseURL: dbURL)
    }

    // MARK: - CRUD

    @Test("upsert then fetch returns the same metadata")
    func upsertAndFetch() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = DocumentMetadata(
            id: "doc-1",
            status: .draft,
            lastOpenedAt: now,
            lastModifiedAt: now.addingTimeInterval(60),
            remindAt: now.addingTimeInterval(3600)
        )

        try await store.upsert(metadata)
        let fetched = try await store.fetch(id: "doc-1")

        #expect(fetched == metadata)
    }

    @Test("fetch returns nil for unknown id")
    func fetchUnknownReturnsNil() async throws {
        let fetched = try await store.fetch(id: "nonexistent")
        #expect(fetched == nil)
    }

    @Test("upsert overwrites existing row")
    func upsertOverwrites() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let base = DocumentMetadata(id: "doc-1", status: .draft, lastOpenedAt: now, lastModifiedAt: now)
        var updated = base
        updated.status = .signed

        try await store.upsert(base)
        try await store.upsert(updated)

        let fetched = try await store.fetch(id: "doc-1")
        #expect(fetched?.status == .signed)
    }

    @Test("fetchMany batches ids correctly")
    func fetchManyBatches() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 1...5 {
            try await store.upsert(DocumentMetadata(id: "doc-\(i)", lastOpenedAt: now, lastModifiedAt: now))
        }

        let result = try await store.fetchMany(ids: ["doc-2", "doc-4", "doc-99"])

        #expect(result.count == 2)
        #expect(result["doc-2"]?.id == "doc-2")
        #expect(result["doc-4"]?.id == "doc-4")
        #expect(result["doc-99"] == nil)
    }

    @Test("fetchMany with empty ids returns empty dict")
    func fetchManyEmpty() async throws {
        let result = try await store.fetchMany(ids: [])
        #expect(result.isEmpty)
    }

    @Test("delete removes the row")
    func deleteRemoves() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsert(DocumentMetadata(id: "doc-1", lastOpenedAt: now, lastModifiedAt: now))
        try await store.delete(id: "doc-1")

        let fetched = try await store.fetch(id: "doc-1")
        #expect(fetched == nil)
    }

    // MARK: - Aggregates

    @Test("draftCount counts only draft status")
    func draftCountOnlyDraft() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsert(DocumentMetadata(id: "d1", status: .draft,    lastOpenedAt: now, lastModifiedAt: now))
        try await store.upsert(DocumentMetadata(id: "d2", status: .draft,    lastOpenedAt: now, lastModifiedAt: now))
        try await store.upsert(DocumentMetadata(id: "s1", status: .signed,   lastOpenedAt: now, lastModifiedAt: now))
        try await store.upsert(DocumentMetadata(id: "r1", status: .reviewed, lastOpenedAt: now, lastModifiedAt: now))
        try await store.upsert(DocumentMetadata(id: "x1", status: .sent,     lastOpenedAt: now, lastModifiedAt: now))

        let count = try await store.draftCount()
        #expect(count == 2)
    }

    @Test("draftCount returns 0 for empty store")
    func draftCountEmpty() async throws {
        let count = try await store.draftCount()
        #expect(count == 0)
    }

    // MARK: - Reminders

    @Test("dueReminderIDs returns only past reminders, ascending")
    func dueReminderIDsSorted() async throws {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier  = cutoff.addingTimeInterval(-7200)
        let earliest = cutoff.addingTimeInterval(-86400)
        let future   = cutoff.addingTimeInterval(3600)

        try await store.upsert(DocumentMetadata(id: "d-future",   lastOpenedAt: cutoff, lastModifiedAt: cutoff, remindAt: future))
        try await store.upsert(DocumentMetadata(id: "d-earliest", lastOpenedAt: cutoff, lastModifiedAt: cutoff, remindAt: earliest))
        try await store.upsert(DocumentMetadata(id: "d-earlier",  lastOpenedAt: cutoff, lastModifiedAt: cutoff, remindAt: earlier))
        try await store.upsert(DocumentMetadata(id: "d-nil",      lastOpenedAt: cutoff, lastModifiedAt: cutoff, remindAt: nil))

        let due = try await store.dueReminderIDs(before: cutoff)

        #expect(due == ["d-earliest", "d-earlier"])
    }

    @Test("dueReminderIDs excludes rows with nil remindAt")
    func dueReminderIDsIgnoresNil() async throws {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsert(DocumentMetadata(id: "d-nil", lastOpenedAt: cutoff, lastModifiedAt: cutoff, remindAt: nil))

        let due = try await store.dueReminderIDs(before: cutoff)
        #expect(due.isEmpty)
    }

    // MARK: - Reset

    @Test("reset wipes all rows")
    func resetWipes() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsert(DocumentMetadata(id: "d1", lastOpenedAt: now, lastModifiedAt: now))
        try await store.upsert(DocumentMetadata(id: "d2", lastOpenedAt: now, lastModifiedAt: now))

        try await store.reset()

        let d1 = try await store.fetch(id: "d1")
        let d2 = try await store.fetch(id: "d2")
        let count = try await store.draftCount()

        #expect(d1 == nil)
        #expect(d2 == nil)
        #expect(count == 0)
    }
}
