import PDFKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct PrintFlowView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var initialSource: FilePickerSource? = nil

    @State private var sourceURL: URL?
    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// True while auto-printing from a pre-picked URL (officeToPDF flow).
    /// Suppresses the configureState view so only the system print sheet
    /// is visible — no intermediate Print preview screen.
    @State private var isAutoPrinting = false
    /// PDF page navigation state — reset whenever a new file is loaded.
    @State private var pdfPageCurrent: Int = 1
    @State private var pdfPageTotal: Int = 1

    // UTTypes AirPrint / Quick Look can render on device — PDF natively,
    // Office formats through iOS's built-in Quick Look renderers.
    private static let printableTypes: [UTType] = [.pdf, .rtf, .plainText]
        + ["docx", "doc", "xlsx", "xls", "pptx", "ppt"]
            .compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Group {
            if isLibraryPickerPresented || (initialSource == .library && !didAutoPresent) {
                InlineCabinetPicker(
                    entries: store.entries,
                    filter: nil,
                    allowsMultipleSelection: false
                ) { urls in
                    sourceURL = urls.first
                    isLibraryPickerPresented = false
                } onCancel: {
                    if sourceURL == nil {
                        dismiss()   // no flash: keep isLibraryPickerPresented true while popping
                    } else {
                        isLibraryPickerPresented = false
                    }
                } onBrowse: {
                    isPickerPresented = true
                }
            } else if isAutoPrinting {
                // Blank backing view while the system print sheet is on screen.
                // The sheet is triggered immediately from .task for prePickedURLs
                // (officeToPDF → Print flow) — no preview screen needed.
                Color.dsBackgroundSecondary.ignoresSafeArea()
            } else if let sourceURL {
                configureState(sourceURL)
            } else {
                printEmptyState
            }
        }
        .prominentInlineTitle(isLibraryPickerPresented ? "Cabinet" : "Print")
        .navigationBarBackButtonHidden(isLibraryPickerPresented || sourceURL != nil || isAutoPrinting)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: Self.printableTypes,
            onCompletion: handleFilePicked
        )
        .errorAlert($viewModel.errorMessage)
        .onAppear { viewModel.errorMessage = nil }
        .task {
            guard !didAutoPresent, let source = initialSource else { return }
            didAutoPresent = true
            switch source {
            case .prePickedURLs(let urls):
                guard let url = urls.first else { return }
                sourceURL = url
                // Auto-trigger print immediately (no preview interaction needed).
                // Dismiss after so the user returns to the caller (e.g. officeToPDF
                // success screen) rather than landing here with a back button.
                isAutoPrinting = true
                await performPrint()
                isAutoPrinting = false
                dismiss()
            case .library:
                guard sourceURL == nil else { return }
                isLibraryPickerPresented = true
            case .browse:
                isPickerPresented = true
            }
        }
        .fileSourcePicker(
            isPresented: $isSourcePickerPresented,
            title: "Choose a file to print",
            message: "Select where your file is stored",
            onLibrary: { isLibraryPickerPresented = true },
            onBrowse: { isPickerPresented = true }
        )
        .onChange(of: sourceURL) {
            pdfPageCurrent = 1
            pdfPageTotal  = 1
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Custom back from preview → Cabinet picker (or empty state for browse).
        // Only shown when preview is visible — Cabinet picker owns its own Cancel.
        if sourceURL != nil && !isLibraryPickerPresented {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    sourceURL = nil
                    if initialSource == .library { isLibraryPickerPresented = true }
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        if !isLibraryPickerPresented {
            ToolbarItem(placement: .confirmationAction) {
                Button("Print") { Task { await performPrint() } }
                    .fontWeight(.semibold)
                    .disabled(sourceURL == nil || viewModel.isProcessing)
            }
        }
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            sourceURL = url
            isLibraryPickerPresented = false
        }
    }

    // MARK: - Empty state

    private var printEmptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DSSpacing.lg).frame(maxHeight: 160)

            VStack(spacing: DSSpacing.xxl) {
                VStack(spacing: DSSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.dsBrandPrimary.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: "printer.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color.dsBrandPrimary)
                    }
                    Text("Choose a file to print")
                        .font(DSFont.title3.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                        .padding(.top, DSSpacing.xs)
                    Text("PDF, Word, Excel, and PowerPoint supported.\nAirPrint handles printer selection.")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, DSSpacing.xl)

                Button("Choose a file") { isSourcePickerPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
            }

            Spacer(minLength: DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundSecondary)
    }

    // MARK: - Configured state (file selected)

    private func configureState(_ url: URL) -> some View {
        let ext  = url.pathExtension.lowercased()
        let kind = DocumentKind(rawValue: ext) ?? .pdf
        let isPDF = ext == "pdf"
        return VStack(spacing: 0) {
            // File info header
            HStack(spacing: DSSpacing.sm) {
                DocumentKindIcon(kind: kind)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(DSFont.headline)
                        .lineLimit(1)
                    Text(ext.uppercased() + " · Ready to print")
                        .font(DSFont.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(Color.dsBackgroundPrimary)

            Divider()

            // Preview + page navigator overlay
            ZStack(alignment: .bottom) {
                if isPDF {
                    PrintPDFPageView(
                        url: url,
                        currentPage: $pdfPageCurrent,
                        totalPages: $pdfPageTotal
                    )
                } else {
                    PrintQLPreview(url: url)
                }

                if isPDF && pdfPageTotal > 0 {
                    pageNavigator
                        .padding(.bottom, DSSpacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.dsBackgroundSecondary)
    }

    /// Capsule pill with ‹ · "page / total" · › — overlaid at the
    /// bottom-centre of the PDF preview.
    private var pageNavigator: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                pdfPageCurrent = max(1, pdfPageCurrent - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(pdfPageCurrent <= 1)

            Text("\(pdfPageCurrent) / \(pdfPageTotal)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.primary)
                .frame(minWidth: 52)

            Button {
                pdfPageCurrent = min(pdfPageTotal, pdfPageCurrent + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(pdfPageCurrent >= pdfPageTotal)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Action

    private func performPrint() async {
        guard let sourceURL else { return }
        // Security-scope claim for files outside the app sandbox (e.g.
        // picked via fileImporter from Files.app / iCloud). Library files
        // in the app's own sandbox don't need this but the call is a no-op
        // for those — safe to call unconditionally.
        let didStartScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { sourceURL.stopAccessingSecurityScopedResource() } }
        await viewModel.print(sourceURL, jobName: sourceURL.deletingPathExtension().lastPathComponent)
    }
}

// MARK: - PDF preview with single-page mode (Print)

/// PDFView subclass that sets a fill-width scale every layout pass.
/// `autoScales = true` fits the full page vertically, which produces
/// small text on portrait documents. Fill-width keeps the page the
/// same width as the view so text reads at a comfortable size; the
/// user can scroll vertically to see the rest of the page.
private final class PrintPDFView: PDFView {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !autoScales,
              let page = currentPage ?? document?.page(at: 0) else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, bounds.width > 0 else { return }
        let target = bounds.width / pageBounds.width
        if abs(scaleFactor - target) > 0.005 { scaleFactor = target }
    }
}

/// `PrintPDFView` in single-page display mode wired to parent bindings
/// so the page-navigator pill in `PrintFlowView` can read and drive
/// page changes.
private struct PrintPDFPageView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int

    func makeUIView(context: Context) -> PrintPDFView {
        let view = PrintPDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.autoScales = false  // PrintPDFView.layoutSubviews sets fill-width scale
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        // Initialise totals on the next tick so SwiftUI binding writes land safely.
        let count = view.document?.pageCount ?? 1
        DispatchQueue.main.async {
            self.totalPages  = count
            self.currentPage = 1
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ uiView: PrintPDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
            let count = uiView.document?.pageCount ?? 1
            DispatchQueue.main.async {
                self.totalPages  = count
                self.currentPage = 1
            }
            return
        }
        guard let doc = uiView.document,
              let target = doc.page(at: currentPage - 1),
              uiView.currentPage !== target else { return }
        uiView.go(to: target)
    }

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        init(currentPage: Binding<Int>) { _currentPage = currentPage }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let doc  = pdfView.document else { return }
            let idx = doc.index(for: page) + 1
            Task { @MainActor [weak self] in self?.currentPage = idx }
        }
    }
}

// MARK: - QuickLook preview (non-PDF)

/// Embeds a `QLPreviewController` inline — handles Word, Excel, PowerPoint,
/// RTF, and any other Office format that AirPrint can also render.
///
/// Wrapped in a plain `UIViewController` container so that QLPreviewController
/// does not try to show its own navigation bar (which appeared as blank
/// whitespace at the top when embedded directly via UIViewControllerRepresentable).
private struct PrintQLPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .systemBackground
        let qlVC = QLPreviewController()
        qlVC.dataSource = context.coordinator
        container.addChild(qlVC)
        qlVC.view.frame = container.view.bounds
        qlVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.view.addSubview(qlVC.view)
        qlVC.didMove(toParent: container)
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.url = url
        (uiViewController.children.first as? QLPreviewController)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

