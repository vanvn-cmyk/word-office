// Session 12 (2026-09-04) — form-filler via `PDFAnnotation.freeText`.
//
// Uses PDFAnnotation instead of CGPDFContext re-render (the approach
// SignatureStamper uses) because free-text annotations DO persist
// reliably through `PDFDocument.write(to:)`: PDFKit serialises them
// into the file's annotation dictionary + generates an appearance
// stream automatically. That saves us from re-rendering every page
// just to add a few text overlays.

import CoreGraphics
import Foundation
import PDFKit
import UIKit

actor PDFKitFormFiller: FormFilling {
    func fill(
        _ annotations: [TextAnnotation],
        on sourceURL: URL,
        into destinationDirectory: URL
    ) async throws -> URL {
        // Session 19 code-review #4 — security-scope claim on the
        // external picker URL survives to this actor via `sourceURL`;
        // the picker's transient grant does NOT survive the multi-hop
        // trip through `FillFormView.handleFilePicked` → `Task { await
        // viewModel.stagePreview }` → this actor. Without the claim,
        // `PDFDocument(url:)` returns nil for any iCloud / third-party
        // provider file and the caller throws `.cannotOpenPDF` with no
        // clue why. Matches the wrap `DocumentImporter.importOne`
        // already applies on the same shape of URL.
        let didStartScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: sourceURL) else {
            throw FormFillingError.cannotOpenPDF
        }

        for annotation in annotations {
            guard annotation.pageIndex >= 0,
                  annotation.pageIndex < document.pageCount,
                  let page = document.page(at: annotation.pageIndex)
            else { continue }
            let pdfAnnotation = PDFAnnotation(
                bounds: annotation.pageRect,
                forType: .freeText,
                withProperties: nil
            )
            pdfAnnotation.contents = annotation.text
            pdfAnnotation.font = UIFont.systemFont(ofSize: annotation.fontSize)
            // `UIColor.black`, NOT `.label` — `.label` is a dynamic color that
            // resolves against the CURRENT trait collection at draw time.
            // A user in dark mode fills a form and taps Save → `.label`
            // resolves to near-white → PDFKit bakes near-white into the
            // annotation's appearance stream. The file then renders as
            // empty on any white PDF paper (Preview, Acrobat, sharing to
            // someone on light mode). Filled forms are printer/PDF-viewer
            // artifacts, not app-theme content — a fixed dark ink is the
            // only safe choice.
            pdfAnnotation.fontColor = .black
            // Transparent background — the source PDF's own content shows
            // through (form underline, ruled paper). A solid color here
            // would occlude whatever was under the text field.
            pdfAnnotation.color = .clear
            // Remove PDFKit's default 1pt annotation border — otherwise
            // every filled field renders with a visible frame on
            // third-party viewers like Preview.
            let border = PDFBorder()
            border.lineWidth = 0
            pdfAnnotation.border = border
            page.addAnnotation(pdfAnnotation)
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let destination = FileManager.default.nonConflictingURL(
            for: "\(stem) filled.pdf",
            in: destinationDirectory
        )

        // `PDFDocument.write(to:)` returns Bool. False = write failed,
        // no error detail — the best we can do is a generic message.
        guard document.write(to: destination) else {
            throw FormFillingError.writeFailed("PDFDocument.write returned false")
        }
        return destination
    }
}
