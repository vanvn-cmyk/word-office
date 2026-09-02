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
        let folderPath = folderURL.resolvingSymlinksInPath().path
        let selfPath = resolvingSymlinksInPath().path
        let relative = selfPath.hasPrefix(folderPath)
            ? String(selfPath.dropFirst(folderPath.count))
            : selfPath
        // Hash `folderPath` too, not just `relative` — `loadLibrary()` calls this
        // once per source folder (the granted folder, then the sandbox
        // `Documents/`, per its dual-source scan). Hashing only the relative
        // suffix means a same-named file at the same relative position under
        // two different source folders (e.g. both happen to have a root-level
        // "Notes.docx") produces an identical ID, so `mergeSecondSource` treats
        // one as a duplicate of the other and metadata gets applied to the
        // wrong physical file.
        let digest = SHA256.hash(data: Data((folderPath + "\u{0}" + relative).utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
