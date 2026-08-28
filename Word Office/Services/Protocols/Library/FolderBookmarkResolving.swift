import Foundation

/// Persist + resolve the folder bookmark saved from `FolderPermissionGranting`.
/// Backing store: Keychain (SecItem) — survives app uninstall, encrypted at rest.
/// Must NOT use UserDefaults (backup-out-of-device risk).
protocol FolderBookmarkResolving: Sendable {
    /// Nil if the user has never granted a folder — caller should trigger onboarding.
    func loadSaved() -> FolderBookmark?

    /// Resolve bookmark data → live URL. Refreshes stored bookmark if `isStale`.
    /// Throws `.revoked` when the OS has revoked access (Settings → Privacy) —
    /// caller MUST surface `ReauthorizePermissionCTA` (never silent empty library).
    func resolve(_ bookmark: FolderBookmark) throws -> URL

    /// Overwrite the stored bookmark (used both after first grant and after `isStale` refresh).
    func save(_ bookmark: FolderBookmark) throws

    /// Explicit reset (user chooses "Change folder" in settings). Clears Keychain entry.
    func delete() throws
}

enum FolderBookmarkError: Error, Sendable, LocalizedError {
    case bookmarkStale
    case revoked
    case keychainFailure(OSStatus)
    case corruptedBookmark

    var errorDescription: String? {
        switch self {
        case .bookmarkStale:            "Folder access needs to be refreshed."
        case .revoked:                  "Folder access was revoked. Please re-grant."
        case .keychainFailure(let s):   "Keychain error (code \(s))."
        case .corruptedBookmark:        "The folder bookmark is corrupted — please re-grant access."
        }
    }
}
