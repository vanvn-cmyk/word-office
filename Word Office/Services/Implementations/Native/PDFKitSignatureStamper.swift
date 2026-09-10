// Session 12 (2026-09-04) — PDF signature stamper via CGPDFContext.
//
// Chose the CGPDFContext re-render approach over `PDFAnnotation.stamp`
// with a subclassed `draw(with:in:)` for a specific reason: the
// annotation subclass approach works in `PDFView` (display) but the
// bitmap doesn't persist reliably into an appearance stream when
// `PDFDocument.write(to:)` serialises — third-party viewers (Preview,
// Acrobat) then show the stamp as an empty box. Re-rendering every page
// through `CGPDFContext` and drawing the CGImage inline guarantees the
// bytes are baked into the output file's page content, viewer-agnostic.
//
// Trade-off: entire PDF is re-rendered even when only one page changes.
// For MVP-scale files (contracts <50 pages) this is imperceptible on
// modern hardware. If the tool ever handles hundreds-of-pages inputs,
// revisit and stream unchanged pages via `CGPDFDocument`+`CGPDFPage`
// direct dictionary copy instead of `page.draw(...)`.

import CoreGraphics
import Foundation
import PDFKit
import UIKit

actor PDFKitSignatureStamper: SignatureStamping {
    func stamp(
        _ signature: Signature,
        on sourceURL: URL,
        pageIndex: Int,
        pageRect: CGRect,
        into destinationDirectory: URL
    ) async throws -> URL {
        // Session 19 code-review #4 — security-scope claim required
        // on the external picker URL. See mirror block in
        // `PDFKitFormFiller.fill` for the full rationale.
        let didStartScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: sourceURL) else {
            throw SignatureStampingError.cannotOpenPDF
        }
        let pageCount = document.pageCount
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw SignatureStampingError.pageIndexOutOfRange(pageIndex, pageCount: pageCount)
        }
        guard let uiImage = UIImage(data: signature.imageData), let cgImage = uiImage.cgImage else {
            throw SignatureStampingError.invalidImageData
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let destination = FileManager.default.nonConflictingURL(
            for: "\(stem) signed.pdf",
            in: destinationDirectory
        )

        // First-page media box is the initial `mediaBox` for `CGContext(url:mediaBox:)`
        // — subsequent pages call `beginPage(mediaBox:)` with their own box, so
        // per-page varying page sizes are preserved.
        guard let firstPage = document.page(at: 0) else {
            throw SignatureStampingError.cannotOpenPDF
        }
        var initialMediaBox = firstPage.bounds(for: .mediaBox)
        guard let context = CGContext(destination as CFURL, mediaBox: &initialMediaBox, nil) else {
            throw SignatureStampingError.contextCreationFailed
        }

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            var box = page.bounds(for: .mediaBox)
            context.beginPage(mediaBox: &box)
            // Draw the original page. `PDFPage.draw(with:to:)` handles the
            // Y-axis convention internally — CGPDFContext is bottom-left origin
            // and PDFKit renders correctly into it without extra transform.
            page.draw(with: .mediaBox, to: context)
            // Overlay signature only on the target page. Aspect-fit within
            // `pageRect` rather than stretching to fill it — the SwiftUI
            // placement preview (`SignPDFCanvas.signatureOverlay`) shows
            // the signature aspect-fit inside that same rect, so a plain
            // `context.draw(cgImage, in: pageRect)` (which always stretches
            // to fill) would bake a visibly squished/stretched signature
            // into the saved PDF that doesn't match what the user saw.
            if index == pageIndex {
                context.draw(cgImage, in: Self.aspectFitRect(imageSize: CGSize(width: cgImage.width, height: cgImage.height), in: pageRect))
            }
            context.endPage()
        }
        context.closePDF()

        // Sanity check — CGPDFContext writes are non-throwing, so verify the
        // file exists before handing the URL back to the caller.
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw SignatureStampingError.writeFailed("Output file missing after write")
        }
        return destination
    }

    /// Largest rect matching `imageSize`'s aspect ratio that fits centered
    /// inside `rect` — the `CGContext.draw(_:in:)` equivalent of SwiftUI's
    /// `.aspectRatio(contentMode: .fit)`, which draws directly stretch-to-fill.
    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let imageAspect = imageSize.width / imageSize.height
        let rectAspect = rect.width / rect.height
        if imageAspect > rectAspect {
            let height = rect.width / imageAspect
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        } else {
            let width = rect.height * imageAspect
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
    }
}
