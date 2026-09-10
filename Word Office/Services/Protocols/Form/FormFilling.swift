// Session 12 (2026-09-04) — embed text annotations into a PDF and
// write the filled copy. Native via `PDFAnnotation(bounds:forType:.freeText)`.

import CoreGraphics
import Foundation

protocol FormFilling: Sendable {
    /// Embed `annotations` onto their respective pages of `sourceURL`,
    /// write the result into `destinationDirectory` under a
    /// non-conflicting `<stem> filled.pdf` name, and return the new URL.
    ///
    /// Runs off the caller's actor. Empty `annotations` still writes a
    /// copy (idempotent) — no special "nothing changed" branch, since
    /// the caller already gates Save on non-empty state.
    func fill(
        _ annotations: [TextAnnotation],
        on sourceURL: URL,
        into destinationDirectory: URL
    ) async throws -> URL
}

enum FormFillingError: Error, LocalizedError {
    case cannotOpenPDF
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:        "Could not open the PDF"
        case .writeFailed(let msg): "Could not save the filled PDF: \(msg)"
        }
    }
}
