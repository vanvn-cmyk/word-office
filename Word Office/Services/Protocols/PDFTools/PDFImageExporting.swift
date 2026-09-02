import Foundation

/// Exports PDF pages as PNG images — native (`PDFKit`), independent of the Artifex
/// SDK license. See Phase0-Implementation-Logic-v2.md §7.4.
protocol PDFImageExporting: Sendable {
    /// Exports `pageRange` (0-based, inclusive; `nil` = every page) from `url` as
    /// one PNG per page, written into `directory`. Returns the created file URLs
    /// in page order.
    func exportImages(from url: URL, pageRange: ClosedRange<Int>?, into directory: URL) async throws -> [URL]
}

enum PDFImageExportError: Error, Sendable, LocalizedError {
    case unreadableDocument
    case rangeOutOfBounds(ClosedRange<Int>, pageCount: Int)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableDocument:
            "Couldn't open the PDF — it may be corrupted or password-protected"
        case .rangeOutOfBounds(let range, let pageCount):
            "Range \(range.lowerBound + 1)–\(range.upperBound + 1) is out of bounds (document has \(pageCount) pages)"
        case .writeFailed:
            "Couldn't write the exported image"
        }
    }
}
