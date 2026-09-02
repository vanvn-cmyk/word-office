import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Native `SearchablePDFRendering` — raw `CGContext` PDF generation (not
/// `UIGraphicsPDFRenderer`), so the coordinate space stays native bottom-left-origin
/// throughout. Vision's `OCRTextBlock.boundingBox` is already normalized in that
/// same origin (§6.4), so a block's text lands at the right position with a plain
/// scale — no Y-flip math to get wrong by mixing it with UIKit's auto-flipped
/// drawing context.
final class CGSearchablePDFRenderer: SearchablePDFRendering {
    func render(pages: [CGImage], results: [OCRResult], to destination: URL) async throws {
        guard !pages.isEmpty else { throw SearchablePDFRenderingError.emptyInput }
        let resultsByPage = Dictionary(uniqueKeysWithValues: results.map { ($0.pageIndex, $0) })

        try await Task.detached(priority: .utility) {
            guard let consumer = CGDataConsumer(url: destination as CFURL) else {
                throw SearchablePDFRenderingError.writeFailed
            }
            guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                throw SearchablePDFRenderingError.writeFailed
            }

            for (pageIndex, cgImage) in pages.enumerated() {
                let pageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
                let pageInfo = [kCGPDFContextMediaBox as String: NSValue(cgRect: pageRect)] as CFDictionary
                context.beginPDFPage(pageInfo)
                context.draw(cgImage, in: pageRect)
                if let result = resultsByPage[pageIndex] {
                    Self.drawInvisibleText(result.blocks, pageSize: pageRect.size, in: context)
                }
                context.endPDFPage()
            }
            context.closePDF()

            guard PDFDocument(url: destination) != nil else {
                throw SearchablePDFRenderingError.writeFailed
            }
        }.value
    }

    /// Draws each block's text at its bounding box, fully invisible — makes it
    /// selectable/searchable without changing what's visible underneath.
    private static func drawInvisibleText(_ blocks: [OCRTextBlock], pageSize: CGSize, in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for block in blocks where !block.text.isEmpty {
            let rect = CGRect(
                x: block.boundingBox.minX * pageSize.width,
                y: block.boundingBox.minY * pageSize.height,
                width: block.boundingBox.width * pageSize.width,
                height: block.boundingBox.height * pageSize.height
            )
            guard rect.height > 0 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.85, nil)
            let attributed = NSAttributedString(string: block.text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: rect.minX, y: rect.minY)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
