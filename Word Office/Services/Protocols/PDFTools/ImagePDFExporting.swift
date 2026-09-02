import Foundation
import UIKit

/// Combines images into a multi-page PDF, one image per page — native
/// (`UIGraphicsPDFRenderer`), independent of the Artifex SDK license.
/// See Phase0-Implementation-Logic-v2.md §7.4.
protocol ImagePDFExporting: Sendable {
    /// `images` in order = page order. Each page is sized to its own image
    /// (no forced common page size, no auto-crop/rotate).
    func exportPDF(from images: [UIImage], to destination: URL) async throws
}

enum ImagePDFExportError: Error, Sendable, LocalizedError {
    case emptyInput
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Add at least one photo to combine into a PDF"
        case .encodingFailed:
            "Couldn't read one of the selected photos"
        case .writeFailed:
            "Couldn't write the combined PDF"
        }
    }
}
