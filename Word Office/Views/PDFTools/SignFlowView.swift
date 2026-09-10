// Session 12 (2026-09-04, revision 2) — Sign flow orchestrator.
// Two stages: pickPDF → fill (tap-position-first, sheet canvas).
//
// UX matches Adobe Fill & Sign + this app's own FillFormView: tap
// where you want to sign, draw in a bottom sheet, commit. Signature
// stays draggable-by-retap; long-press to clear and re-draw.

import PencilKit
import SwiftUI
import UniformTypeIdentifiers

struct SignFlowView: View {
    @Bindable var viewModel: SignatureViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Kept for API stability across tool destinations; Sign no longer
    /// auto-opens the editor after save (Session 12 UX change — pop
    /// back to Tools home + toast instead), but the signature stays so
    /// `ToolsTabView.destinationView` doesn't need a special-case.
    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil

    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// Placement captured at tap time — set when the user taps an empty
    /// spot on the PDF (no signature yet). Non-nil = show the draw
    /// sheet. Nil = sheet dismissed. The commit action consumes this
    /// alongside the drawing bytes.
    @State private var pendingPlacement: PendingPlacement?
    /// Staged preview URL from `viewModel.stagePreview()`. Non-nil
    /// presents the preview+confirm sheet (Session 12 UX: preview
    /// before commit).
    @State private var previewPayload: PreviewPayload?
    /// Set right before `previewPayload = nil` on a successful save so the
    /// sheet's `onDismiss` can pop this destination AFTER the sheet's own
    /// dismiss animation finishes, instead of both firing in the same
    /// runloop tick (was a visible double-dismiss race, worse on iPad).
    @State private var shouldDismissAfterPreviewCloses = false

    private struct PendingPlacement: Identifiable {
        let id = UUID()
        let placement: SignatureViewModel.Placement
    }

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
        .prominentInlineTitle("Sign")
        .toolbar { toolbarContent }
        // `signatureVM` is a single instance shared across every push into
        // this destination (`ToolsTabView` creates it once, not per-push) —
        // without this, backing out mid-flow without saving left `stage`/
        // `sourceURL`/`placement` stale, so re-opening Sign landed straight
        // back on the mid-flow state instead of a fresh "Choose a PDF".
        // Harmless no-op if `commitSave` already called `reset()` on the
        // success path just before this fires.
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
                ProcessingOverlay(title: "Stamping signature", subtitle: "Re-rendering the PDF with your signature on the chosen page")
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
        .sheet(item: $pendingPlacement) { pending in
            SignatureDrawSheet { pngData in
                viewModel.commitSignature(pngData: pngData, at: pending.placement)
                pendingPlacement = nil
            } onCancel: {
                pendingPlacement = nil
            }
        }
        .sheet(item: $previewPayload, onDismiss: {
            if shouldDismissAfterPreviewCloses {
                shouldDismissAfterPreviewCloses = false
                // Reset AFTER the sheet has left the screen so the empty
                // `.pickPDF` state isn't visible during the dismiss
                // animation (F11).
                viewModel.reset()
                dismiss()
            }
        }) { payload in
            PreviewConfirmSheet(
                url: payload.url,
                title: "Preview signed PDF",
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.stage == .fill {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await performSave() } }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
            }
        }
    }

    // MARK: - Stage 1

    @ViewBuilder
    private var pickStage: some View {
        // When a source was chosen on the Tools tab, the picker will auto-open
        // via .task. Don't show the empty state while that's pending — it
        // creates a "double screen" appearance (Sign empty state + picker sheet).
        if !didAutoPresent, initialSource != nil {
            Color.dsBackgroundSecondary.ignoresSafeArea()
        } else {
            EmptyStateView(
                icon: "signature",
                title: "Choose a PDF to sign",
                message: "Pick one PDF. You'll tap where you want to sign, then draw your signature.",
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
                SignPDFCanvas(
                    document: document,
                    signatureImage: signatureUIImage,
                    placement: viewModel.placement,
                    onTapPDF: handlePDFTap,
                    onMoveViaDrag: viewModel.movePlacement,
                    onClearSignature: viewModel.clearSignature
                )
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

    private var signatureUIImage: UIImage? {
        guard let data = viewModel.signatureImageData else { return nil }
        return UIImage(data: data)
    }

    private var helpBanner: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
            Text(helpBannerText)
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextSecondary)
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.dsBackgroundSecondary)
    }

    private var helpBannerText: LocalizedStringKey {
        if viewModel.signatureImageData == nil {
            "Tap where you want to sign — you'll draw your signature next"
        } else {
            "Drag the signature to move it. Long-press to clear. Tap Save when done."
        }
    }

    // MARK: - Actions

    private func handlePDFTap(_ placement: SignatureViewModel.Placement) {
        if viewModel.signatureImageData == nil {
            // No signature drawn yet — open the sheet + remember where
            // to place it on commit.
            pendingPlacement = PendingPlacement(placement: placement)
        } else {
            // Signature exists — this tap is a reposition request.
            viewModel.movePlacement(to: placement)
        }
    }

    /// User tapped Save in toolbar — stage a preview to temp then
    /// present the confirm sheet. Nothing lands in Documents/ until
    /// they explicitly Confirm.
    private func performSave() async {
        guard let staged = await viewModel.stagePreview() else { return }
        previewPayload = PreviewPayload(url: staged)
    }

    private func commitSave(_ stagedURL: URL, mode: PreviewSaveMode) async {
        guard let final = await viewModel.commitPreview(stagedURL, mode: mode) else {
            // Failure — `commitPreview` already deleted the staged temp file
            // and set `errorMessage`. Close the sheet so `.errorAlert`
            // (attached to the view underneath) can actually present it;
            // previously this returned with the sheet still open, which
            // both hid the alert forever and left "Save" stuck disabled
            // with no way out but a swipe-dismiss. Stay on `.fill` (no
            // `shouldDismissAfterPreviewCloses`, no `reset()`) so the
            // placement survives and the user can just retry Save.
            previewPayload = nil
            return
        }
        // Toast copy differentiates save mode so the user can tell
        // whether they created a new file OR overwrote the original,
        // without opening Library to verify. Exhaustive `switch` (not
        // ternary) so adding a third `PreviewSaveMode` case in the
        // future is a compile error here instead of silently
        // mis-labeling — code-review finding #7.
        //
        // Toast filename comes from the SOURCE's last-path-component,
        // not `final`'s: on a cross-volume replace fallback the OS may
        // migrate `final` to a differently-named temp path, and the
        // toast should read what the user picked (finding #14).
        let toastTitle: String
        let toastFilename: String
        switch mode {
        case .newFile:
            toastTitle = "Your signed document was saved to Home"
            toastFilename = final.lastPathComponent
        case .replaceOriginal:
            toastTitle = "The original file has been replaced"
            toastFilename = viewModel.sourceURL?.lastPathComponent ?? final.lastPathComponent
        }
        toaster.show(.success, title: toastTitle, filename: toastFilename)
        // Dismiss FIRST, then reset — flipping stage back to `.pickPDF`
        // while the preview sheet is still animating out would flash the
        // empty pick-a-PDF state behind the sheet (F11). onDismiss resets
        // once the sheet has left the screen.
        if previewPayload != nil {
            shouldDismissAfterPreviewCloses = true
            previewPayload = nil
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

// MARK: - Signature draw sheet

/// Bottom sheet with a PKCanvasView for drawing the signature. Shipped
/// as a medium-detent sheet so the PDF context above stays visible —
/// the user can drag to `.large` for more drawing room.
struct SignatureDrawSheet: View {
    let onCommit: (Data) -> Void
    let onCancel: () -> Void

    @State private var drawing = PKDrawing()
    @State private var isClearConfirmationPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.md) {
                Text("Draw your signature")
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.md)

                SignatureCanvasView(drawing: $drawing)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                            .stroke(Color.dsBorderSubtle, lineWidth: 1)
                            .allowsHitTesting(false)
                    )
                    .padding(.horizontal, DSSpacing.md)

                Text("Signature is stored on this device only — never uploaded")
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsTextTertiary)
                    .padding(.horizontal, DSSpacing.md)

                Spacer(minLength: 0)
            }
            .padding(.top, DSSpacing.md)
            .background(Color.dsBackgroundSecondary)
            .navigationTitle("New signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign here") {
                        if let data = drawing.pngData() {
                            onCommit(data)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(drawing.strokes.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        isClearConfirmationPresented = true
                    } label: {
                        Label("Clear", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
            // Wiping an in-progress drawing is irreversible (no undo
            // manager wired to this canvas) — per `~/CLAUDE.md`'s
            // destructive-action rule, confirm before it's gone.
            .confirmationDialog(
                "Clear this signature?",
                isPresented: $isClearConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Clear Signature", role: .destructive) {
                    drawing = PKDrawing()
                }
            } message: {
                Text("This can't be undone.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
