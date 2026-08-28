// Requires GRDB.swift SPM package.
// Xcode → File → Add Package Dependencies → https://github.com/groue/GRDB.swift → stable 6.x

import Foundation
import GRDB

/// SQLite-backed `MetadataStoring` via GRDB. See Library-Architecture.md §2 + §6.
///
/// Storage path: pass in the SQLite file URL — production goes to the App Group
/// container (`group.com.wordoffice.app`) so `FilesProviderExtension` (Sprint 0.3)
/// reads the same DB. Until App Group entitlement is set (A6, waiting for Bundle ID +
/// Team ID), init with a sandbox path — see `MetadataStoreLocator` for the
/// FIXME switch site.
///
/// Concurrency: GRDB `DatabaseQueue` serializes writes internally; safe to call
/// concurrently from any actor.
final class MetadataStoreImpl: MetadataStoring {
    private let dbQueue: DatabaseQueue

    init(databaseURL: URL) throws {
        do {
            var config = Configuration()
            config.label = "wordoffice.metadata"
            self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        } catch {
            throw MetadataStoreError.databaseOpenFailed(underlying: error.localizedDescription)
        }
        do {
            try Self.runMigrations(on: dbQueue)
        } catch {
            throw MetadataStoreError.migrationFailed(underlying: error.localizedDescription)
        }
    }

    // MARK: - Migrations

    private static func runMigrations(on db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_document_metadata") { db in
            try db.create(table: "document_metadata") { t in
                t.column("id", .text).primaryKey()
                t.column("status", .text).notNull()
                t.column("last_opened_at", .double).notNull()
                t.column("last_modified_at", .double).notNull()
                t.column("remind_at", .double)   // nullable
            }
            try db.create(
                index: "idx_metadata_status",
                on: "document_metadata",
                columns: ["status"]
            )
            try db.create(
                index: "idx_metadata_remind_at",
                on: "document_metadata",
                columns: ["remind_at"]
            )
        }

        try migrator.migrate(db)
    }

    // MARK: - MetadataStoring

    func fetch(id: String) async throws -> DocumentMetadata? {
        try await runRead { db in
            try Row.fetchOne(db, sql: "SELECT * FROM document_metadata WHERE id = ?", arguments: [id])
                .map(Self.decode)
        }
    }

    func upsert(_ metadata: DocumentMetadata) async throws {
        try await runWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO document_metadata
                        (id, status, last_opened_at, last_modified_at, remind_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        status           = excluded.status,
                        last_opened_at   = excluded.last_opened_at,
                        last_modified_at = excluded.last_modified_at,
                        remind_at        = excluded.remind_at
                    """,
                arguments: [
                    metadata.id,
                    metadata.status.rawValue,
                    metadata.lastOpenedAt.timeIntervalSince1970,
                    metadata.lastModifiedAt.timeIntervalSince1970,
                    metadata.remindAt?.timeIntervalSince1970
                ]
            )
        }
    }

    func fetchMany(ids: [String]) async throws -> [String: DocumentMetadata] {
        guard !ids.isEmpty else { return [:] }
        return try await runRead { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = "SELECT * FROM document_metadata WHERE id IN (\(placeholders))"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids))
            var result: [String: DocumentMetadata] = [:]
            for row in rows {
                let metadata = Self.decode(from: row)
                result[metadata.id] = metadata
            }
            return result
        }
    }

    func delete(id: String) async throws {
        try await runWrite { db in
            try db.execute(sql: "DELETE FROM document_metadata WHERE id = ?", arguments: [id])
        }
    }

    func draftCount() async throws -> Int {
        try await runRead { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM document_metadata WHERE status = ?",
                arguments: [DocumentStatus.draft.rawValue]
            ) ?? 0
        }
    }

    func dueReminderIDs(before moment: Date) async throws -> [String] {
        try await runRead { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM document_metadata
                    WHERE remind_at IS NOT NULL AND remind_at <= ?
                    ORDER BY remind_at ASC
                    """,
                arguments: [moment.timeIntervalSince1970]
            )
        }
    }

    func reset() async throws {
        try await runWrite { db in
            try db.execute(sql: "DELETE FROM document_metadata")
        }
    }

    // MARK: - GRDB → Model mapping

    /// `nonisolated` because it's called from GRDB read closures which run off the
    /// main actor. Project default actor isolation is `MainActor`, so without this
    /// the compiler treats `Self.decode` as main-actor-isolated and rejects the call.
    nonisolated private static func decode(from row: Row) -> DocumentMetadata {
        DocumentMetadata(
            id: row["id"],
            status: DocumentStatus(rawValue: row["status"]) ?? .draft,
            lastOpenedAt: Date(timeIntervalSince1970: row["last_opened_at"]),
            lastModifiedAt: Date(timeIntervalSince1970: row["last_modified_at"]),
            remindAt: (row["remind_at"] as TimeInterval?).map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - Async wrappers with error translation

    private func runRead<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        do {
            return try await dbQueue.read(block)
        } catch {
            throw MetadataStoreError.queryFailed(underlying: error.localizedDescription)
        }
    }

    private func runWrite<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        do {
            return try await dbQueue.write(block)
        } catch {
            throw MetadataStoreError.queryFailed(underlying: error.localizedDescription)
        }
    }
}

// MARK: - Storage location

/// Resolves where `metadata.sqlite` lives. Single switch site — flip when
/// Bundle ID + Team ID land (A6 in arch v2.2) and App Group entitlement is added.
enum MetadataStoreLocator {
    /// Production: App Group container so FilesProviderExtension shares the DB.
    /// FIXME(A6): replace `groupIdentifier` with the real group ID once entitlement is configured.
    static let groupIdentifier = "group.com.wordoffice.app"

    static func resolveDatabaseURL() throws -> URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            return groupURL.appendingPathComponent("metadata.sqlite")
        }
        // Fallback: Application Support until App Group is provisioned.
        // Same-app-only during dev; Sprint 0.3 requires the App Group path.
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("metadata.sqlite")
    }
}
