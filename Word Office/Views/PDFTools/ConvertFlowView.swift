// Sprint 0.3, §7.4 — one view parametrized by `ConvertDirection` rather than 4
// near-identical views: pick → convert → success, only the file-type filter,
// copy, and result kind differ per direction.

import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ConvertFlowView: View {
    @Bindable var viewModel: PDFToolsViewModel
    let direction: ConvertDirection
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(\.dismiss) private var dismiss
    /// Fires after a successful conversion that produces a single output
    /// file — parent uses it to open the result in the editor. Fires for
    /// `officeToPDF`, `pdfToWord`, and `imageToPDF`; the `pdfToImage`
    /// case always uses `onShowGallery` regardless of image count because
    /// images have no in-app editor destination.
    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil
    /// Fires for `pdfToImage` with any output — parent presents
    /// `ToolResultGalleryView` (thumbnail grid) so the user can review
    /// each page, save-all, share-all, or open any single image via
    /// QuickLook. Session 10 gap fix (2026-09-04) — the previous "toast
    /// + stay at picker" behaviour orphaned the export result.
    var onShowGallery: (([URL]) -> Void)? = nil
    /// Called after a successful officeToPDF conversion — parent can push
    /// the Sign destination with the result pre-selected, skipping the
    /// cabinet re-pick. Only wired for officeToPDF; other directions stay nil.
    var onSign: ((URL) -> Void)? = nil
    /// Called after a successful officeToPDF conversion — parent can push
    /// the Print destination with the result pre-selected.
    var onPrint: ((URL) -> Void)? = nil

    // Office→PDF / PDF→Word
    @State private var singleFileURL: URL?
    @State private var needsOCRNotice: Bool?
    /// Bound to ToolsTabView's `officeToPDFResult` for officeToPDF — allows
    /// Sign (when invoked from the success screen) to update the preview by
    /// writing the signed URL back through the binding. For all other directions
    /// this binding is `.constant(nil)` and no writes are observed.
    @Binding var conversionResult: URL?
    /// Bound to ToolsTabView's `imageToPDFSignedResult` — when Sign
    /// auto-commits a signed PDF from the imageToPDF success screen, the
    /// committed URL flows in here and `imageToPDFCommittedURL` is updated
    /// so the preview refreshes to the signed version.
    var imageToPDFSignedResult: Binding<URL?> = .constant(nil)

    // PDF→Image — gallery managed internally so Done can reset to Cabinet
    @State private var isGalleryPresented = false
    @State private var galleryURLs: [URL] = []
    @State private var pendingGalleryEditorURL: URL?

    @State private var pageRangeAll = true
    @State private var fromPage = 1
    @State private var toPage = 1
    @State private var pageCount = 1

    // Image→PDF
    /// Wraps a picked photo with a stable identity — `UIImage` isn't
    /// `Identifiable`/`Hashable`, and array index/offset as `ForEach` id breaks
    /// on delete/reorder (SwiftUI reuses the wrong row's identity for whatever
    /// shifted into that offset).
    private struct SelectedImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var images: [SelectedImage] = []
    /// Staged temp URL from `convertImagesToPDFToTemp` — non-nil = show
    /// preview screen. User taps Continue to commit to Library, or back chevron
    /// to discard and return to the photo list.
    @State private var imageToPDFStagedURL: URL?
    /// Set after `commitImagesPDF` succeeds — shows Sign/Print/Done success screen.
    @State private var imageToPDFCommittedURL: URL?
    /// True while auto-converting from the browse path so `stateContent`
    /// stays blank (processing overlay covers). Prevents the "1 file selected"
    /// intermediate screen from flashing into view.
    @State private var isDirectConverting = false

    @Environment(LibraryStore.self) private var store

    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var didAutoPresent = false

    /// Identifies exactly what a successful convert ran on, so re-tapping
    /// "Convert" on that same unchanged input can be disabled — the picker
    /// deliberately stays populated after success (see `stateContent`'s
    /// comment) so the user can re-convert with different options without
    /// re-navigating, but tapping it again with NOTHING changed used to
    /// silently write a second, distinctly-named output file.
    private enum ConvertSnapshot: Equatable {
        case singleFile(URL)
        case pdfToImageRange(URL, ClosedRange<Int>?)
        case images([UUID])
    }
    @State private var lastConvertedSnapshot: ConvertSnapshot?

    private var currentSnapshot: ConvertSnapshot? {
        switch direction {
        case .officeToPDF, .pdfToWord:
            guard let singleFileURL else { return nil }
            return .singleFile(singleFileURL)
        case .pdfToImage:
            guard let singleFileURL else { return nil }
            let range: ClosedRange<Int>? = pageRangeAll ? nil : (min(fromPage, toPage) - 1)...(max(fromPage, toPage) - 1)
            return .pdfToImageRange(singleFileURL, range)
        case .imageToPDF:
            return images.isEmpty ? nil : .images(images.map(\.id))
        }
    }

    var body: some View {
        Group {
            if isLibraryPickerPresented || (initialSource == .library && !didAutoPresent) {
                InlineCabinetPicker(
                    entries: store.entries,
                    filter: libraryFilter,
                    allowsMultipleSelection: false,
                    emptyTitle: libraryEmptyTitle,
                    emptyMessage: libraryEmptyMessage
                ) { urls in
                    guard let url = urls.first else { return }
                    // Auto-converting directions keep the cabinet visible behind
                    // the processing overlay; handleFilePicked controls when to
                    // flip isLibraryPickerPresented after conversion completes.
                    if direction == .imageToPDF {
                        isLibraryPickerPresented = false
                    }
                    handleFilePicked(.success(url))
                } onCancel: {
                    if conversionResult != nil {
                        // Result screen is pending; cabinet was opened for some other
                        // reason — just close cabinet to reveal the result screen.
                        isLibraryPickerPresented = false
                    } else if singleFileURL == nil || direction == .officeToPDF {
                        dismiss()
                    } else {
                        isLibraryPickerPresented = false
                    }
                } onBrowse: {
                    isPickerPresented = true
                }
            } else {
                stateContent
            }
        }
        .prominentInlineTitle(isLibraryPickerPresented ? "Cabinet" : direction.title)
        .navigationBarBackButtonHidden(
            isDirectConverting ||
            isLibraryPickerPresented ||
            (!didAutoPresent && initialSource == .library) ||
            (singleFileURL != nil && initialSource == .library && direction != .officeToPDF && direction != .pdfToWord) ||
            (conversionResult != nil && initialSource == .library) ||
            (direction == .imageToPDF && imageToPDFStagedURL != nil) ||
            (direction == .imageToPDF && imageToPDFCommittedURL != nil)
        )
        .toolbar { toolbarContent }
        .sheet(isPresented: $isGalleryPresented, onDismiss: handleGalleryDismissed) {
            ToolResultGalleryView(
                urls: galleryURLs,
                onOpenFile: { url in pendingGalleryEditorURL = url },
                onDone: {
                    // Update state on Done tap (before dismiss animation completes)
                    // so the underlying view already shows the cabinet by the time
                    // the sheet finishes animating out — prevents the stateContent
                    // from flashing through during the sheet dismiss.
                    singleFileURL = nil
                    if initialSource == .library { isLibraryPickerPresented = true }
                },
                onSaveAll: {
                    let finals = await viewModel.commitPDFToImages(galleryURLs)
                    if !finals.isEmpty {
                        finals.forEach { store.markAsNew($0) }
                        let count = finals.count
                        toaster.show(.success, title: "\(count) image\(count == 1 ? "" : "s") saved to your Library")
                        galleryURLs = finals
                    }
                }
            )
            .toastHost(toaster)
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: fileImporterTypes, onCompletion: handleFilePicked)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          title: sourcePickerTitle,
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent else { return }
            didAutoPresent = true
            guard direction != .imageToPDF else { return }
            switch initialSource {
            case .prePickedURLs(let urls):
                singleFileURL = urls.first
                guard singleFileURL != nil else { return }
                // Suppress stateContent during auto-convert from pre-picked path.
                isDirectConverting = true
                await performConvert()
                isDirectConverting = false
                // Staged flows show their own result screen (officeToPDF/pdfToWord)
                // or gallery sheet (pdfToImage) — do NOT dismiss here.
            case .library:
                guard singleFileURL == nil else { return }
                isLibraryPickerPresented = true
            case .browse:
                isPickerPresented = true
            case nil:
                guard singleFileURL == nil else { return }
                isSourcePickerPresented = true
            }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadImages(items) }
        }
        .onChange(of: imageToPDFSignedResult.wrappedValue) { _, url in
            guard let url else { return }
            imageToPDFCommittedURL = url
            imageToPDFSignedResult.wrappedValue = nil
            // Reset so Convert re-enables after sign (user can create a fresh
            // unsigned PDF from the same photos if they want).
            lastConvertedSnapshot = nil
        }
        .overlay { processingOverlay }
        .errorAlert($viewModel.errorMessage)
        // `viewModel` (`pdfToolsVM`) is shared across Merge/Split/
        // Convert (all 4 directions)/Print — a failure left over from
        // whichever the user visited last otherwise pops up here as if
        // it were this direction's error.
        .onAppear { viewModel.errorMessage = nil }
    }

    // Split out of `body` — the type-checker was timing out trying to solve the
    // branching content together with the long modifier chain in one expression.
    // No `didFinish` branch: success is a toast (see `performConvert`) and the
    // picker stays visible with the file still selected so the user can
    // re-convert with different options or pick a new file without navigating
    // back and re-tapping the tool card.
    @ViewBuilder
    private var stateContent: some View {
        if isDirectConverting {
            // Keep background blank while processing overlay is active —
            // prevents the "1 file selected" form from flashing into view
            // during auto-convert from the browse path.
            Color.dsBackgroundSecondary.ignoresSafeArea()
        } else {
            switch direction {
            case .officeToPDF, .pdfToWord:
                singleFileState
            case .pdfToImage:
                pdfToImageState
            case .imageToPDF:
                if let committedURL = imageToPDFCommittedURL {
                    imageToPDFSuccessView(committedURL)
                } else {
                    imageToPDFState
                }
            }
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        if viewModel.isProcessing {
            ProcessingOverlay(title: "Converting", subtitle: singleFileURL?.lastPathComponent)
        }
    }

    // MARK: - Toolbar
    //
    // Factored into its own `@ToolbarContentBuilder` property rather than an
    // inline `.toolbar { if !didFinish { ... } }` closure — the long modifier
    // chain on `body` combined with conditional `ToolbarItem`s inline made the
    // type-checker time out ("unable to type-check this expression in reasonable
    // time"); splitting it out gives it a smaller expression to solve.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Back from officeToPDF success screen → cabinet (library source).
        if direction == .officeToPDF, conversionResult != nil, initialSource == .library {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if let url = conversionResult {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                        conversionResult = nil
                    }
                    singleFileURL = nil
                    isLibraryPickerPresented = true
                } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        // Back from file-selected state → cabinet (pdfToImage from library).
        if singleFileURL != nil && !isLibraryPickerPresented && initialSource == .library
            && direction == .pdfToImage {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    singleFileURL = nil
                    isLibraryPickerPresented = true
                } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        // Back from imageToPDF success screen → photo list.
        if direction == .imageToPDF, imageToPDFCommittedURL != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    imageToPDFCommittedURL = nil
                    images = []
                } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        // Back from imageToPDF preview → photo list (discard staged temp file).
        if direction == .imageToPDF, imageToPDFStagedURL != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if let url = imageToPDFStagedURL {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                        imageToPDFStagedURL = nil
                    }
                    lastConvertedSnapshot = nil
                } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        // Convert button — only for directions that need manual confirmation
        // (pdfToImage page-range form, imageToPDF photo list).
        // officeToPDF and pdfToWord auto-convert on file pick, so they never
        // show the Convert button.
        if !isLibraryPickerPresented
            && (direction == .pdfToImage || direction == .imageToPDF)
            && imageToPDFStagedURL == nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Convert") { Task { await performConvert() } }
                    .fontWeight(.semibold)
                    .disabled(!canConvert || viewModel.isProcessing || currentSnapshot == lastConvertedSnapshot)
            }
        }
    }

    // MARK: - Office→PDF / PDF→Word

    /// Success screen shown after officeToPDF converts — lets the user Sign,
    /// Print, or dismiss without re-navigating to a separate tool.
    @ViewBuilder
    private func officeToPDFSuccessView(_ url: URL) -> some View {
        VStack(spacing: 0) {
            // Compact header
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.dsBrandPrimary)
                VStack(spacing: 2) {
                    Text("PDF created")
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(url.lastPathComponent)
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.lg)
                }
            }
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)

            // PDF preview fills the middle
            PDFFirstPagePreview(url: url)
                .background(Color.dsBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .stroke(Color.dsBorderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, DSSpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Action buttons
            VStack(spacing: DSSpacing.xs) {
                if let onSign {
                    Button { onSign(url) } label: {
                        Label("Sign PDF", systemImage: "signature")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
                if let onPrint {
                    Button { onPrint(url) } label: {
                        Label("Print", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
                Button {
                    Task {
                        if let finalURL = await viewModel.commitToPDF(url) {
                            store.markAsNew(finalURL)
                            toaster.show(.success, title: "Your PDF was saved to your Library", filename: finalURL.lastPathComponent)
                        }
                        conversionResult = nil
                        singleFileURL = nil
                        if initialSource == .library {
                            isLibraryPickerPresented = true
                        } else {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.dsBrandPrimary)
                .disabled(viewModel.isProcessing)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.lg)
        }
    }

    private var singleFileState: some View {
        Group {
            if direction == .officeToPDF, let resultURL = conversionResult {
                officeToPDFSuccessView(resultURL)
            } else if let singleFileURL {
                List {
                    Section("1 file selected") {
                        DSFileRow(ref: DocumentRef(name: singleFileURL.lastPathComponent, url: singleFileURL, modifiedAt: singleFileURL.contentModificationDateOrNow, kind: DocumentKind(rawValue: singleFileURL.pathExtension.lowercased()) ?? (direction == .officeToPDF ? .docx : .pdf)))
                    }
                    if direction == .pdfToWord {
                        Section {
                            Label(
                                needsOCRNoticeText,
                                systemImage: needsOCRNoticeIcon
                            )
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextPrimary)
                        }
                        .listRowBackground(needsOCRNoticeBackground)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "doc.badge.arrow.up",
                    title: "Choose a file",
                    message: direction == .officeToPDF
                        ? "Pick a Word, Excel, or PowerPoint file to convert to PDF"
                        : "Pick a PDF file to convert to Word",
                    action: ("Choose a File", { isSourcePickerPresented = true })
                )
            }
        }
    }

    // MARK: - PDF→Image

    private var pdfToImageState: some View {
        Group {
            if let singleFileURL {
                Form {
                    Section {
                        DSFileRow(ref: DocumentRef(name: singleFileURL.lastPathComponent, url: singleFileURL, modifiedAt: singleFileURL.contentModificationDateOrNow, kind: .pdf))
                    }
                    Section("Pages to export") {
                        Toggle("All pages", isOn: $pageRangeAll)
                        if !pageRangeAll {
                            Stepper("From page \(fromPage)", value: $fromPage, in: 1...pageCount)
                            Stepper("To page \(toPage)", value: $toPage, in: 1...pageCount)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    icon: "doc.badge.arrow.up",
                    title: "Choose a PDF",
                    message: "Pick a file, then choose which pages to export as images",
                    action: ("Choose a File", { isSourcePickerPresented = true })
                )
            }
        }
    }

    // MARK: - Image→PDF

    private var imageToPDFState: some View {
        Group {
            if let stagedURL = imageToPDFStagedURL {
                imageToPDFPreviewView(stagedURL)
            } else if images.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "Add photos",
                    message: "Choose the photos you want combined into one PDF, in order",
                    action: ("Choose photos", { isPhotoPickerPresented = true })
                )
                .photosPicker(isPresented: $isPhotoPickerPresented,
                              selection: $photoItems,
                              matching: .images)
            } else {
                List {
                    Section("\(images.count) photos · will merge in this order") {
                        ForEach(images) { entry in
                            HStack(spacing: DSSpacing.sm) {
                                Image(uiImage: entry.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)
                                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
                                Text("Photo \((images.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1)").font(DSFont.headline)
                                Spacer()
                            }
                        }
                        .onDelete { images.remove(atOffsets: $0) }
                        .onMove { images.move(fromOffsets: $0, toOffset: $1) }

                        PhotosPicker(selection: $photoItems, matching: .images) {
                            Label("Add more photos", systemImage: "plus")
                        }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            }
        }
    }

    @ViewBuilder
    private func imageToPDFPreviewView(_ url: URL) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.dsBrandPrimary)
                VStack(spacing: 2) {
                    Text("PDF ready")
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("\(images.count) photo\(images.count == 1 ? "" : "s") combined")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)

            PDFFirstPagePreview(url: url)
                .background(Color.dsBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .stroke(Color.dsBorderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, DSSpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                Task { await commitImagesToPDF() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .disabled(viewModel.isProcessing)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.lg)
        }
    }

    /// Success screen shown after Image→PDF is committed to Library.
    /// Mirrors `officeToPDFSuccessView` — Sign / Print / Done buttons.
    @ViewBuilder
    private func imageToPDFSuccessView(_ url: URL) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.dsBrandPrimary)
                VStack(spacing: 2) {
                    Text("PDF ready")
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("\(images.count) photo\(images.count == 1 ? "" : "s") combined")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)

            PDFFirstPagePreview(url: url)
                .background(Color.dsBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .stroke(Color.dsBorderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, DSSpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: DSSpacing.xs) {
                if let onSign {
                    Button { onSign(url) } label: {
                        Label("Sign PDF", systemImage: "signature")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
                if let onPrint {
                    Button { onPrint(url) } label: {
                        Label("Print", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.lg)
        }
    }

    /// `nil` means `checkNeedsOCR` itself failed (e.g. corrupted PDF) — shown as
    /// its own neutral notice rather than defaulting to the "has text" copy,
    /// which would otherwise read as a confident answer to a check that never
    /// actually completed.
    private var needsOCRNoticeText: String {
        switch needsOCRNotice {
        case true:  "No selectable text found — this looks like a scanned PDF. We'll recognize the text first (may take longer)"
        case false: "Only the text will be kept — formatting, images, and tables won't carry over"
        case nil:   "Couldn't inspect this file ahead of time — we'll try converting it directly"
        }
    }

    private var needsOCRNoticeIcon: String {
        switch needsOCRNotice {
        case true:  "info.circle"
        case false: "exclamationmark.triangle.fill"
        case nil:   "questionmark.circle"
        }
    }

    private var needsOCRNoticeBackground: Color {
        switch needsOCRNotice {
        case true:  Color.dsBrandPrimarySubtle
        case false: Color.dsStatusWarningBackground
        case nil:   Color.dsSurfaceSecondary
        }
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        switch direction {
        case .officeToPDF:
            // Cabinet stays visible (overlay on top) while converting to temp.
            // On success: flip to success screen. On failure: cabinet stays for retry.
            singleFileURL = url
            Task {
                if let tempURL = await viewModel.convertToPDFToTemp(url) {
                    conversionResult = tempURL
                }
                isLibraryPickerPresented = false
            }
        case .pdfToWord:
            if initialSource == .library {
                // Library: cabinet stays visible behind overlay; convert + commit directly.
                singleFileURL = url
                Task {
                    if let tempURL = await viewModel.convertPDFToWordToTemp(url),
                       let finalURL = await viewModel.commitPDFToWord(tempURL) {
                        store.markAsNew(finalURL)
                        singleFileURL = nil
                        // Keep isLibraryPickerPresented = true so the cabinet stays
                        // visible beneath the editor sheet — no flash of stateContent
                        // between cabinet and editor, and Done in the editor returns
                        // straight back to the cabinet instead of Tools home.
                        onOpenFile?(finalURL)
                    } else {
                        singleFileURL = nil
                        isLibraryPickerPresented = false
                    }
                }
            } else {
                // Browse: auto-convert + commit, then open in editor.
                isDirectConverting = true
                singleFileURL = url
                Task {
                    if let tempURL = await viewModel.convertPDFToWordToTemp(url),
                       let finalURL = await viewModel.commitPDFToWord(tempURL) {
                        store.markAsNew(finalURL)
                        singleFileURL = nil
                        isDirectConverting = false
                        onOpenFile?(finalURL)
                    } else {
                        singleFileURL = nil
                        isDirectConverting = false
                        dismiss()
                    }
                }
            }
        case .pdfToImage:
            if initialSource == .library {
                // Library: cabinet stays visible behind overlay; convert to temp.
                // Gallery shows after conversion — no toast until Save All is tapped.
                singleFileURL = url
                pageCount = PDFPageCounter.pageCount(of: url)
                toPage = pageCount
                Task {
                    let tempURLs = await viewModel.convertPDFToImagesToTemp(url, pageRange: nil)
                    singleFileURL = nil
                    isLibraryPickerPresented = false
                    guard !tempURLs.isEmpty else { return }
                    lastConvertedSnapshot = .pdfToImageRange(url, nil)
                    galleryURLs = tempURLs
                    isGalleryPresented = true
                }
            } else {
                // Browse: show page-range form; user taps Convert to proceed.
                isLibraryPickerPresented = false
                singleFileURL = url
                pageCount = PDFPageCounter.pageCount(of: url)
                toPage = pageCount
            }
        case .imageToPDF:
            isLibraryPickerPresented = false
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [SelectedImage] = []
        // §7.3 "never silent data loss" — a picked photo can fail to load
        // (unsupported format, or an iCloud original that fails to download)
        // and `try?` alone would drop it with zero trace: `images` just
        // ends up shorter than what the user picked, no error shown
        // anywhere. Mirrors the Session 13 fix in `ScanFlowView.loadPhotos`
        // that this loader was missed by.
        var failedCount = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(SelectedImage(image: image))
            } else {
                failedCount += 1
            }
        }
        images.append(contentsOf: loaded)
        photoItems = []
        if failedCount > 0 {
            viewModel.errorMessage = failedCount == 1
                ? "1 photo couldn't be loaded and was skipped"
                : "\(failedCount) photos couldn't be loaded and were skipped"
        }
    }

    // MARK: - Actions

    private func handleGalleryDismissed() {
        if let url = pendingGalleryEditorURL {
            pendingGalleryEditorURL = nil
            onOpenFile?(url)
        }
        // Library navigation is handled immediately in the gallery's onDone callback
        // (before the sheet animation completes) to prevent stateContent from
        // flashing through during dismissal.
    }

    private var canConvert: Bool {
        switch direction {
        case .officeToPDF, .pdfToWord, .pdfToImage: singleFileURL != nil
        case .imageToPDF: !images.isEmpty
        }
    }

    private func performConvert() async {
        let snapshot = currentSnapshot
        switch direction {
        case .officeToPDF:
            guard let singleFileURL else { return }
            if let tempURL = await viewModel.convertToPDFToTemp(singleFileURL) {
                lastConvertedSnapshot = snapshot
                conversionResult = tempURL
            }
        case .pdfToWord:
            guard let singleFileURL else { return }
            if let tempURL = await viewModel.convertPDFToWordToTemp(singleFileURL),
               let finalURL = await viewModel.commitPDFToWord(tempURL) {
                store.markAsNew(finalURL)
                lastConvertedSnapshot = snapshot
                self.singleFileURL = nil
                onOpenFile?(finalURL)
            }
        case .pdfToImage:
            guard let singleFileURL else { return }
            let range: ClosedRange<Int>? = pageRangeAll ? nil : (min(fromPage, toPage) - 1)...(max(fromPage, toPage) - 1)
            let tempURLs = await viewModel.convertPDFToImagesToTemp(singleFileURL, pageRange: range)
            guard !tempURLs.isEmpty else { return }
            lastConvertedSnapshot = snapshot
            // No toast here — user must tap Save All in the gallery to commit.
            galleryURLs = tempURLs
            isGalleryPresented = true
        case .imageToPDF:
            if let tempURL = await viewModel.convertImagesToPDFToTemp(images.map(\.image)),
               let finalURL = await viewModel.commitImagesPDF(tempURL) {
                store.markAsNew(finalURL)
                lastConvertedSnapshot = snapshot
                imageToPDFCommittedURL = finalURL
                toaster.show(.success, title: "PDF saved to your Library", filename: finalURL.lastPathComponent)
            }
        }
    }

    private func commitImagesToPDF() async {
        guard let tempURL = imageToPDFStagedURL else { return }
        if let finalURL = await viewModel.commitImagesPDF(tempURL) {
            store.markAsNew(finalURL)
            imageToPDFStagedURL = nil
            lastConvertedSnapshot = nil
            // Show success screen (Sign / Print / Done) — mirroring the
            // officeToPDF pattern so user can sign or print the fresh PDF.
            imageToPDFCommittedURL = finalURL
        }
    }

    private var sourcePickerTitle: LocalizedStringKey {
        switch direction {
        case .officeToPDF: "Choose a file to convert"
        case .pdfToWord:   "Choose a PDF to convert"
        case .pdfToImage:  "Choose a PDF to export"
        case .imageToPDF:  "Add photos to convert"
        }
    }

    private var fileImporterTypes: [UTType] {
        switch direction {
        case .officeToPDF: [
            UTType("org.openxmlformats.wordprocessingml.document"),
            UTType("com.microsoft.word.doc"),
            .rtf, .plainText,
        ].compactMap { $0 }
        case .pdfToWord, .pdfToImage: [.pdf]
        case .imageToPDF: []
        }
    }

    private var libraryFilter: (LibraryEntry) -> Bool {
        switch direction {
        case .officeToPDF: return { $0.document.kind == .docx || $0.document.kind == .doc || $0.document.kind == .rtf || $0.document.kind == .txt || $0.document.kind == .markdown }
        case .pdfToWord, .pdfToImage: return { $0.document.kind == .pdf }
        case .imageToPDF: return { _ in false }
        }
    }

    private var libraryEmptyTitle: String {
        switch direction {
        case .officeToPDF: return "No Word documents in Library"
        case .pdfToWord, .pdfToImage: return "No PDFs in Library"
        case .imageToPDF: return "No files in Library"
        }
    }

    private var libraryEmptyMessage: String {
        switch direction {
        case .officeToPDF: return "Import a Word document first."
        case .pdfToWord, .pdfToImage: return "Import PDF files first, then come back."
        case .imageToPDF: return "Import files first, then come back."
        }
    }
}

// MARK: - PDF first-page preview

/// Non-interactive single-page PDFView used in the officeToPDF success screen.
private struct PDFFirstPagePreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
