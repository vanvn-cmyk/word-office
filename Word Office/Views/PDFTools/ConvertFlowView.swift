// Sprint 0.3, §7.4 — one view parametrized by `ConvertDirection` rather than 4
// near-identical views: pick → convert → success, only the file-type filter,
// copy, and result kind differ per direction.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ConvertFlowView: View {
    @Bindable var viewModel: PDFToolsViewModel
    let direction: ConvertDirection
    @Environment(\.dismiss) private var dismiss

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

    @State private var isPickerPresented = false
    @State private var didFinish = false

    var body: some View {
        stateContent
            .navigationTitle(direction.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: fileImporterTypes, onCompletion: handleFilePicked)
            .onChange(of: photoItems) { _, items in
                Task { await loadImages(items) }
            }
            .overlay { processingOverlay }
            .errorAlert($viewModel.errorMessage)
    }

    // Split out of `body` — the type-checker was timing out trying to solve the
    // branching content together with the long modifier chain in one expression.
    @ViewBuilder
    private var stateContent: some View {
        if didFinish {
            successState
        } else {
            switch direction {
            case .officeToPDF, .pdfToWord:
                singleFileState
            case .pdfToImage:
                pdfToImageState
            case .imageToPDF:
                imageToPDFState
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
        if !didFinish {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Convert") { Task { await performConvert() } }
                    .fontWeight(.semibold)
                    .disabled(!canConvert || viewModel.isProcessing)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    // MARK: - Office→PDF / PDF→Word

    private var singleFileState: some View {
        Group {
            if let singleFileURL {
                List {
                    Section("1 file selected") {
                        DSFileRow(ref: DocumentRef(name: singleFileURL.lastPathComponent, url: singleFileURL, modifiedAt: .now, kind: direction == .officeToPDF ? .docx : .pdf))
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
                    action: ("Choose a file", { isPickerPresented = true })
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
                        DSFileRow(ref: DocumentRef(name: singleFileURL.lastPathComponent, url: singleFileURL, modifiedAt: .now, kind: .pdf))
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
                    action: ("Choose a file", { isPickerPresented = true })
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
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(SelectedImage(image: image))
            }
        }
        images.append(contentsOf: loaded)
        photoItems = []
    }

    // MARK: - Success

    private var successState: some View {
        VStack(spacing: DSSpacing.lg) {
            switch direction {
            case .officeToPDF, .pdfToWord, .imageToPDF:
                if let url = viewModel.lastConvertedURL {
                    SuccessBadge(title: "Converted successfully", subtitle: "Saved to your Documents — it'll show up in Library too")
                    DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: .now, kind: direction == .pdfToWord ? .docx : .pdf))
                        .padding(DSSpacing.sm)
                        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                }
            case .pdfToImage:
                SuccessBadge(title: "Exported \(viewModel.lastImageExportURLs.count) images", subtitle: "Saved to your Documents")
                List {
                    ForEach(viewModel.lastImageExportURLs, id: \.self) { url in
                        Text(url.lastPathComponent).font(DSFont.subheadline)
                    }
                }
                .listStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, DSSpacing.md)
        .padding(.horizontal, DSSpacing.md)
        .navigationBarBackButtonHidden()
    }

    // MARK: - Actions

    private var canConvert: Bool {
        switch direction {
        case .officeToPDF, .pdfToWord, .pdfToImage: singleFileURL != nil
        case .imageToPDF: !images.isEmpty
        }
    }

    private func performConvert() async {
        switch direction {
        case .officeToPDF:
            guard let singleFileURL else { return }
            await viewModel.convertToPDF(singleFileURL)
            if viewModel.lastConvertedURL != nil { didFinish = true }
        case .pdfToWord:
            guard let singleFileURL else { return }
            await viewModel.convertPDFToWord(singleFileURL)
            if viewModel.lastConvertedURL != nil { didFinish = true }
        case .pdfToImage:
            guard let singleFileURL else { return }
            let range: ClosedRange<Int>? = pageRangeAll ? nil : (min(fromPage, toPage) - 1)...(max(fromPage, toPage) - 1)
            await viewModel.convertPDFToImages(singleFileURL, pageRange: range)
            if !viewModel.lastImageExportURLs.isEmpty { didFinish = true }
        case .imageToPDF:
            await viewModel.convertImagesToPDF(images.map(\.image))
            if viewModel.lastConvertedURL != nil { didFinish = true }
        }
    }

    private var fileImporterTypes: [UTType] {
        switch direction {
        case .officeToPDF: AddFileMenu.supportedTypes.filter { $0 != .pdf }
        case .pdfToWord, .pdfToImage: [.pdf]
        case .imageToPDF: []
        }
    }
}
