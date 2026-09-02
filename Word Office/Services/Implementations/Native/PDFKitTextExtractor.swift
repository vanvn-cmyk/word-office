import Foundation
import PDFKit
import UIKit  // PDFPage.thumbnail(of:for:) returns UIImage

/// Native `PDFTextExtracting` — direct read via `PDFKit` when the PDF has a text
/// layer, OCR fallback (reusing the same `TextRecognizing` pipeline as camera/Photos
/// scan input) when it doesn't. See Phase0-Implementation-Logic-v2.md §7.4.
final class PDFKitTextExtractor: PDFTextExtracting {
    private let recognizer: any TextRecognizing

    init(recognizer: any TextRecognizing) {
        self.recognizer = recognizer
    }

    /// `true` when at least one page lacks a text layer — a mixed PDF (e.g. a
    /// scanned signature page appended to an otherwise-text document) still
    /// needs OCR for that page, so this checks "any", not "all" (§7.4).
    func needsOCR(_ url: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            guard let document = PDFDocument(url: url) else {
                throw PDFTextExtractingError.unreadableDocument
            }
            for pageIndex in 0..<document.pageCount {
                let text = document.page(at: pageIndex)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text?.isEmpty ?? true { return true }
            }
            return false
        }.value
    }

    /// Decides direct-read vs. OCR **per page**, not once for the whole document —
    /// a mixed PDF (most pages have text, one scanned page doesn't) must still get
    /// that one page OCR'd rather than silently dropped.
    func extractText(from url: URL, languages: [String]) async throws -> String {
        // `document` is opened fresh inside the detached task (not captured from
        // outside) — `PDFDocument` isn't Sendable, so it must never cross the
        // actor boundary; only the recognizer (declared `Sendable`) is captured.
        try await Task.detached(priority: .utility) { [recognizer] in
            guard let document = PDFDocument(url: url) else {
                throw PDFTextExtractingError.unreadableDocument
            }

            var text = ""
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let pageText, !pageText.isEmpty {
                    text += pageText + "\n\n"
                } else {
                    // No text layer on this page — render it to an image and run
                    // it through the exact same OCR pipeline as camera/Photos input.
                    let pageBounds = page.bounds(for: .mediaBox)
                    let scale: CGFloat = 2
                    let targetSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
                    guard let cgImage = page.thumbnail(of: targetSize, for: .mediaBox).cgImage else { continue }
                    let result = try await recognizer.recognize(in: cgImage, pageIndex: pageIndex, languages: languages)
                    text += result.fullText + "\n\n"
                }
            }
            return text
        }.value
    }
}
