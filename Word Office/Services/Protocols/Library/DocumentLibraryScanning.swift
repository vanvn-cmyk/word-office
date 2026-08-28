import Foundation

/// Scan the user-granted folder for supported document files.
/// - Filters by UTI (not by extension — `.docx` renamed to `.foo` still detected via UTI).
/// - Does NOT wait for iCloud placeholders to download (would block the whole list on a slow file);
///   returns entries with `downloadState = .downloading` and lets the caller kick off async download.
/// - Does NOT read file contents (metadata + UTI only, keep scan cheap).
protocol DocumentLibraryScanning: Sendable {
    func scan(folder: URL) async -> [LibraryScanEntry]
}

/// One entry produced by the scanner. `document` carries the addressable file;
/// `downloadState` is ephemeral (not persisted to `MetadataStoring`).
struct LibraryScanEntry: Hashable, Sendable {
    let document: DocumentRef
    var downloadState: iCloudDownloadState

    init(document: DocumentRef, downloadState: iCloudDownloadState = .local) {
        self.document = document
        self.downloadState = downloadState
    }
}

enum iCloudDownloadState: Hashable, Sendable {
    case local                       // File on-disk, ready to open
    case downloading(progress: Double)   // 0.0…1.0 — placeholder being fetched
    case notDownloaded               // Placeholder, download not yet started
    case failed(reason: String)      // Surfaced in UI but keeps entry visible
}
