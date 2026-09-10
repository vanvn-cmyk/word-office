// Sprint 0.3, §6 — 3 input sources (camera / Photos / existing PDF) all converge
// on OCRViewModel.recognize(_:), then a dual export step (editable .docx primary,
// searchable PDF secondary/optional) per §6.5.

import PDFKit
import PhotosUI
import SwiftUI
import VisionKit

struct ScanFlowView: View {
    @Bindable var viewModel: OCRViewModel
    /// Controls whether the `.addPages` stage shows an explicit `Cancel`
    /// toolbar item. `false` (default) for the Tools-tab push, where the
    /// system back chevron already dismisses — an extra Cancel next to the
    /// chevron reads as a duplicate. `true` for the Library-tab FAB sheet,
    /// where the sheet root has no back chevron and needs its own Cancel.
    var showsExplicitCancel: Bool = false
    /// Fires after a successful save that produced exactly one file
    /// (user picked one of editable Word / searchable PDF). Parent opens
    /// it in the editor, matching the other single-output tool flows.
    var onOpenFile: ((URL) -> Void)? = nil
    /// Fires after a successful save that produced multiple files (both
    /// formats selected — DOCX + PDF). Parent presents
    /// `ToolResultGalleryView` so the user can open each format, save
    /// them elsewhere, or share both. Session 10 gap fix (2026-09-04) —
    /// the previous "toast + stay at export screen" behaviour hid the
    /// results with no path back to them from the picker.
    var onShowGallery: (([URL]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    /// Wizard stages. No `.success` stage — save completion fires a toast
    /// (see `performSave`) and the user stays at `.exportFormat` so they can
    /// re-save with different toggles or back out via `Back`/system chevron.
    private enum Stage {
        case addPages, review, exportFormat
    }

    private enum PageSource {
        case camera, photo, pdf

        var systemImage: String {
            switch self {
            case .camera: "viewfinder"
            case .photo: "photo"
            case .pdf: "doc.fill"
            }
        }
    }

    /// Wraps a page image with its source and a stable identity — `CGImage`
    /// isn't `Identifiable`/`Hashable`, and array index/offset as `ForEach` id
    /// breaks on delete (SwiftUI reuses the wrong tile's identity for whatever
    /// shifted into that offset). Also replaces what was 2 parallel arrays
    /// (`pages`/`pageSources`) kept in sync by hand — one array of one struct
    /// can't drift out of sync the way two arrays can.
    private struct ScannedPage: Identifiable {
        let id = UUID()
        let image: CGImage
        let source: PageSource
    }

    @State private var stage: Stage = .addPages
    @State private var pages: [ScannedPage] = []
    @State private var isCameraPresented = false
    @State private var isPDFPickerPresented = false
    /// Drives `sourceOptionsSheet` (Camera / Photos / PDF) from both
    /// `sourcePickerButton` call sites — the empty-state CTA and
    /// `addMoreTile`. One shared boolean is fine here (not an
    /// `Identifiable`-enum `.sheet(item:)`): the sheet has no associated
    /// model data, it's the same static 3-row picker regardless of
    /// which button opened it.
    @State private var isSourceSheetPresented = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedPageIndex = 0
    @State private var exportEditableWord = true
    @State private var exportSearchablePDF = false
    /// Reentrancy guard for `performSave`. `ocrVM` is shared across the
    /// Tools-tab lifetime; a double-tap on Save otherwise races two file
    /// writes against `FileManager.nonConflictingURL`, silently landing
    /// as `Scan 2026-09-07.docx` + `Scan 2026-09-07 (2).docx` (both
    /// with identical content) plus two toasts fighting for sheet state.
    /// View-local `@State` is enough — save state is a per-flow concern,
    /// not something other Tools screens need to observe.
    @State private var isSaving = false
    /// Session 19 — auto-opens the camera on the first appearance of a
    /// fresh flow (pages empty, camera never opened yet). Skips the
    /// "Add pages to recognize" landing state so the user lands
    /// directly in the scan surface — one tap less to first capture.
    /// Reset only via `viewModel.reset()` / `.onDisappear`, so a mid-
    /// flow cancel back to the pages grid doesn't re-fire the camera
    /// unexpectedly.
    @State private var hasAutoOpenedCamera = false
    /// Drives `.photosPicker(isPresented:)` for the quick "Photos"
    /// shortcut overlaid on the live camera scanner (below) — the
    /// landing state's own "Choose from Photos" is a `PhotosPicker`
    /// used directly as a `moreSourcesMenu` item now (self-presenting,
    /// no binding needed), but the camera overlay's button isn't a
    /// `PhotosPicker` itself (it dismisses the camera first, with a
    /// short delay, before presenting), so it still needs this.
    @State private var isPhotosPickerPresented = false

    /// True only when a real, usable document-scanner camera is
    /// present. Combines Apple's own API (`VNDocumentCameraViewController.isSupported`,
    /// which reports false on the iOS Simulator and on rare device
    /// configurations without a camera) with a belt-and-braces
    /// `#if targetEnvironment(simulator)` compile-time guard so a
    /// future iOS-simulator change that flips `isSupported` to `true`
    /// without providing an actual camera session (would present a
    /// frozen black `VNDocumentCameraViewController` again) still
    /// gets caught here at compile time.
    private var isCameraAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }

    var body: some View {
        stateContent
            .prominentInlineTitle(navigationTitle)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $isCameraPresented) { cameraSheet }
            .fileImporter(isPresented: $isPDFPickerPresented, allowedContentTypes: [.pdf], onCompletion: handlePDFPicked)
            // Top-level, matching `.fileImporter` right above — not
            // scoped inside `emptyAddPages` (where it lived until this
            // review). That scoping was a real bug: the camera overlay's
            // quick "Photos" shortcut sets `isPhotosPickerPresented`
            // after dismissing the camera, but once `pages` is non-empty
            // `addPagesState` renders `pagesGrid` instead of
            // `emptyAddPages` — the shortcut would silently do nothing
            // if tapped after the user already had ≥1 page. Top-level
            // means it's live regardless of which state is showing.
            .photosPicker(
                isPresented: $isPhotosPickerPresented,
                selection: $photoItems,
                matching: .images
            )
            .sheet(isPresented: $isSourceSheetPresented) { sourceOptionsSheet }
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .overlay { processingOverlay }
            .errorAlert($viewModel.errorMessage)
            // `ocrVM` outlives this view (owned by `ToolsTabView`), so
            // errors and results from a previous Scan push would otherwise
            // greet the next push — matching the Session 13 fix pattern
            // that Print/Merge/Split/Convert got; Scan was missed then.
            .onAppear {
                viewModel.errorMessage = nil
                // Auto-open camera on first entry to a fresh flow. Skips
                // the landing state entirely on the common path (user
                // opened Scan tool → wants to scan) while preserving
                // the fallback surface (see `emptyAddPages`) for the
                // cancel-and-choose-another-source path.
                //
                // Guarded by `isCameraAvailable` (returns false on
                // simulator + rare device configs) so we never present
                // the frozen black VC that would result from opening
                // `VNDocumentCameraViewController` without a working
                // camera session. Landing state's Choose from Photos /
                // PDF buttons are still usable in that case; the "Scan
                // with Camera" button there is disabled with an
                // explanatory hint so users can't manually reach the
                // same frozen state.
                if pages.isEmpty && !hasAutoOpenedCamera && isCameraAvailable {
                    hasAutoOpenedCamera = true
                    isCameraPresented = true
                }
            }
            .onDisappear { viewModel.reset() }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch stage {
        case .addPages:
            addPagesState
        case .review:
            OCRPreviewView(results: viewModel.results, selectedPageIndex: $selectedPageIndex)
        case .exportFormat:
            exportFormatState
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        if viewModel.isProcessing {
            ProcessingOverlay(
                title: "Recognizing page \(viewModel.completedPageCount + 1) of \(viewModel.totalPageCount)",
                subtitle: "Up to 3 pages processed at once"
            )
        }
    }

    private var cameraSheet: some View {
        // Camera surface + floating "Photos" pill overlay (top-right,
        // clear of `VNDocumentCameraViewController`'s own Cancel top-
        // left and shutter/filter chrome bottom-center). One-tap
        // switch from camera into the system photo picker — saves the
        // user the cancel-out-then-tap-Photos two-step the landing
        // state previously required.
        //
        // Tap sequence: dismiss camera first, wait one dismiss frame
        // (~350ms — same pattern the kebab Share/Rename flows use so
        // the system picker slides up onto a settled screen), then
        // present the Photos picker. Presenting both modals at once
        // races the fullScreenCover's dismiss animation and iOS
        // rejects the picker with "Attempt to present … while
        // presenting" in the log.
        ZStack(alignment: .topTrailing) {
            DocumentCameraScanner(
                onFinish: { images in
                    pages.append(contentsOf: images.map { ScannedPage(image: $0, source: .camera) })
                    isCameraPresented = false
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()

            Button {
                isCameraPresented = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isPhotosPickerPresented = true
                }
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .foregroundStyle(.white)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            }
            .accessibilityLabel("Choose from Photos")
            // Positioned in the top-right corner where VN's own chrome
            // (Cancel top-left, Auto toggle further right, shutter
            // bottom) leaves the most breathing room. `padding(.top)`
            // clears the status bar / notch.
            .padding(.trailing, DSSpacing.md)
            .padding(.top, DSSpacing.md + 8)
        }
    }

    private var navigationTitle: String {
        switch stage {
        case .addPages: pages.isEmpty ? "Scan & OCR" : "\(pages.count) page\(pages.count == 1 ? "" : "s")"
        case .review: "Review"
        case .exportFormat: "Export as"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch stage {
        case .addPages:
            if showsExplicitCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            if !pages.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Recognize") { Task { await performRecognize() } }
                        .fontWeight(.semibold)
                        .disabled(viewModel.isProcessing)
                }
            }
        case .review:
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { stage = .exportFormat }.fontWeight(.semibold)
            }
        case .exportFormat:
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { stage = .review }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await performSave() } }
                    .fontWeight(.semibold)
                    .disabled(!(exportEditableWord || exportSearchablePDF) || isSaving)
            }
        }
    }

    // MARK: - Add pages

    @ViewBuilder
    private var addPagesState: some View {
        if pages.isEmpty {
            emptyAddPages
        } else {
            pagesGrid
        }
    }

    private var emptyAddPages: some View {
        // Inline layout with `Spacer()` brackets instead of `EmptyStateView`.
        // `EmptyStateView` has `.frame(maxHeight: .infinity)` baked in — it's
        // designed as a full-page component where the CTA sits INSIDE it, not
        // as a sibling in a VStack. Using it here pushed the "Scan with
        // Camera" button and the "Or choose from Photos / PDF" menu link to
        // the very bottom of the parent frame, where the floating tab bar
        // rendered over them. Centering the icon+text with `Spacer()` on
        // both sides puts the CTAs above the tab-bar safe-area inset instead.
        VStack(spacing: DSSpacing.md) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)

            VStack(spacing: DSSpacing.xs) {
                Text("Add pages to recognize")
                    .font(DSFont.title3)
                    .foregroundStyle(Color.dsTextPrimary)
                Text("We'll turn it into text you can edit, search, and copy")
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Single CTA opening `sourceOptionsSheet` (Camera / Photos /
            // PDF) — replaces the earlier 3 stacked full-width buttons,
            // flagged as "nhiều button quá". A bottom sheet, not a
            // `Menu` (tried first, flagged as "bottom sheet đi ổn hơn
            // đấy" — the compact popover anchored to the button read
            // cramped next to the icons). Same sheet the "add more
            // pages" tile already opens once pages exist (`addMoreTile`
            // below), so the interaction is consistent whether this is
            // the first page or the fifth. "Choose a Source", not "Add
            // Pages" — the headline right above already says "Add
            // pages to recognize"; the button repeating it added
            // nothing and was flagged ("hay text khác"). "Choose a
            // Source" instead describes what tapping it actually does.
            // The "Camera not available…" hint stays as its own line
            // since it's still useful context even with Camera folded
            // into the sheet (now `.disabled` there instead of removed).
            VStack(spacing: DSSpacing.xxs) {
                sourcePickerButton {
                    Text("Choose a Source")
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextOnBrand)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DSSize.buttonHeight)
                        .background(Color.dsBrandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
                }

                if !isCameraAvailable {
                    Text("Camera not available on this device — use Photos or PDF instead")
                        .font(DSFont.caption)
                        .foregroundStyle(Color.dsTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        // `xl`, not `sm` — the CTA + hint were reading as jammed
        // against the bottom curve/home-indicator edge ("đẩy lên sát
        // quá") once the 3 stacked buttons collapsed into 1 shorter
        // block, since the same bottom padding no longer had 2 extra
        // buttons' worth of height keeping it away from the edge.
        .padding(.bottom, DSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundPrimary)
    }

    private var pagesGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: DSSpacing.sm)], spacing: DSSpacing.sm) {
                ForEach(pages) { entry in
                    pageThumbnail(entry)
                }
                addMoreTile
            }
            .padding(DSSpacing.md)
        }
    }

    private func pageThumbnail(_ entry: ScannedPage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: UIImage(cgImage: entry.image))
                .resizable()
                .aspectRatio(3.0 / 4.0, contentMode: .fill)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: entry.source.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(5)
                }

            Button {
                pages.removeAll { $0.id == entry.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(5)
            .accessibilityLabel("Remove page")
        }
    }

    private var addMoreTile: some View {
        sourcePickerButton {
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(Color.dsBorderDefault, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .frame(height: 120)
                .overlay {
                    Image(systemName: "plus").foregroundStyle(Color.dsBrandPrimary)
                }
        }
    }

    /// Opens `sourceOptionsSheet` — a plain styled `Button`, not `Menu`,
    /// since the sheet is presented top-level (`body`'s `.sheet(isPresented:
    /// $isSourceSheetPresented)`), not anchored to this button the way a
    /// `Menu`'s popover would be.
    @ViewBuilder
    private func sourcePickerButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            isSourceSheetPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    /// Bottom sheet listing the 3 page sources — replaced a `Menu` (tried
    /// first) whose compact popover-near-the-button read cramped once
    /// icons were added to every row ("cái này thì bottom sheet đi ổn
    /// hơn đấy"). Compact fixed height, not a default-detent sheet — 3
    /// rows don't need `.medium`/`.large`'s worth of sheet.
    private var sourceOptionsSheet: some View {
        VStack(spacing: 0) {
            sourceRow(icon: "viewfinder", title: "Scan with Camera", isDisabled: !isCameraAvailable) {
                selectSource { isCameraPresented = true }
            }
            Divider().padding(.leading, 56)
            sourceRow(icon: "photo.on.rectangle", title: "Choose from Photos") {
                selectSource { isPhotosPickerPresented = true }
            }
            Divider().padding(.leading, 56)
            sourceRow(icon: "doc.richtext", title: "Choose a PDF") {
                selectSource { isPDFPickerPresented = true }
            }
        }
        // Pushed further per "lùi xuống thêm 1 chút nữa đi" — `xxl` (32),
        // up from `xl` (24).
        .padding(.top, DSSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.dsBackgroundPrimary)
        // Explicit opaque background on the SHEET itself, not just the
        // content — without this, iOS's default sheet chrome at a
        // compact custom `.height()` detent rendered as a translucent
        // card with the page behind bleeding through ("trong quá, khó
        // nhìn"). `RatingDialogView`/`FillFormView`'s sheets look solid
        // by default because they sit inside more standard detents/a
        // `NavigationStack`; this one didn't, so it needs it explicit.
        .presentationBackground(Color.dsBackgroundPrimary)
        // Base 145 came from measuring a real screenshot (content only
        // needed ~137pt). +`xxl` matches the `xxl` top padding above, so
        // pushing the rows down doesn't reopen bottom dead-space.
        .presentationDetents([.height(145 + DSSpacing.xxl)])
        .presentationDragIndicator(.visible)
    }

    private func sourceRow(
        icon: String,
        title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isDisabled ? Color.dsTextDisabled : Color.dsBrandPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(isDisabled ? Color.dsTextDisabled : Color.dsTextPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.lg)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    /// Dismisses the sheet, then fires `trigger` after a short delay —
    /// same shape as the existing camera→Photos handoff below (avoids
    /// racing the sheet's own dismiss animation against whatever
    /// presentation `trigger` starts, e.g. the camera `fullScreenCover`).
    private func selectSource(_ trigger: @escaping () -> Void) {
        isSourceSheetPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            trigger()
        }
    }

    // MARK: - Export format (§6.5)

    private var exportFormatState: some View {
        Form {
            Toggle(isOn: $exportEditableWord) {
                exportOptionLabel(
                    title: "Editable Word",
                    tag: "Recommended",
                    subtitle: "Text you can open & edit — loses original layout"
                )
            }
            Toggle(isOn: $exportSearchablePDF) {
                exportOptionLabel(
                    title: "Searchable PDF",
                    tag: nil,
                    subtitle: "Keeps the original look — find/copy text only, not editable"
                )
            }
        }
    }

    private func exportOptionLabel(title: String, tag: String?, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title).font(DSFont.headline)
                if let tag {
                    Text(tag.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsBrandPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dsBrandPrimarySubtle, in: Capsule())
                }
            }
            Text(subtitle).font(DSFont.footnote).foregroundStyle(Color.dsTextTertiary)
        }
    }

    // MARK: - Actions

    private func performRecognize() async {
        await viewModel.recognize(pages.map(\.image))
        if !viewModel.results.isEmpty {
            selectedPageIndex = 0
            stage = .review
        }
    }

    private func performSave() async {
        // Reentrancy guard — belt-and-braces with the button's `.disabled`
        // check: a fast double-tap can race the Task-launch before SwiftUI
        // repaints the disabled state, so we also gate the async work
        // itself. Same pattern as `PDFToolsViewModel`'s reentrancy guards.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        var urls: [URL] = []
        let stem = "Scan " + Date.now.formatted(.iso8601.year().month().day())
        do {
            if exportEditableWord {
                let destination = FileManager.default.nonConflictingURL(for: "\(stem).docx", in: .documentsDirectory)
                try await viewModel.exportEditableWord(to: destination)
                urls.append(destination)
            }
            if exportSearchablePDF {
                let destination = FileManager.default.nonConflictingURL(for: "\(stem).pdf", in: .documentsDirectory)
                try await viewModel.exportSearchablePDF(to: destination)
                urls.append(destination)
            }
            guard !urls.isEmpty else { return }
            let filename = urls.count == 1 ? urls[0].lastPathComponent : nil
            let title = urls.count == 1
                ? "Your document was saved to your Library"
                : "\(urls.count) files were saved to your Library"
            toaster.show(.success, title: title, filename: filename)
            // Single-file save: navigate directly to the recognized doc.
            // Both-formats save: hand the pair to the gallery so the user
            // can inspect and open each format without hunting in Library.
            if urls.count == 1, let url = urls.first {
                onOpenFile?(url)
            } else {
                onShowGallery?(urls)
            }
            // The Library FAB entry point (`LibraryAddButton`) supplies
            // neither callback — a sheet with no editor/gallery destination
            // reachable from it. Without this, the sheet stayed stuck on
            // `.exportFormat` with Save still enabled against the same
            // already-recognized pages, so a second tap silently wrote a
            // second, distinctly-named export ("Scan 2026-09-05 (2).docx").
            if onOpenFile == nil && onShowGallery == nil {
                dismiss()
            } else {
                // Tools-tab entry (has callbacks): the callback opens the
                // editor or gallery on top, but this view stays alive on
                // the nav stack with `pages`/`results` intact. A second
                // Save tap would export the same recognized pages again
                // under a `(2)` suffix (F5). Clear the recognized state
                // so the export button is `.disabled` and the user has to
                // re-recognize before another Save can fire.
                pages.removeAll()
                viewModel.reset()
                stage = .addPages
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handlePDFPicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            // §7.3 — must run off the caller's actor, same reasoning as
            // PDFKitMerger/PDFKitSplitter: `renderPages` rasterizes every page at
            // 2x scale, which would otherwise block the main thread synchronously.
            let images = await Task.detached(priority: .utility) {
                Self.renderPages(of: url)
            }.value
            pages.append(contentsOf: images.map { ScannedPage(image: $0, source: .pdf) })
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var newPages: [ScannedPage] = []
        // §7.3 "never silent data loss" — a picked photo can fail to load
        // (unsupported format, or an iCloud original that fails to download)
        // and `try?` alone would drop it with zero trace: `pages` just ends
        // up shorter than what the user picked, no error shown anywhere.
        var failedCount = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let cgImage = uiImage.cgImage {
                newPages.append(ScannedPage(image: cgImage, source: .photo))
            } else {
                failedCount += 1
            }
        }
        pages.append(contentsOf: newPages)
        photoItems = []
        if failedCount > 0 {
            viewModel.errorMessage = failedCount == 1
                ? "1 photo couldn't be loaded and was skipped"
                : "\(failedCount) photos couldn't be loaded and were skipped"
        }
    }

    /// Renders every page of an existing PDF picked as a Scan input — always runs
    /// OCR on these regardless of whether the PDF already has a text layer, unlike
    /// "PDF → Word" (which auto-detects and skips OCR when possible): choosing
    /// Scan & OCR here is a deliberate request for the review/confidence flow.
    nonisolated private static func renderPages(of url: URL) -> [CGImage] {
        // Session 19 code-review #4 — security-scope claim required on
        // the external picker URL. `handlePDFPicked` (line 404) dispatches
        // this call into `Task.detached`, which drops the `.fileImporter`
        // transient grant; without the claim, `PDFDocument(url:)` returns
        // nil for iCloud / Files-provider PDFs and Scan silently loads
        // an empty page set instead of raising an error.
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { return [] }
        var images: [CGImage] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            if let cgImage = page.thumbnail(of: targetSize, for: .mediaBox).cgImage {
                images.append(cgImage)
            }
        }
        return images
    }
}
