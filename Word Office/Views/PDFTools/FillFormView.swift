// Session 12 (2026-09-04) — Fill Form free-text overlay orchestrator.
// Adobe Fill & Sign pattern: tap PDF → sheet edit → committed text
// renders as SwiftUI overlay + persists to `TextAnnotation` model,
// finally embedded as `PDFAnnotation.freeText` on Save.
//
// Sheet-based edit rather than inline UITextField over PDFView because
// putting a live UITextField responder on top of PDFView's own scroll
// gesture recogniser fights every keystroke (PDFView tries to
// pan/zoom, TextField tries to caret-move). The sheet sidesteps that
// entire interaction fight — user types in isolation, commits, PDFView
// re-becomes the interactive layer for the next tap.

import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FillFormView: View {
    @Bindable var viewModel: FillFormViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Kept for API stability across tool destinations; Fill Form no
    /// longer auto-opens the editor after save (Session 12 UX change —
    /// pop back to Tools home + toast instead), but the signature stays
    /// so `ToolsTabView.destinationView` doesn't need a special-case.
    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil

    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// Staged preview URL, set after `viewModel.stagePreview()` writes
    /// the filled PDF to temp. Wrapped in `PreviewPayload` because
    /// `URL` isn't `Identifiable` by default and `sheet(item:)` needs it.
    @State private var previewPayload: PreviewPayload?
    /// Set right before `previewPayload = nil` on a successful save so the
    /// sheet's `onDismiss` can pop this destination AFTER the sheet's own
    /// dismiss animation finishes, instead of both firing in the same
    /// runloop tick (was a visible double-dismiss race, worse on iPad).
    @State private var shouldDismissAfterPreviewCloses = false

    private struct PreviewPayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        Group {
            switch viewModel.stage {
            case .pickPDF: pickStage
            case .fill:    fillStage
            }
        }
        .prominentInlineTitle("Fill Form")
        // `fillFormVM` is a single instance shared across every push into
        // this destination (`ToolsTabView` creates it once, not per-push) —
        // without this, backing out mid-flow without saving left `stage`/
        // `sourceURL`/`annotations` stale, so re-opening Fill Form landed
        // straight back on the mid-flow state instead of a fresh "Choose a
        // PDF". Harmless no-op if `commitSave` already called `reset()` on
        // the success path just before this fires.
        .onDisappear { viewModel.reset() }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.pdf],
            onCompletion: handleFilePicked
        )
        .sheet(isPresented: $isLibraryPickerPresented) {
            LibraryFilePicker(
                entries: store.entries,
                filter: { $0.document.kind == .pdf },
                allowsMultipleSelection: false,
                emptyTitle: "No PDFs in Library",
                emptyMessage: "Import PDF files first, then come back."
            ) { urls in
                guard let url = urls.first else { return }
                handleFilePicked(.success(url))
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Preparing preview", subtitle: "Embedding text into the document")
            }
        }
        .errorAlert($viewModel.errorMessage)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent, let source = initialSource, viewModel.stage == .pickPDF else { return }
            didAutoPresent = true
            switch source {
            case .library: isLibraryPickerPresented = true
            case .browse:  isPickerPresented = true
            }
        }
        .sheet(item: $previewPayload, onDismiss: {
            if shouldDismissAfterPreviewCloses {
                shouldDismissAfterPreviewCloses = false
                // Reset AFTER dismiss — the sheet has now left the screen,
                // so the underlying view flipping back to `.pickPDF` isn't
                // visible (F11).
                viewModel.reset()
                dismiss()
            }
        }) { payload in
            PreviewConfirmSheet(
                url: payload.url,
                title: "Preview filled PDF",
                confirmLabel: "Save",
                canReplaceOriginal: viewModel.canReplaceSourceInPlace
            ) { mode in
                Task { await commitSave(payload.url, mode: mode) }
            } onCancel: {
                viewModel.discardPreview(payload.url)
                previewPayload = nil
            }
        }
    }

    // MARK: - Stage 1

    @ViewBuilder
    private var pickStage: some View {
        if !didAutoPresent, initialSource != nil {
            Color.dsBackgroundSecondary.ignoresSafeArea()
        } else {
            EmptyStateView(
                icon: "square.and.pencil",
                title: "Choose a PDF to fill",
                message: "Pick one PDF. You'll tap on the page to add text — forms or scans, doesn't matter.",
                action: ("Choose a PDF", { isSourcePickerPresented = true })
            )
        }
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            Task { await viewModel.selectPDF(url) }
        }
    }

    // MARK: - Stage 2

    @ViewBuilder
    private var fillStage: some View {
        if let document = viewModel.pdfDocument {
            VStack(spacing: 0) {
                helpBanner
                FillFormPDFCanvas(
                    document: document,
                    annotations: viewModel.annotations,
                    onAddAnnotation: viewModel.addAnnotation,
                    onRemoveAnnotation: viewModel.removeAnnotation(id:),
                    onMoveAnnotation: viewModel.moveAnnotation(id:to:)
                )
            }
            // Action bar as a `.safeAreaInset` — stacks ABOVE the 84pt
            // inset `RootView` already reserves for the floating custom
            // tab bar, so the Save/Undo buttons stay visible instead of
            // being clipped by the pill+FAB overlay. Plain VStack layout
            // would place them at screen-bottom edge, which sits BEHIND
            // the tab bar (Session 12 UI bug reported by user).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
        } else {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "No PDF loaded",
                message: "Something went wrong — pick a PDF to try again",
                action: ("Pick PDF", { viewModel.reset() })
            )
        }
    }

    private var helpBanner: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
            Text("Tap the page to add text. Drag to move it, long-press to remove.")
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextSecondary)
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.dsBackgroundSecondary)
    }

    private var actionBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                viewModel.undoLast()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .disabled(viewModel.annotations.isEmpty)

            Button {
                Task { await performSave() }
            } label: {
                Text("Save changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.dsBackgroundSecondary)
    }

    /// User tapped "Save changes" in editing — stage a preview into
    /// temp then present the confirm sheet. Two-phase (Session 12 UX):
    /// nothing lands in Documents/ until they explicitly Confirm.
    private func performSave() async {
        guard let staged = await viewModel.stagePreview() else { return }
        previewPayload = PreviewPayload(url: staged)
    }

    /// User confirmed from preview sheet — move staged file to Documents/,
    /// fire toast, pop back to Tools home.
    private func commitSave(_ stagedURL: URL, mode: PreviewSaveMode) async {
        guard let final = await viewModel.commitPreview(stagedURL, mode: mode) else {
            // Failure — `commitPreview` already deleted the staged temp file
            // and set `errorMessage`. Close the sheet so `.errorAlert`
            // (attached to the view underneath) can actually present it;
            // previously this returned with the sheet still open, which
            // both hid the alert forever and left "Save" stuck disabled
            // with no way out but a swipe-dismiss. Stay on `.fill` (no
            // `shouldDismissAfterPreviewCloses`, no `reset()`) so the
            // annotations survive and the user can just retry Save.
            previewPayload = nil
            return
        }
        // Toast BEFORE dismiss — presenter is app-scoped so it keeps
        // showing on Tools home after the pop. Exhaustive `switch` +
        // source-derived filename for the replace path — see the
        // matching block in `SignFlowView.commitSave` for the full
        // rationale (code-review findings #7, #14).
        let toastTitle: String
        let toastFilename: String
        switch mode {
        case .newFile:
            toastTitle = "Your filled document was saved to Home"
            toastFilename = final.lastPathComponent
        case .replaceOriginal:
            toastTitle = "The original file has been replaced"
            toastFilename = viewModel.sourceURL?.lastPathComponent ?? final.lastPathComponent
        }
        toaster.show(.success, title: toastTitle, filename: toastFilename)
        // Dismiss the preview sheet FIRST, then reset — the earlier
        // order (reset() → previewPayload=nil) flipped stage back to
        // `.pickPDF` while the sheet was still dismissing, so the user
        // saw a ~200ms flash of the empty pick-a-PDF state behind the
        // sheet on iPad (and on the last few frames of the iPhone slide-
        // out). See code review F11.
        if previewPayload != nil {
            shouldDismissAfterPreviewCloses = true
            previewPayload = nil
            // `viewModel.reset()` runs from the sheet's onDismiss below,
            // after the sheet has actually left the screen.
        } else {
            viewModel.reset()
            // User swipe-dismissed the preview sheet while commitPreview was
            // running. onDismiss already fired with flag=false (no pop). The
            // sheet is gone, so setting previewPayload=nil is a no-op and
            // onDismiss won't fire again — pop directly instead of leaving
            // shouldDismissAfterPreviewCloses=true to trip on the next Cancel.
            dismiss()
        }
    }
}

// MARK: - PDF canvas + tap-to-add + overlay display

/// PDFView wrapped in SwiftUI with tap-to-add + long-press-to-remove
/// annotations. The overlay renders committed annotations on top of
/// PDFView at their PDF-page positions converted back to view coords.
struct FillFormPDFCanvas: View {
    let document: PDFDocument
    let annotations: [TextAnnotation]
    let onAddAnnotation: (TextAnnotation) -> Void
    let onRemoveAnnotation: (UUID) -> Void
    /// Fires at drag-end with the new PDF-page-coord rect for the
    /// annotation being moved. Overlay computes it locally via
    /// `PDFView.convert(_:to:)` so the parent doesn't need PDFView refs.
    let onMoveAnnotation: (UUID, CGRect) -> Void

    @State private var pdfView: PDFView?
    /// Mirrors `pdfView.currentPage`'s page index into observable state
    /// (F6). PDFKit exposes `currentPage` as a plain UIKit property with
    /// no publisher, so a raw SwiftUI body never re-runs on scroll — the
    /// annotation filter below would then silently drop overlays as the
    /// user swipes to a different page. `PDFView.pageChangedNotification`
    /// (subscribed via `.onReceive`) updates this on every primary-page
    /// transition, driving the re-render.
    @State private var currentPageIndex: Int = 0
    /// Draft text being entered via the sheet. Nil = sheet dismissed.
    @State private var pendingDraft: PendingDraft?

    private struct PendingDraft: Identifiable {
        let id = UUID()
        let pageIndex: Int
        let pageRect: CGRect
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                FillFormPDFView(
                    document: document,
                    pdfView: $pdfView,
                    onTap: { locationInView in
                        handleTap(at: locationInView)
                    }
                )

                // Render committed annotations for the current page on top.
                // Filter by `currentPageIndex` (observable state updated
                // from the pageChanged notification) so SwiftUI re-runs
                // body when the user scrolls — reading `pdfView
                // .currentPage` directly wouldn't establish the state
                // dependency, so the filter would stay stale.
                if let pdfView,
                   let page = pdfView.document?.page(at: currentPageIndex) {
                    ForEach(annotations.filter { $0.pageIndex == currentPageIndex }) { annotation in
                        TextAnnotationOverlay(
                            annotation: annotation,
                            pdfView: pdfView,
                            page: page,
                            onRemove: { onRemoveAnnotation(annotation.id) },
                            onMove: { newPageRect in
                                onMoveAnnotation(annotation.id, newPageRect)
                            }
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { note in
            guard let sender = note.object as? PDFView, sender === pdfView,
                  let page = sender.currentPage,
                  let doc = sender.document else { return }
            currentPageIndex = doc.index(for: page)
        }
        .sheet(item: $pendingDraft) { draft in
            FillFormTextEditor { text in
                let annotation = TextAnnotation(
                    pageIndex: draft.pageIndex,
                    pageRect: draft.pageRect,
                    text: text
                )
                onAddAnnotation(annotation)
                pendingDraft = nil
            } onCancel: {
                pendingDraft = nil
            }
        }
    }

    private func handleTap(at locationInView: CGPoint) {
        guard let pdfView,
              let page = pdfView.page(for: locationInView, nearest: true),
              let document = pdfView.document
        else { return }
        let pageIndex = document.index(for: page)
        let pageOrigin = pdfView.convert(locationInView, to: page)
        // Default annotation box: 180×24 pt on the PDF page, anchored at
        // the tap. Autosizing happens later at save if needed.
        let pageRect = page.clampedToMediaBox(CGRect(x: pageOrigin.x, y: pageOrigin.y - 24, width: 180, height: 24))
        pendingDraft = PendingDraft(pageIndex: pageIndex, pageRect: pageRect)
    }
}

/// One committed text annotation as a SwiftUI overlay over the PDFView.
/// Owns its own drag + long-press gestures so `@GestureState` isolation
/// per-item works correctly (a shared gesture state across `ForEach`
/// items would race between them). Drag translates live via view-space
/// offset; on release, the parent's `onMove` receives the finalised
/// PDF-page-coord rect (converted via `PDFView.convert(_:to:)`).
private struct TextAnnotationOverlay: View {
    let annotation: TextAnnotation
    let pdfView: PDFView
    let page: PDFPage
    let onRemove: () -> Void
    let onMove: (CGRect) -> Void

    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        let viewRect = viewRect()
        Text(annotation.text)
            .font(.system(size: annotation.fontSize))
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, 3)
            .background(Color.dsBrandPrimarySubtle.opacity(0.6))
            .overlay(
                Rectangle()
                    .strokeBorder(Color.dsBrandPrimary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
            .frame(width: viewRect.width, height: viewRect.height, alignment: .topLeading)
            .position(
                x: viewRect.midX + dragTranslation.width,
                y: viewRect.midY + dragTranslation.height
            )
            .highPriorityGesture(dragGesture(viewRect: viewRect))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in onRemove() }
            )
            .accessibilityLabel("Text annotation — drag to move, long-press to remove")
    }

    private func viewRect() -> CGRect {
        let topLeftInView = pdfView.convert(CGPoint(x: annotation.pageRect.minX, y: annotation.pageRect.maxY), from: page)
        let bottomRightInView = pdfView.convert(CGPoint(x: annotation.pageRect.maxX, y: annotation.pageRect.minY), from: page)
        return CGRect(
            x: min(topLeftInView.x, bottomRightInView.x),
            y: min(topLeftInView.y, bottomRightInView.y),
            width: abs(bottomRightInView.x - topLeftInView.x),
            height: abs(bottomRightInView.y - topLeftInView.y)
        )
    }

    /// `.highPriorityGesture` so PDFView's pan/scroll doesn't win when
    /// the finger starts on the annotation. Translation animates live
    /// via `@GestureState`; the parent's `onMove` fires once at end.
    private func dragGesture(viewRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newViewRect = viewRect.offsetBy(dx: value.translation.width, dy: value.translation.height)
                let topLeft = pdfView.convert(CGPoint(x: newViewRect.minX, y: newViewRect.minY), to: page)
                let bottomRight = pdfView.convert(CGPoint(x: newViewRect.maxX, y: newViewRect.maxY), to: page)
                let x = min(topLeft.x, bottomRight.x)
                let y = min(topLeft.y, bottomRight.y)
                let width = abs(bottomRight.x - topLeft.x)
                let height = abs(bottomRight.y - topLeft.y)
                onMove(page.clampedToMediaBox(CGRect(x: x, y: y, width: width, height: height)))
            }
    }
}

// MARK: - PDFView bridge with tap gesture

struct FillFormPDFView: UIViewRepresentable {
    /// Pre-loaded document from `FillFormViewModel.pdfDocument` — never
    /// parsed inside `makeUIView` so the push/nav animation stays smooth
    /// on large PDFs (F8). Caller renders a placeholder while the VM's
    /// async load is in flight.
    let document: PDFDocument
    @Binding var pdfView: PDFView?
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .systemBackground
        // Single-tap recogniser to capture "add text here" intent —
        // PDFView's own gestures still handle scroll/zoom underneath.
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

        // Yielding to PDFView's built-in recognisers so pinch-zoom /
        // scroll aren't blocked. A tap that lands after a scroll still
        // registers because UIKit only cancels the tap if a scroll
        // actually recognised — pure taps come through.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - Text editor sheet

struct FillFormTextEditor: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Text to add")
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsTextSecondary)
                    .padding(.horizontal, DSSpacing.md)

                TextField("Type here", text: $text, axis: .vertical)
                    .font(DSFont.body)
                    .focused($focused)
                    .padding(DSSpacing.sm)
                    .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.control)
                            .stroke(Color.dsBorderDefault, lineWidth: 1)
                    )
                    .padding(.horizontal, DSSpacing.md)
                    .lineLimit(1...4)
                    .submitLabel(.done)
                    .onSubmit(commit)

                Spacer()
            }
            .padding(.top, DSSpacing.md)
            .navigationTitle("Add text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: commit)
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(220), .medium])
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
    }
}
