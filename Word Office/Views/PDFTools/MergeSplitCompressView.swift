// Sprint 0.3 — Merge/Split (§7.1). Compress excluded, moved to Phase 1.

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Merge

struct MergeView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil
    /// Parent pushes Sign on top of the nav stack with the merged PDF pre-selected.
    /// Dismiss from Sign pops back to this preview.
    var onSign: ((URL) -> Void)? = nil
    var onPrint: ((URL) -> Void)? = nil
    /// Written by ToolsTabView when Sign completes from the Merge success screen
    /// — non-nil means Show the signed preview instead of the original merge temp.
    /// Done button commits the signed URL via `commitToPDF` and clears this binding.
    @Binding var signedResult: URL?

    @State private var urls: [URL] = []
    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// Set to the exact `urls` snapshot that produced the staged result —
    /// prevents re-merging the same unchanged selection.
    @State private var lastMergedSnapshot: [URL]?
    /// Staged temp URL from `mergeToTemp` — non-nil = show preview screen.
    /// User taps Done to commit to Library, or back chevron to discard.
    @State private var mergeResultURL: URL?

    var body: some View {
        Group {
            if isLibraryPickerPresented || (initialSource == .library && !didAutoPresent) {
                InlineCabinetPicker(
                    entries: store.entries,
                    filter: { $0.document.kind == .pdf },
                    allowsMultipleSelection: true,
                    emptyTitle: "No PDFs in Cabinet",
                    emptyMessage: "Import PDF files first — they'll appear here."
                ) { picked in
                    urls.append(contentsOf: picked)
                    isLibraryPickerPresented = false
                } onCancel: {
                    isLibraryPickerPresented = false
                    if urls.isEmpty { dismiss() }
                } onBrowse: {
                    isPickerPresented = true
                }
            } else if let resultURL = mergeResultURL {
                mergeResultPreview(resultURL)
            } else if urls.isEmpty {
                EmptyStateView(
                    icon: "doc.on.doc",
                    title: "Add PDF files",
                    message: "Pick 2 or more files to combine, in the order you want them merged",
                    action: ("Add Files", { isSourcePickerPresented = true })
                )
            } else {
                fileList
            }
        }
        .prominentInlineTitle(isLibraryPickerPresented ? "Cabinet" : "Merge PDFs")
        .navigationBarBackButtonHidden(mergeResultURL != nil || isLibraryPickerPresented)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleFilesPicked
        )
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Merging \(urls.count) files", subtitle: "Running in the background — won't block the app")
            }
        }
        .errorAlert($viewModel.errorMessage)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          title: "Add PDF files",
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent, let source = initialSource else { return }
            didAutoPresent = true
            switch source {
            case .prePickedURLs(let picked):
                urls.append(contentsOf: picked)
            case .library:
                guard urls.isEmpty else { return }
                isLibraryPickerPresented = true
            case .browse:
                isPickerPresented = true
            }
        }
        .onAppear { viewModel.errorMessage = nil }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Back from result preview → file list (discards temp file).
        if mergeResultURL != nil {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if let signed = signedResult {
                        try? FileManager.default.removeItem(at: signed.deletingLastPathComponent())
                        signedResult = nil
                    }
                    if let url = mergeResultURL {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                        mergeResultURL = nil
                    }
                    lastMergedSnapshot = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        // Merge button — hidden on cabinet picker or result preview.
        if !isLibraryPickerPresented && mergeResultURL == nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge") { Task { await performMerge() } }
                    .fontWeight(.semibold)
                    .disabled(urls.count < 2 || viewModel.isProcessing || urls == lastMergedSnapshot)
            }
        }
    }

    // MARK: - Merge result preview

    @ViewBuilder
    private func mergeResultPreview(_ url: URL) -> some View {
        // Show signed version if user went Sign PDF → Done in the Sign flow.
        let displayURL = signedResult ?? url
        VStack(spacing: 0) {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.dsBrandPrimary)
                VStack(spacing: 2) {
                    Text("PDFs merged")
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("\(urls.count) files combined")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)

            MergePDFFirstPagePreview(url: displayURL)
                .id(displayURL)
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
                    Button { onSign(displayURL) } label: {
                        Label("Sign PDF", systemImage: "signature")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
                if let onPrint {
                    Button { onPrint(displayURL) } label: {
                        Label("Print", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                }
                Button {
                    Task { await commitMergeAction(displayURL: displayURL) }
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

    // MARK: - File list

    private var fileList: some View {
        List {
            Section {
                ForEach(urls, id: \.self) { url in
                    DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: url.contentModificationDateOrNow, kind: .pdf))
                }
                .onDelete { urls.remove(atOffsets: $0) }
                .onMove { urls.move(fromOffsets: $0, toOffset: $1) }

                Menu {
                    Button {
                        isLibraryPickerPresented = true
                    } label: {
                        Label("From Cabinet", systemImage: "cabinet.fill")
                    }
                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("From Device", systemImage: "iphone")
                    }
                } label: {
                    Label("Add more files", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("\(urls.count) files · will merge in this order")
                    Spacer()
                    EditButton()
                        .font(DSFont.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFilesPicked(_ result: Result<[URL], Error>) {
        if case .success(let picked) = result {
            urls.append(contentsOf: picked)
            isLibraryPickerPresented = false
        }
    }

    private func performMerge() async {
        if let tempURL = await viewModel.mergeToTemp(urls) {
            lastMergedSnapshot = urls
            mergeResultURL = tempURL
        }
    }

    private func commitMergeAction(displayURL: URL) async {
        guard let tempURL = mergeResultURL else { return }
        let finalURL: URL?
        if let signed = signedResult {
            // Signed version: commit via generic commitToPDF, then clean up the
            // unsigned merge temp so the staging directory doesn't accumulate.
            finalURL = await viewModel.commitToPDF(signed)
            try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
        } else {
            finalURL = await viewModel.commitMerge(tempURL)
        }
        if let finalURL {
            store.markAsNew(finalURL)
            signedResult = nil
            mergeResultURL = nil
            urls = []
            lastMergedSnapshot = nil
            toaster.show(.success, title: "Your document was saved to your Library", filename: finalURL.lastPathComponent)
            isSourcePickerPresented = true
        }
    }
}

/// Non-interactive single-page PDFView for the merge result preview screen.
private struct MergePDFFirstPagePreview: UIViewRepresentable {
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

// MARK: - Split

struct SplitView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil
    var onShowGallery: (([URL]) -> Void)? = nil
    var onSign: ((URL) -> Void)? = nil
    var onPrint: ((URL) -> Void)? = nil
    /// Written by ToolsTabView when Sign completes from the Split single-output
    /// success screen — updates the preview to show the signed version.
    @Binding var signedResult: URL?

    private struct PageRange: Identifiable {
        let id = UUID()
        let range: ClosedRange<Int>
    }

    @State private var sourceURL: URL?
    @State private var pageCount: Int = 0
    @State private var ranges: [PageRange] = []
    @State private var rangeStart = 1
    @State private var rangeEnd = 1
    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    @State private var lastSplitSnapshot: [ClosedRange<Int>]?
    /// Staged temp URLs from `splitToTemp` — non-empty = show result screen.
    /// User taps Done to commit to Library, or back chevron to discard.
    @State private var splitResultURLs: [URL] = []

    var body: some View {
        Group {
            if isLibraryPickerPresented {
                InlineCabinetPicker(
                    entries: store.entries,
                    filter: { $0.document.kind == .pdf },
                    allowsMultipleSelection: false,
                    emptyTitle: "No PDFs in Cabinet",
                    emptyMessage: "Import PDF files first — they'll appear here."
                ) { picked in
                    guard let url = picked.first else { return }
                    // Don't close the cabinet here — handleFilePicked's async
                    // page-count check controls isLibraryPickerPresented so a
                    // 1-page rejection keeps the cabinet visible (no flash).
                    handleFilePicked(.success(url))
                } onCancel: {
                    isLibraryPickerPresented = false
                    if sourceURL == nil { dismiss() }
                } onBrowse: {
                    isPickerPresented = true
                }
            } else if !splitResultURLs.isEmpty {
                splitResultPreview(splitResultURLs)
            } else if let sourceURL {
                configureState(sourceURL)
            } else {
                EmptyStateView(
                    icon: "square.split.2x1",
                    title: "Choose a PDF",
                    message: "Pick one file, then define the page ranges you want split out",
                    action: ("Choose a PDF", { isSourcePickerPresented = true })
                )
            }
        }
        .prominentInlineTitle(isLibraryPickerPresented ? "Cabinet" : "Split PDF")
        .navigationBarBackButtonHidden(!splitResultURLs.isEmpty || isLibraryPickerPresented)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.pdf], onCompletion: handleFilePicked)
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Splitting into \(ranges.count) files", subtitle: "Running in the background — won't block the app")
            }
        }
        .errorAlert($viewModel.errorMessage)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          title: "Choose a PDF to split",
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent, let source = initialSource else { return }
            didAutoPresent = true
            switch source {
            case .prePickedURLs(let urls):
                sourceURL = urls.first
            case .library:
                guard sourceURL == nil else { return }
                isLibraryPickerPresented = true
            case .browse:
                isPickerPresented = true
            }
        }
        .onAppear { viewModel.errorMessage = nil }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Back from result preview → configure screen (discards temp files).
        if !splitResultURLs.isEmpty {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if let signed = signedResult {
                        try? FileManager.default.removeItem(at: signed.deletingLastPathComponent())
                        signedResult = nil
                    }
                    if let firstTemp = splitResultURLs.first {
                        try? FileManager.default.removeItem(at: firstTemp.deletingLastPathComponent())
                    }
                    splitResultURLs = []
                    lastSplitSnapshot = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        if !isLibraryPickerPresented && splitResultURLs.isEmpty, sourceURL != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Split") { Task { await performSplit() } }
                    .fontWeight(.semibold)
                    .disabled(ranges.isEmpty || viewModel.isProcessing || ranges.map(\.range) == lastSplitSnapshot)
            }
        }
    }

    // MARK: - Result preview

    @ViewBuilder
    private func splitResultPreview(_ urls: [URL]) -> some View {
        if urls.count == 1, let only = urls.first {
            // Single output: PDF preview + Done/Sign/Print like merge result.
            // Show signed version if user went Sign PDF → Done in the Sign flow.
            let displayURL = signedResult ?? only
            VStack(spacing: 0) {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.dsBrandPrimary)
                    VStack(spacing: 2) {
                        Text("PDF split")
                            .font(DSFont.headline)
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("1 file ready")
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.md)

                MergePDFFirstPagePreview(url: displayURL)
                    .id(displayURL)
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
                        Button { onSign(displayURL) } label: {
                            Label("Sign PDF", systemImage: "signature")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.dsBrandPrimary)
                    }
                    if let onPrint {
                        Button { onPrint(displayURL) } label: {
                            Label("Print", systemImage: "printer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Color.dsBrandPrimary)
                    }
                    Button {
                        Task { await commitSplitAction(displayURL: displayURL, original: only) }
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
        } else {
            // Multiple outputs: list of filenames + Done
            VStack(spacing: 0) {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.dsBrandPrimary)
                    VStack(spacing: 2) {
                        Text("PDF split")
                            .font(DSFont.headline)
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("\(urls.count) files ready")
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.sm)

                List {
                    ForEach(urls, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "doc.fill")
                            .font(DSFont.body)
                            .foregroundStyle(Color.dsTextPrimary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    Task { await commitSplitAction() }
                } label: {
                    Text("Done")
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
    }

    // MARK: - Configure state

    private func handleFilePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        // Page-count check runs BEFORE we close the cabinet or set sourceURL —
        // so a 1-page rejection stays on the cabinet (or empty state for browse)
        // and only shows the toast, without flashing the split form or landing
        // on "Choose a PDF" instead of the picker.
        Task {
            let count = await Task.detached(priority: .utility) {
                PDFPageCounter.pageCount(of: url)
            }.value
            if count < 2 {
                toaster.show(.error, title: "Can't split — this file has only 1 page", filename: url.lastPathComponent)
                return
            }
            isLibraryPickerPresented = false
            sourceURL = url
            pageCount = count
            rangeEnd = count
        }
    }

    @ViewBuilder
    private func configureState(_ url: URL) -> some View {
        splitForm(url)
    }

    private func splitForm(_ url: URL) -> some View {
        Form {
            Section {
                DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: url.contentModificationDateOrNow, kind: .pdf))
            }

            if pageCount > 1 {
                if !ranges.isEmpty {
                    Section("Page ranges") {
                        ForEach(ranges) { entry in
                            HStack {
                                Text("\(entry.range.lowerBound + 1)–\(entry.range.upperBound + 1)")
                                Spacer()
                                Button {
                                    ranges.removeAll { $0.id == entry.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dsTextTertiary)
                                }
                                .accessibilityLabel("Remove page range \(entry.range.lowerBound + 1) to \(entry.range.upperBound + 1)")
                            }
                        }
                    }
                }

                Section {
                    Stepper("From page \(rangeStart)", value: $rangeStart, in: 1...pageCount)
                    Stepper("To page \(rangeEnd)", value: $rangeEnd, in: 1...pageCount)
                    Button {
                        let lower = min(rangeStart, rangeEnd) - 1
                        let upper = max(rangeStart, rangeEnd) - 1
                        ranges.append(PageRange(range: lower...upper))
                    } label: {
                        Label("Add this range", systemImage: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func performSplit() async {
        guard let sourceURL else { return }
        let requestedRanges = ranges.map(\.range)
        let temps = await viewModel.splitToTemp(sourceURL, ranges: requestedRanges)
        guard !temps.isEmpty else { return }
        lastSplitSnapshot = requestedRanges
        splitResultURLs = temps
    }

    /// Commits the split result to Library. When invoked from the single-output
    /// success screen, `displayURL` may be the signed staged temp and `original`
    /// the unsigned split temp — in that case commits the signed version via
    /// `commitToPDF` and cleans up the unsigned temp.
    private func commitSplitAction(displayURL: URL? = nil, original: URL? = nil) async {
        guard !splitResultURLs.isEmpty else { return }
        // Single-output signed case: commit signed, skip the bulk commit.
        if let signed = signedResult, let displayURL, let original, displayURL == signed {
            if let finalURL = await viewModel.commitToPDF(signed) {
                store.markAsNew(finalURL)
                try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
                signedResult = nil
                splitResultURLs = []
                sourceURL = nil
                lastSplitSnapshot = nil
                toaster.show(.success, title: "Your document was saved to your Library", filename: finalURL.lastPathComponent)
                isSourcePickerPresented = true
            }
            return
        }
        let finals = await viewModel.commitSplit(splitResultURLs)
        guard !finals.isEmpty else { return }
        finals.forEach { store.markAsNew($0) }
        signedResult = nil
        splitResultURLs = []
        sourceURL = nil
        lastSplitSnapshot = nil
        let count = finals.count
        toaster.show(.success, title: "\(count) file\(count == 1 ? "" : "s") saved to your Library")
        isSourcePickerPresented = true
    }
}

/// Reads a PDF's page count purely for stepper bounds — not routed through
/// `PDFToolsViewModel` since it's local UI state, not a tool operation.
enum PDFPageCounter {
    nonisolated static func pageCount(of url: URL) -> Int {
        // Session 19 — security-scope claim required. `handleFilePicked`
        // dispatches this call into `Task.detached`, which drops the
        // `.fileImporter` transient grant on the picker URL. Without
        // the claim, `PDFDocument(url:)` returns nil for iCloud /
        // Files-provider PDFs → we fall back to `1`, the Split
        // stepper bounds `1...1` freeze both `-` and `+`, and the
        // user can't pick any range but page 1. Same class of bug as
        // the SignatureViewModel / FillFormViewModel / ScanFlowView
        // security-scope misses caught in the S19 code-review #4 pass.
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
        return PDFDocument(url: url)?.pageCount ?? 1
    }
}
