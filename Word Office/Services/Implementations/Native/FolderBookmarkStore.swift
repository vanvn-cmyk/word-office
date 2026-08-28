import Foundation
import Security

/// Keychain-backed store for the single `FolderBookmark` granting library access.
/// Survives app uninstall (Keychain lives independently), encrypted at rest.
/// See Phase0-Implementation-Logic-v2.md §4.1 + Library-Architecture.md §2.
///
/// One bookmark per app: single (service, account) pair. If the user re-picks
/// a different folder, `save(_:)` overwrites the previous entry.
final class FolderBookmarkStore: FolderBookmarkResolving {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "com.wordoffice.folderBookmarks",
         account: String = "primary") {
        self.service = service
        self.account = account
    }

    // MARK: - FolderBookmarkResolving

    func loadSaved() -> FolderBookmark? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? decoder.decode(FolderBookmark.self, from: data)
    }

    func resolve(_ bookmark: FolderBookmark) throws -> URL {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw FolderBookmarkError.revoked
        }

        // Verify accessible right now — a resolvable bookmark can still be revoked.
        guard url.startAccessingSecurityScopedResource() else {
            throw FolderBookmarkError.revoked
        }
        url.stopAccessingSecurityScopedResource()

        // Best-effort refresh — a failed refresh does NOT invalidate this session's url.
        if isStale {
            _ = try? refresh(url: url, previous: bookmark)
        }
        return url
    }

    func save(_ bookmark: FolderBookmark) throws {
        let data = try encoder.encode(bookmark)
        let query = baseQuery()
        let updateAttributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw FolderBookmarkError.keychainFailure(addStatus)
            }
        default:
            throw FolderBookmarkError.keychainFailure(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FolderBookmarkError.keychainFailure(status)
        }
    }

    // MARK: - Helpers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func refresh(url: URL, previous: FolderBookmark) throws {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let newData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let refreshed = FolderBookmark(
            bookmarkData: newData,
            displayPath: previous.displayPath,
            grantedAt: previous.grantedAt
        )
        try save(refreshed)
    }
}
