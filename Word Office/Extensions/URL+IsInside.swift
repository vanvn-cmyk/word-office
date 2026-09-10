import Foundation

extension URL {
    /// True when the receiver lives inside `container` on disk. Compares
    /// **path components** (not raw `path.hasPrefix`) so a sibling
    /// directory whose name starts with the container's last path
    /// component doesn't false-positive its way in:
    ///
    ///     "/…/Documents-Backup/foo.pdf".isInside(
    ///         URL(fileURLWithPath: "/…/Documents"))
    ///     // → false  (was: `true` under `path.hasPrefix`, which is what
    ///     //  code-review #5 flagged as a destructive-Replace safety-gate
    ///     //  bypass in `SignatureViewModel.canReplaceSourceInPlace` and
    ///     //  its mirror in `FillFormViewModel` /
    ///     //  `LocalPreviewCommitter`.)
    ///
    /// Both URLs are `standardizedFileURL`-normalised first so `/private`
    /// vs `/var` symlink differences (the app's temporary directory sits
    /// under `/private/var/…` while `documentsURL` resolves to `/var/…`
    /// or vice-versa depending on how it was constructed) don't false-
    /// negative genuinely-inside paths.
    ///
    /// A URL is NOT considered inside itself — `container.isInside(container)`
    /// returns `false`. Matches the reading callers want ("a file inside
    /// the folder", not "a folder inside itself").
    func isInside(_ container: URL) -> Bool {
        let target = standardizedFileURL.pathComponents
        let root = container.standardizedFileURL.pathComponents
        guard target.count > root.count else { return false }
        return Array(target.prefix(root.count)) == root
    }
}
