import CoreGraphics
import Foundation

/// Wraps recognized OCR text as an invisible, searchable text layer over the
/// original scanned image — visually identical to the source image, but the text
/// is selectable/searchable/copyable. Secondary/optional OCR output, alongside
/// the primary editable-.docx output. See Phase0-Implementation-Logic-v2.md §6.5.
protocol SearchablePDFRendering: Sendable {
    /// `pages[i]` is the source image for `results` entries whose `pageIndex == i`.
    func render(pages: [CGImage], results: [OCRResult], to destination: URL) async throws
}

enum SearchablePDFRenderingError: Error, Sendable, LocalizedError {
    case emptyInput
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "No pages to export"
        case .writeFailed:
            "Couldn't write the searchable PDF"
        }
    }
}
