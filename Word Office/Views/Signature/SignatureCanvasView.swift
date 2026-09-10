// Session 12 (2026-09-04) — PencilKit canvas wrapped for SwiftUI.
// Ink-only (no marker/pencil), single black colour for MVP — the point
// is a signature, not a drawing surface. Additional tool/colour options
// can layer on later without changing the export contract.

import PencilKit
import SwiftUI
import UIKit

struct SignatureCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawing = drawing
        // `.anyInput` — finger AND Apple Pencil both draw. Default is
        // pencil-only on iPad, which would silently reject a finger tap
        // and read as "canvas is broken" for non-Pencil users.
        view.drawingPolicy = .anyInput
        // `.black` — hardcoded, NOT `.label`. `.label` resolves to
        // near-white in Dark Mode, and `PKDrawing.pngData` bakes the
        // resolved colour into the exported PNG; that PNG is then
        // composited onto a white PDF page by `PDFKitSignatureStamper`,
        // making the signature invisible in the saved file (silent data
        // loss — the toast says "Signed" but the file is broken).
        // Signatures are ink; ink is black regardless of app theme.
        // Session 19 code-review #3 fix. Same PDFKit annotation-colour
        // reality already documented for text fill in `PDFKitFormFiller`.
        view.tool = PKInkingTool(.pen, color: .black, width: 4)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // One-way flow — SwiftUI drives clear-canvas via binding reset
        // to empty `PKDrawing`. Never sync UIView.drawing → binding here
        // (that path lives in the delegate) to avoid re-entrant updates.
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

extension PKDrawing {
    /// Renders the drawing to a transparent-background PNG. Uses the
    /// drawing's `bounds` (tight around actual strokes) so the exported
    /// image doesn't carry blank canvas whitespace — that lets the
    /// placement UI size the signature naturally without user-visible
    /// padding around the strokes.
    func pngData(scale: CGFloat = 2.0) -> Data? {
        let strokeBounds = bounds
        guard !strokeBounds.isEmpty, !strokeBounds.isNull else { return nil }
        let image = image(from: strokeBounds, scale: scale)
        return image.pngData()
    }
}
