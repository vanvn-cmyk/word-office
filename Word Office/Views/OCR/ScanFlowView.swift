// Sprint 0.3, §6 — 3 input sources (camera / Photos / existing PDF) all converge
// on OCRViewModel.recognize(_:), then a dual export step (editable .docx primary,
// searchable PDF secondary/optional) per §6.5.

import PDFKit
import PhotosUI
import SwiftUI

struct ScanFlowView: View {
    @Bindable var viewModel: OCRViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case addPages, review, exportFormat, success
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedPageIndex = 0
    @State private var exportEditableWord = true
    @State private var exportSearchablePDF = false
    @State private var savedURLs: [URL] = []

    var body: some View {
        stateContent
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $isCameraPresented) { cameraSheet }
            .fileImporter(isPresented: $isPDFPickerPresented, allowedContentTypes: [.pdf], onCompletion: handlePDFPicked)
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .overlay { processingOverlay }
            .errorAlert($viewModel.errorMessage)
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
        case .success:
            successState
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
        DocumentCameraScanner(
            onFinish: { images in
                pages.append(contentsOf: images.map { ScannedPage(image: $0, source: .camera) })
                isCameraPresented = false
            },
            onCancel: { isCameraPresented = false }
        )
        .ignoresSafeArea()
    }

    private var navigationTitle: String {
        switch stage {
        case .addPages: pages.isEmpty ? "Scan & OCR" : "\(pages.count) page\(pages.count == 1 ? "" : "s")"
        case .review: "Review"
        case .exportFormat: "Export as"
        case .success: "Scan & OCR"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch stage {
        case .addPages:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
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
                    .disabled(!(exportEditableWord || exportSearchablePDF))
            }
        case .success:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
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
        VStack(spacing: DSSpacing.md) {
            EmptyStateView(
                icon: "viewfinder",
                title: "Add pages to recognize",
                message: "We'll turn it into text you can edit, search, and copy"
            )
            DSPrimaryButton(title: "Scan with Camera") { isCameraPresented = true }
                .padding(.horizontal, DSSpacing.md)
            moreSourcesMenu {
                HStack(spacing: 4) {
                    Text("Or choose from Photos / PDF")
                    Image(systemName: "chevron.right")
                }
                .font(DSFont.subheadline.weight(.medium))
                .foregroundStyle(Color.dsBrandPrimary)
            }
        }
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
        moreSourcesMenu {
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(Color.dsBorderDefault, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .frame(height: 120)
                .overlay {
                    Image(systemName: "plus").foregroundStyle(Color.dsBrandPrimary)
                }
        }
    }

    @ViewBuilder
    private func moreSourcesMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button {
                isCameraPresented = true
            } label: {
                Label("Scan with Camera", systemImage: "viewfinder")
            }
            PhotosPicker("Choose from Photos", selection: $photoItems, matching: .images)
            Button("Choose a PDF") { isPDFPickerPresented = true }
        } label: {
            label()
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

    // MARK: - Success

    private var successState: some View {
        VStack(spacing: DSSpacing.lg) {
            SuccessBadge(title: "Text recognized", subtitle: "Saved to your Documents — it'll show up in Library too")
            ForEach(savedURLs, id: \.self) { url in
                DSFileRow(ref: DocumentRef(
                    name: url.lastPathComponent,
                    url: url,
                    modifiedAt: .now,
                    kind: url.pathExtension.lowercased() == "docx" ? .docx : .pdf
                ))
                .padding(DSSpacing.sm)
                .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            }
            Spacer()
        }
        .padding(DSSpacing.md)
        .navigationBarBackButtonHidden()
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
            savedURLs = urls
            stage = .success
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
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let cgImage = uiImage.cgImage {
                newPages.append(ScannedPage(image: cgImage, source: .photo))
            }
        }
        pages.append(contentsOf: newPages)
        photoItems = []
    }

    /// Renders every page of an existing PDF picked as a Scan input — always runs
    /// OCR on these regardless of whether the PDF already has a text layer, unlike
    /// "PDF → Word" (which auto-detects and skips OCR when possible): choosing
    /// Scan & OCR here is a deliberate request for the review/confidence flow.
    nonisolated private static func renderPages(of url: URL) -> [CGImage] {
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
