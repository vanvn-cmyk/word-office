import Foundation

/// Scans the granted folder for supported document files.
/// See Phase0-Implementation-Logic-v2.md §4.1–4.2 + Library-Architecture.md §4 scenario 3.
///
/// Design intent:
/// - UTI filter (via `DocumentKind.fromUTI`), not extension — file renamed to `.foo` still classified.
/// - Non-blocking on iCloud placeholders: entries are returned immediately with
///   `.notDownloaded`; the caller (`LibraryViewModel`) kicks off downloads and
///   updates state as they complete. Never wait in-scan.
/// - Caller owns security-scoped access — this scanner assumes the folder URL is already accessible.
final class DocumentLibraryScanner: DocumentLibraryScanning {
    private let fileManager = FileManager.default

    func scan(folder: URL) async -> [LibraryScanEntry] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> LibraryScanEntry? in
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true,
                let kind = DocumentKind.fromUTI(url: url)
            else {
                return nil
            }

            let ref = DocumentRef(
                name: url.lastPathComponent,
                url: url,
                modifiedAt: values.contentModificationDate ?? Date(),
                kind: kind
            )
            return LibraryScanEntry(document: ref, downloadState: Self.downloadState(from: values))
        }
    }

    // MARK: - iCloud state mapping

    /// URL resource values report status only (not progress %). Progress tracking
    /// belongs to a higher layer via `NSMetadataQuery` if needed — kept out here
    /// to keep the scan pass cheap.
    private static func downloadState(from values: URLResourceValues) -> iCloudDownloadState {
        guard values.isUbiquitousItem == true else { return .local }
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return .local
        case .notDownloaded:
            return .notDownloaded
        default:
            return .notDownloaded
        }
    }
}
