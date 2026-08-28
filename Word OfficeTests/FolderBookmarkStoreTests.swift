import Foundation
import Testing
@testable import Word_Office

/// Unit tests for `FolderBookmarkStore` (Keychain-backed).
/// Each test uses a UUID-suffixed service so tests never share Keychain entries —
/// safe under parallel execution, and orphan entries from crashes stay bounded.
/// `resolve(_:)` with a real security-scoped bookmark can't be exercised at the
/// unit level (needs a real picker interaction) — those paths live in integration.
@Suite("FolderBookmarkStore")
struct FolderBookmarkStoreTests {
    let store: FolderBookmarkStore
    let service: String

    init() {
        self.service = "test.wordoffice.\(UUID().uuidString)"
        self.store = FolderBookmarkStore(service: service, account: "primary")
    }

    // MARK: - Round-trip

    @Test("save then load returns identical bookmark")
    func saveAndLoadRoundTrip() throws {
        let bookmark = FolderBookmark(
            bookmarkData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            displayPath: "iCloud Drive/Test",
            grantedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(bookmark)
        defer { try? store.delete() }

        let loaded = try #require(store.loadSaved())
        #expect(loaded.bookmarkData == bookmark.bookmarkData)
        #expect(loaded.displayPath == bookmark.displayPath)
        #expect(loaded.grantedAt == bookmark.grantedAt)
    }

    @Test("load returns nil when store is empty")
    func loadEmpty() {
        defer { try? store.delete() }
        #expect(store.loadSaved() == nil)
    }

    @Test("save overwrites existing entry")
    func saveOverwrites() throws {
        defer { try? store.delete() }
        let first = FolderBookmark(bookmarkData: Data([0x01]), displayPath: "/first")
        let second = FolderBookmark(bookmarkData: Data([0x02]), displayPath: "/second")

        try store.save(first)
        try store.save(second)

        let loaded = try #require(store.loadSaved())
        #expect(loaded.bookmarkData == Data([0x02]))
        #expect(loaded.displayPath == "/second")
    }

    // MARK: - Delete

    @Test("delete removes stored bookmark")
    func deleteRemoves() throws {
        try store.save(FolderBookmark(bookmarkData: Data([0x99]), displayPath: "/x"))
        try store.delete()

        #expect(store.loadSaved() == nil)
    }

    @Test("delete is idempotent — no error when nothing to delete")
    func deleteIdempotent() {
        // Both invocations must succeed even though the store starts empty.
        #expect(throws: Never.self) { try store.delete() }
        #expect(throws: Never.self) { try store.delete() }
    }

    // MARK: - Resolve

    @Test("resolve throws for corrupted bookmark data")
    func resolveCorruptedThrows() {
        let bogus = FolderBookmark(
            bookmarkData: Data([0xFF, 0xAA, 0x55, 0x00, 0xDE, 0xAD]),
            displayPath: "/corrupted"
        )
        // The store translates any URL-resolution failure into `.revoked` —
        // but `FolderBookmarkError` isn't Equatable (associated OSStatus case),
        // so we assert the type rather than the specific case here.
        #expect(throws: FolderBookmarkError.self) {
            _ = try store.resolve(bogus)
        }
    }
}
