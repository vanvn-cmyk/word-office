// Session 12 (2026-09-04) — stamp a drawn signature onto a PDF page and
// write the result to disk. Native (no Artifex SDK) — see impl
// `PDFKitSignatureStamper` for the CGPDFContext re-render approach.
//
// Not `SignatureDrawing` (which was the pre-existing scaffold stub for
// the PencilKit canvas bridge — that's just SwiftUI wrapping now, no
// protocol needed). This one is the PDF-write side, which IS testable
// IO worth abstracting.

import CoreGraphics
import Foundation

protocol SignatureStamping: Sendable {
    /// Embed `signature` on page `pageIndex` (0-based) of `sourceURL` at
    /// `pageRect` (PDF coordinate space of that page's mediaBox, bottom-
    /// left origin), write the result into `destinationDirectory` under a
    /// non-conflicting `<stem> signed.pdf` name, and return the new URL.
    ///
    /// Runs off the caller's actor — same pattern as `PDFKitMerger` and
    /// `PDFKitSplitter`, since re-rendering every page through a
    /// `CGPDFContext` is not instant for large PDFs.
    func stamp(
        _ signature: Signature,
        on sourceURL: URL,
        pageIndex: Int,
        pageRect: CGRect,
        into destinationDirectory: URL
    ) async throws -> URL
}

enum SignatureStampingError: Error, LocalizedError {
    case cannotOpenPDF
    case pageIndexOutOfRange(Int, pageCount: Int)
    case invalidImageData
    case contextCreationFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:                    "Could not open the PDF"
        case .pageIndexOutOfRange(let i, let n): "Page \(i + 1) doesn't exist — this PDF has \(n) pages"
        case .invalidImageData:                 "Signature image is corrupted"
        case .contextCreationFailed:            "Could not create the output PDF"
        case .writeFailed(let msg):             "Could not save the signed PDF: \(msg)"
        }
    }
}
