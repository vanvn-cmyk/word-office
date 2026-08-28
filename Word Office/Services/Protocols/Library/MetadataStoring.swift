import Foundation

/// CRUD + query for `DocumentMetadata` (status, remindAt, timestamps).
/// Backing store: SQLite via GRDB — file at `<App Group Container>/metadata.sqlite`
/// so `FilesProviderExtension` (Sprint 0.3) reads the same source.
/// Never writes into the source `.docx`/`.pdf` file — metadata is app-owned only.
protocol MetadataStoring: Sendable {
    func fetch(id: String) async throws -> DocumentMetadata?

    /// Insert if missing, update otherwise. Also used to bump `lastOpenedAt`/`lastModifiedAt`.
    func upsert(_ metadata: DocumentMetadata) async throws

    /// Batch fetch for library rendering (avoid N+1 queries).
    /// Missing ids in result → caller creates a default `.draft` metadata.
    func fetchMany(ids: [String]) async throws -> [String: DocumentMetadata]

    func delete(id: String) async throws

    /// Count of `status == .draft` — drives the badge on `LibraryView`.
    func draftCount() async throws -> Int

    /// documentIDs where `remindAt <= moment`, sorted by `remindAt` ascending.
    /// Consumed by `RemindScheduling` — kept here (not in a separate table) so
    /// the SQL query is a single indexed scan.
    func dueReminderIDs(before moment: Date) async throws -> [String]

    /// Test / preview helper — wipe all rows.
    func reset() async throws
}

enum MetadataStoreError: Error, Sendable, LocalizedError {
    case databaseOpenFailed(underlying: String)
    case migrationFailed(underlying: String)
    case queryFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let u): "Couldn't open the metadata database: \(u)"
        case .migrationFailed(let u):    "Data schema migration failed: \(u)"
        case .queryFailed(let u):        "Metadata query failed: \(u)"
        }
    }
}
