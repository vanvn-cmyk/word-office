// Session 12 (2026-09-04) — Fill Form free-text overlay (Option B,
// Adobe Fill & Sign pattern). NOT in Phase0-Impl-v2 spec — user
// requested as a Session 12 addition.
//
// Option A (AcroForm auto-detect widget fields) deferred: many
// real-world forms are scanned PDFs with no form fields, so free-text
// covers the broader user need first.

import CoreGraphics
import Foundation

/// A user-added text annotation on a specific page of a PDF. Position
/// is stored in the source PDF's page coordinate space (bottom-left
/// origin), so it survives page rotation/scaling by PDFView between
/// capture and save.
///
/// Font size is a fixed default for MVP — a font-size chip UI is called
/// out in the mockup as "later" work.
struct TextAnnotation: Identifiable, Sendable, Hashable {
    let id: UUID
    let pageIndex: Int
    /// Rect in PDF page coords (bottom-left origin, mediaBox space).
    /// `var` so drag-to-reposition can update in place — new rect is
    /// computed from the drag translation via `PDFView.convert(_:to:)`
    /// at drag-end (see `TextAnnotationOverlay` in `FillFormView`).
    var pageRect: CGRect
    var text: String
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        pageRect: CGRect,
        text: String,
        fontSize: CGFloat = 14
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.pageRect = pageRect
        self.text = text
        self.fontSize = fontSize
    }
}
