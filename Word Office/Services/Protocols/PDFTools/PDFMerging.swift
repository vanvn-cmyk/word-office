import Foundation

/// Merge multiple PDFs into one, page order = input order — native (`PDFKit`),
/// independent of the Artifex SDK license. See Phase0-Implementation-Logic-v2.md §7.1.
protocol PDFMerging: Sendable {
    /// Merge `urls` in order into one PDF written to `destination`.
    func merge(_ urls: [URL], into destination: URL) async throws
}

enum PDFMergeError: Error, Sendable, LocalizedError {
    case emptyInput
    case unreadableDocument(URL)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Select at least one PDF to merge"
        case .unreadableDocument(let url):
            "Couldn't open \"\(url.lastPathComponent)\" — the file may be corrupted or password-protected"
        case .writeFailed:
            "Couldn't write the merged PDF"
        }
    }
}
