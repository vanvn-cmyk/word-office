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

/// PDFView bridged to SwiftUI. One page at a time (singlePage +
/// usePageViewController) so the signing canvas matches `PreviewConfirmSheet`.
/// Publishes the live `PDFView`, current page (1-based), and total page count
/// back to the parent via bindings. Forwards single-tap locations upward.
struct SignPDFView: UIViewRepresentable {
    /// Pre-loaded document from `SignatureViewModel.pdfDocument` — never
    /// parsed inside `makeUIView`, so the push animation into the fill
    /// stage stays smooth even on large scanned contracts (F8).
    let document: PDFDocument
    @Binding var pdfView: PDFView?
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePage
        view.autoScales = true
        view.backgroundColor = .systemBackground
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.onTap = onTap
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        let count = document.pageCount
        DispatchQueue.main.async {
            pdfView = view
            totalPages = max(1, count)
            currentPage = 1
            // Runs after first layout so PDFView's UIScrollView is in hierarchy.
            // Disabling scroll prevents swipe-based page navigation; the
            // chevron button pill is the only way to change pages.
            Self.disableScrollNav(in: view)
        }
        return view
    }

    private static func disableScrollNav(in view: UIView) {
        for subview in view.subviews {
            if let sv = subview as? UIScrollView { sv.isScrollEnabled = false }
            disableScrollNav(in: subview)
        }
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.onTap = onTap
        // Drive navigation when parent increments/decrements currentPage via buttons.
        guard let doc = uiView.document,
              currentPage >= 1, currentPage <= doc.pageCount,
              let target = doc.page(at: currentPage - 1),
              uiView.currentPage !== target else { return }
        uiView.go(to: target)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?
        private var currentPage: Binding<Int>

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        @objc func didTap(_ sender: UITapGestureRecognizer) {
            let location = sender.location(in: sender.view)
            onTap?(location)
        }

        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let page = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let idx = doc.index(for: page) + 1
            Task { @MainActor [weak self] in self?.currentPage.wrappedValue = idx }
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
/// currently-committed placement and a page-navigator pill (chevrons + "X/Y")
/// floated at the bottom when the document has more than one page.
///
/// Interactions:
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
    /// Fires at pinch-end with the cumulative scale factor so the parent can
    /// resize the PDF-coord rect via `SignatureViewModel.scalePlacement(by:)`.
    var onScalePlacement: ((CGFloat) -> Void)? = nil

    @State private var pdfView: PDFView?
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    /// Live drag translation in view coords — added on top of the
    /// committed placement's screen position while the finger is down.
    /// Reset to `.zero` on drag-end after the parent's move callback
    /// consumes the delta.
    @GestureState private var dragTranslation: CGSize = .zero
    /// Live scale during a pinch — 1.0 when no pinch is active.
    @GestureState private var pinchScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { _ in
                ZStack {
                    SignPDFView(
                        document: document,
                        pdfView: $pdfView,
                        currentPage: $currentPage,
                        totalPages: $totalPages
                    ) { locationInView in
                        handleTap(at: locationInView)
                    }

                    // Gate on `currentPage` (state) not `pdfView.currentPage`
                    // (UIKit property, not observable) so SwiftUI re-runs body
                    // when the user navigates pages. Overlay reappears once
                    // they return to `placement.pageIndex`.
                    if let signatureImage,
                       let placement,
                       let pdfView,
                       let document = pdfView.document,
                       placement.pageIndex < document.pageCount,
                       let page = document.page(at: placement.pageIndex),
                       placement.pageIndex == currentPage - 1 {
                        signatureOverlay(image: signatureImage, placement: placement, pdfView: pdfView, page: page)
                    }
                }
                // ZStack is not greedy by default — without this it collapses to
                // its content's ideal size, leaving a large gray gap between the
                // help banner and the PDF page.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if totalPages > 1 {
                pageNavigator
                    .padding(.bottom, DSSpacing.md)
            }
        }
    }

    // MARK: - Page navigator pill

    private var pageNavigator: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                currentPage = max(1, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(currentPage <= 1)

            Text("\(currentPage) / \(totalPages)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.primary)
                .frame(minWidth: 52)

            Button {
                currentPage = min(totalPages, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(currentPage >= totalPages)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Tap handler

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

    // MARK: - Signature overlay

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
            .scaleEffect(pinchScale)
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
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in state = value }
                    .onEnded { scale in onScalePlacement?(scale) }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in onClearSignature() }
            )
            .accessibilityLabel("Signature — drag to move, pinch to resize, long-press to clear")
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
