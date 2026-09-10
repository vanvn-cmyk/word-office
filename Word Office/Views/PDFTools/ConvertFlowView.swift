// Sprint 0.3, §7.4 — one view parametrized by `ConvertDirection` rather than 4
// near-identical views: pick → convert → success, only the file-type filter,
// copy, and result kind differ per direction.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ConvertFlowView: View {
    @Bindable var viewModel: PDFToolsViewModel
    let direction: ConvertDirection
    @Environment(DSToastPresenter.self) private var toaster
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

    // Office→PDF / PDF→Word
    @State private var singleFileURL: URL?
    @State private var needsOCRNotice: Bool?

    // PDF→Image
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

    @Environment(LibraryStore.self) private var store

    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
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
        stateContent
            .prominentInlineTitle(direction.title)
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: fileImporterTypes, onCompletion: handleFilePicked)
            .sheet(isPresented: $isLibraryPickerPresented) {
                LibraryFilePicker(
                    entries: store.entries,
                    filter: libraryFilter,
                    allowsMultipleSelection: false,
                    emptyTitle: libraryEmptyTitle,
                    emptyMessage: libraryEmptyMessage
                ) { urls in
                    guard let url = urls.first else { return }
                    handleFilePicked(.success(url))
                }
            }
            .fileSourcePicker(isPresented: $isSourcePickerPresented,
                              onLibrary: { isLibraryPickerPresented = true },
                              onBrowse: { isPickerPresented = true })
            .task {
                // `initialSource` is set by ToolsTabView before navigating here
                // (user already chose Library or Browse from the Tools tab sheet).
                // Open the appropriate picker directly — no intermediate sheet.
                guard !didAutoPresent, let source = initialSource, singleFileURL == nil else { return }
                didAutoPresent = true
                switch source {
                case .library: isLibraryPickerPresented = true
                case .browse:  isPickerPresented = true
                }
            }
            .onChange(of: photoItems) { _, items in
                Task { await loadImages(items) }
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
        switch direction {
        case .officeToPDF, .pdfToWord:
            singleFileState
        case .pdfToImage:
            pdfToImageState
        case .imageToPDF:
            imageToPDFState
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
        // No explicit Cancel — this view is only reached via `NavigationLink`
        // push from `ToolsTabView`, so the system back chevron already covers
        // dismissal. Adding a leading Cancel next to it reads as a duplicate.
        //
        // No "Done" branch either — success shows a toast (see `performConvert`)
        // and the Convert button stays available for re-convert; the user
        // navigates back via the system chevron when finished.
        ToolbarItem(placement: .confirmationAction) {
            Button("Convert") { Task { await performConvert() } }
                .fontWeight(.semibold)
                .disabled(!canConvert || viewModel.isProcessing || currentSnapshot == lastConvertedSnapshot)
        }
    }

    // MARK: - Office→PDF / PDF→Word

    private var singleFileState: some View {
        Group {
            if let singleFileURL {
                List {
                    Section("1 file selected") {
                        DSFileRow(ref: DocumentRef(name: singleFileURL.lastPathComponent, url: singleFileURL, modifiedAt: singleFileURL.contentModificationDateOrNow, kind: direction == .officeToPDF ? .docx : .pdf))
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
            if images.isEmpty {
                VStack(spacing: DSSpacing.md) {
                    EmptyStateView(icon: "photo.on.rectangle", title: "Add photos", message: "Choose the photos you want combined into one PDF, in order")
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Text("Choose photos")
                    }
                    .buttonStyle(.borderedProminent)
                }
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
        case .officeToPDF, .pdfToWord:
            singleFileURL = url
            if direction == .pdfToWord {
                needsOCRNotice = nil
                Task { needsOCRNotice = await viewModel.checkNeedsOCR(url) }
            }
        case .pdfToImage:
            singleFileURL = url
            pageCount = PDFPageCounter.pageCount(of: url)
            toPage = pageCount
        case .imageToPDF:
            break
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
            await viewModel.convertToPDF(singleFileURL)
            if let url = viewModel.lastConvertedURL {
                lastConvertedSnapshot = snapshot
                toaster.show(.success, title: "Your document was saved to your Library", filename: url.lastPathComponent)
                onOpenFile?(url)
            }
        case .pdfToWord:
            guard let singleFileURL else { return }
            await viewModel.convertPDFToWord(singleFileURL)
            if let url = viewModel.lastConvertedURL {
                lastConvertedSnapshot = snapshot
                toaster.show(.success, title: "Your document was saved to your Library", filename: url.lastPathComponent)
                onOpenFile?(url)
            }
        case .pdfToImage:
            guard let singleFileURL else { return }
            let range: ClosedRange<Int>? = pageRangeAll ? nil : (min(fromPage, toPage) - 1)...(max(fromPage, toPage) - 1)
            await viewModel.convertPDFToImages(singleFileURL, pageRange: range)
            let outputs = viewModel.lastImageExportURLs
            guard !outputs.isEmpty else { return }
            lastConvertedSnapshot = snapshot
            let count = outputs.count
            toaster.show(.success, title: "\(count) image\(count == 1 ? "" : "s") saved to your Library")
            // Always gallery for images — no editor destination even for
            // a single image, and the thumbnail grid is the natural way
            // to review a page-by-page export.
            onShowGallery?(outputs)
        case .imageToPDF:
            await viewModel.convertImagesToPDF(images.map(\.image))
            if let url = viewModel.lastConvertedURL {
                lastConvertedSnapshot = snapshot
                toaster.show(.success, title: "Your document was saved to your Library", filename: url.lastPathComponent)
                onOpenFile?(url)
            }
        }
    }

    private var fileImporterTypes: [UTType] {
        switch direction {
        case .officeToPDF: AddFileMenu.supportedTypes.filter { $0 != .pdf }
        case .pdfToWord, .pdfToImage: [.pdf]
        case .imageToPDF: []
        }
    }

    private var libraryFilter: (LibraryEntry) -> Bool {
        switch direction {
        case .officeToPDF: return { $0.document.kind != .pdf }
        case .pdfToWord, .pdfToImage: return { $0.document.kind == .pdf }
        case .imageToPDF: return { _ in false }
        }
    }

    private var libraryEmptyTitle: String {
        switch direction {
        case .officeToPDF: return "No Office documents in Library"
        case .pdfToWord, .pdfToImage: return "No PDFs in Library"
        case .imageToPDF: return "No files in Library"
        }
    }

    private var libraryEmptyMessage: String {
        switch direction {
        case .officeToPDF: return "Import Word, Excel, or PowerPoint files first."
        case .pdfToWord, .pdfToImage: return "Import PDF files first, then come back."
        case .imageToPDF: return "Import files first, then come back."
        }
    }
}
