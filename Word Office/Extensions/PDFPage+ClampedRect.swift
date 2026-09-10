import PDFKit

extension PDFPage {
    /// Clamps `rect` (PDF page coordinate space, bottom-left origin) so it
    /// stays fully inside this page's `mediaBox`. Used before handing a
    /// tap- or drag-derived placement rect (signature stamp, fill-form text
    /// annotation) to a PDF writer: `CGPDFContext`/`PDFAnnotation` drawing
    /// is clipped to the media box, so an unclamped rect near an edge
    /// silently crops or drops content with no error surfaced.
    func clampedToMediaBox(_ rect: CGRect) -> CGRect {
        let bounds = bounds(for: .mediaBox)
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
