import Foundation

/// Compress a single file into a `.zip` archive placed in `folder`.
///
/// The destination filename is `<stem>.zip` (extension stripped, per user
/// spec — cleaner than the Files.app `<name.ext>.zip` convention). Collision
/// resolution is the caller's responsibility so the destination folder can
/// pick its own scheme (`FileManager.nonConflictingURL` today).
protocol DocumentZipping: Sendable {
    /// - Returns: the URL of the newly-created `.zip` inside `folder`.
    /// - Throws: any I/O error from the underlying coordinator.
    func zip(_ url: URL, into folder: URL) async throws -> URL
}
