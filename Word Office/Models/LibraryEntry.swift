import Foundation

/// One row in the Library list. Joins the on-disk file (`DocumentRef`)
/// with its app-owned metadata (`DocumentMetadata`) and the ephemeral iCloud
/// download state emitted by the scanner. See Library-Architecture.md §3.
struct LibraryEntry: Identifiable, Hashable, Sendable {
    let document: DocumentRef
    var metadata: DocumentMetadata
    var downloadState: iCloudDownloadState

    /// `id` == `metadata.id` == `documentID` — stable, comparable across scans.
    var id: String { metadata.id }
}
