// Session 12 (2026-09-04, revision 2) — Sign PDF canvas: PDFView
// wrapped for SwiftUI + tap-to-place gesture + committed signature
// overlay. Bottom sheet handles drawing (see `SignFlowView`).
//
// Same shape as `FillFormPDFView`/`FillFormPDFCanvas` — one gesture
// path, one overlay, same coord conversion helpers. Keeping the two
// PDF-canvas variants parallel makes the shared UX contract obvious.

import PDFKit
import SwiftUI
import UIKit

/// PDFView bridged to SwiftUI. Publishes the live `PDFView` back to
/// the parent (for coord conversion at commit time) and forwards
/// single-tap locations upward. Single-page-continuous scroll matches
/// FillFormPDFView so users get the same feel across Sign / Fill Form.
struct SignPDFView: UIViewRepresentable {
    /// Pre-loaded document from `SignatureViewModel.pdfDocument` — never
    /// parsed inside `makeUIView`, so the push animation into the fill
    /// stage stays smooth even on large scanned contracts (F8).
    let document: PDFDocument
    @Binding var pdfView: PDFView?
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .systemBackground
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.onTap = onTap
        DispatchQueue.main.async {
            pdfView = view
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?

        @objc func didTap(_ sender: UITapGestureRecognizer) {
            let location = sender.location(in: sender.view)
            onTap?(location)
        }

        // Let PDFView's own scroll/zoom recognisers run alongside — a
        // pure tap still comes through, but a tap-that-turned-into-scroll
        // is correctly ignored.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Composes `SignPDFView` with a signature-image overlay for the
/// currently-committed placement. Interactions:
/// - Tap on PDF (empty area): opens draw sheet (no signature yet) or
///   moves the existing signature to that spot.
/// - **Drag the signature**: continuous reposition — the visible bounds
///   follow the finger, and on release the parent's `onMoveViaDrag`
///   fires with the new PDF-page rect.
/// - Long-press the signature: clears bytes + placement.
struct SignPDFCanvas: View {
    let document: PDFDocument
    let signatureImage: UIImage?
    let placement: SignatureViewModel.Placement?
    let onTapPDF: (SignatureViewModel.Placement) -> Void
    /// Fires at drag-end with the new PDF-page-coord rect for the
    /// currently placed signature. Parent typically calls
    /// `SignatureViewModel.movePlacement(to:)`.
    let onMoveViaDrag: (SignatureViewModel.Placement) -> Void
    let onClearSignature: () -> Void

    @State private var pdfView: PDFView?
    /// Observable mirror of `pdfView.currentPage`'s index — see the twin
    /// state in `FillFormPDFCanvas` for the F7 rationale. Without this,
    /// `pdfView.currentPage`/`visiblePages` reads in `body` never re-run
    /// on scroll and the signature overlay's visibility guard uses stale
    /// values (overlay disappears or lingers on the wrong page).
    @State private var currentPageIndex: Int = 0
    /// Live drag translation in view coords — added on top of the
    /// committed placement's screen position while the finger is down.
    /// Reset to `.zero` on drag-end after the parent's move callback
    /// consumes the delta.
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { _ in
            ZStack {
                SignPDFView(document: document, pdfView: $pdfView) { locationInView in
                    handleTap(at: locationInView)
                }

                // Gate on `currentPageIndex` (state) not `pdfView
                // .currentPage` (UIKit property, not observable) so
                // SwiftUI re-runs body when the user scrolls to a
                // different page. Overlay reappears once they scroll
                // back to `placement.pageIndex`.
                if let signatureImage,
                   let placement,
                   let pdfView,
                   let document = pdfView.document,
                   placement.pageIndex < document.pageCount,
                   let page = document.page(at: placement.pageIndex),
                   placement.pageIndex == currentPageIndex {
                    signatureOverlay(image: signatureImage, placement: placement, pdfView: pdfView, page: page)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { note in
            guard let sender = note.object as? PDFView, sender === pdfView,
                  let page = sender.currentPage,
                  let doc = sender.document else { return }
            currentPageIndex = doc.index(for: page)
        }
    }

    private func handleTap(at locationInView: CGPoint) {
        guard let pdfView,
              let page = pdfView.page(for: locationInView, nearest: true),
              let document = pdfView.document
        else { return }
        let pageIndex = document.index(for: page)
        let pageOrigin = pdfView.convert(locationInView, to: page)
        let rect = page.clampedToMediaBox(CGRect(
            x: pageOrigin.x,
            y: pageOrigin.y - 60,
            width: 180,
            height: 60
        ))
        onTapPDF(SignatureViewModel.Placement(pageIndex: pageIndex, pageRect: rect))
    }

    @ViewBuilder
    private func signatureOverlay(
        image: UIImage,
        placement: SignatureViewModel.Placement,
        pdfView: PDFView,
        page: PDFPage
    ) -> some View {
        let topLeftInView = pdfView.convert(CGPoint(x: placement.pageRect.minX, y: placement.pageRect.maxY), from: page)
        let bottomRightInView = pdfView.convert(CGPoint(x: placement.pageRect.maxX, y: placement.pageRect.minY), from: page)
        let viewRect = CGRect(
            x: min(topLeftInView.x, bottomRightInView.x),
            y: min(topLeftInView.y, bottomRightInView.y),
            width: abs(bottomRightInView.x - topLeftInView.x),
            height: abs(bottomRightInView.y - topLeftInView.y)
        )
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: viewRect.width, height: viewRect.height)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.dsBrandPrimary, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .allowsHitTesting(false)
            )
            .position(
                x: viewRect.midX + dragTranslation.width,
                y: viewRect.midY + dragTranslation.height
            )
            .highPriorityGesture(dragGesture(pdfView: pdfView, page: page, currentViewRect: viewRect, placement: placement))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in onClearSignature() }
            )
            .accessibilityLabel("Signature — drag to move, long-press to clear")
    }

    /// Drag lives at `.highPriorityGesture` so PDFView's own pan/scroll
    /// recogniser doesn't win the arbitration when the finger starts on
    /// the signature. Translation animates live via `@GestureState`;
    /// commit happens once at drag-end via `onMoveViaDrag`.
    private func dragGesture(
        pdfView: PDFView,
        page: PDFPage,
        currentViewRect: CGRect,
        placement: SignatureViewModel.Placement
    ) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newViewRect = currentViewRect.offsetBy(dx: value.translation.width, dy: value.translation.height)
                let topLeft = pdfView.convert(CGPoint(x: newViewRect.minX, y: newViewRect.minY), to: page)
                let bottomRight = pdfView.convert(CGPoint(x: newViewRect.maxX, y: newViewRect.maxY), to: page)
                let x = min(topLeft.x, bottomRight.x)
                let y = min(topLeft.y, bottomRight.y)
                let width = abs(bottomRight.x - topLeft.x)
                let height = abs(bottomRight.y - topLeft.y)
                let newPageRect = page.clampedToMediaBox(CGRect(x: x, y: y, width: width, height: height))
                onMoveViaDrag(SignatureViewModel.Placement(pageIndex: placement.pageIndex, pageRect: newPageRect))
            }
    }
}
