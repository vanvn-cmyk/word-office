import Foundation

/// Extracts text from a PDF — reads the embedded text layer directly when present,
/// falls back to on-device OCR per page when absent (a scanned PDF, no text layer).
/// See Phase0-Implementation-Logic-v2.md §7.4 "PDF → Word".
protocol PDFTextExtracting: Sendable {
    /// `true` when none of the PDF's pages carry a real text layer — the caller
    /// should show the "will run OCR, may take longer" notice before extracting.
    func needsOCR(_ url: URL) async throws -> Bool

    /// Extracted text, page breaks joined with a blank line. Internally re-checks
    /// `needsOCR` to pick the direct-read vs. OCR-fallback path.
    func extractText(from url: URL, languages: [String]) async throws -> String
}

enum PDFTextExtractingError: Error, Sendable, LocalizedError {
    case unreadableDocument

    var errorDescription: String? {
        switch self {
        case .unreadableDocument:
            "Couldn't open the PDF — it may be corrupted or password-protected"
        }
    }
}
