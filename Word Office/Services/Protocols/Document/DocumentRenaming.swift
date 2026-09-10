import Foundation

/// Rename a file in place — moves it within the same directory to a new
/// filename. The destination filename must include its extension; callers
/// (Library kebab menu today, picker rows later) that only let the user
/// edit the stem re-attach the original extension before calling.
///
/// Throws when the destination already exists — callers surface that as
/// a "Name already exists" toast rather than silently auto-suffixing;
/// see `LibraryViewModel.rename` for the Library-side handling.
protocol DocumentRenaming: Sendable {
    /// - Returns: the new URL after the move.
    /// - Throws: any `FileManager` error (collision, permission, missing source).
    func rename(_ url: URL, to newFilename: String) async throws -> URL
}
