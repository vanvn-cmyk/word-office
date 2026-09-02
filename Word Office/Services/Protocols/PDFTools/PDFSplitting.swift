import Foundation

/// Split a PDF into multiple files by page range — native (`PDFKit`), independent
/// of the Artifex SDK license. See Phase0-Implementation-Logic-v2.md §7.1.
protocol PDFSplitting: Sendable {
    /// Split `url` into one output file per range in `ranges` (0-based page indices,
    /// inclusive), written into `directory`. Returns the created file URLs in range order.
    func split(_ url: URL, ranges: [ClosedRange<Int>], into directory: URL) async throws -> [URL]
}

enum PDFSplitError: Error, Sendable, LocalizedError {
    case unreadableDocument
    case emptyRanges
    case rangeOutOfBounds(ClosedRange<Int>, pageCount: Int)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableDocument:
            "Couldn't open the PDF — it may be corrupted or password-protected"
        case .emptyRanges:
            "Select at least one page range to split"
        case .rangeOutOfBounds(let range, let pageCount):
            "Range \(range.lowerBound + 1)–\(range.upperBound + 1) is out of bounds (document has \(pageCount) pages)"
        case .writeFailed:
            "Couldn't write the split PDF"
        }
    }
}
