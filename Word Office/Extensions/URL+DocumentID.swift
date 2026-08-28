import Foundation
import CryptoKit

extension URL {
    /// Stable identifier used as `DocumentMetadata.id` in the metadata store.
    /// See Library-Architecture.md §7 trap #1 for the trade-off + escalation trigger.
    ///
    /// - Primary path: APFS `documentIdentifierKey` — persistent across rename,
    ///   move within the volume, and edit. Only invalidated by delete + recreate.
    /// - Fallback path: SHA256 of the path relative to `folderURL` — stable across
    ///   relaunches but broken by rename/move (orphans the metadata row).
    ///
    /// Prefix (`d` or `p`) makes the ID source recognisable in the DB.
    func documentID(within folderURL: URL) -> String {
        if let identifier = try? resourceValues(forKeys: [.documentIdentifierKey]).documentIdentifier {
            return "d\(identifier)"
        }
        return "p\(relativePathDigest(from: folderURL))"
    }

    private func relativePathDigest(from folderURL: URL) -> String {
        let folderPath = folderURL.standardizedFileURL.path
        let selfPath = standardizedFileURL.path
        let relative = selfPath.hasPrefix(folderPath)
            ? String(selfPath.dropFirst(folderPath.count))
            : selfPath
        let digest = SHA256.hash(data: Data(relative.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
