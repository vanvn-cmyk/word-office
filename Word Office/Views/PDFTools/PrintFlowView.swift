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

    // UTTypes AirPrint / Quick Look can render on device — PDF natively,
    // Office formats through iOS's built-in Quick Look renderers.
    private static let printableTypes: [UTType] = [.pdf, .rtf, .plainText]
        + ["docx", "doc", "xlsx", "xls", "pptx", "ppt"]
            .compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Group {
            if isLibraryPickerPresented {
                InlineCabinetPicker(
                    entries: store.entries,
                    filter: nil,
                    allowsMultipleSelection: false
                ) { urls in
                    sourceURL = urls.first
                    isLibraryPickerPresented = false
                } onCancel: {
                    isLibraryPickerPresented = false
                    if sourceURL == nil { dismiss() }
                } onBrowse: {
                    isPickerPresented = true
                }
            } else if let sourceURL {
                configureState(sourceURL)
            } else {
                printEmptyState
            }
        }
        .prominentInlineTitle(isLibraryPickerPresented ? "Cabinet" : "Print")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: Self.printableTypes,
            onCompletion: handleFilePicked
        )
        .errorAlert($viewModel.errorMessage)
        .onAppear { viewModel.errorMessage = nil }
        .task {
            guard !didAutoPresent, let source = initialSource, sourceURL == nil else { return }
            didAutoPresent = true
            switch source {
            case .library: isLibraryPickerPresented = true
            case .browse:  isPickerPresented = true
            }
        }
        .fileSourcePicker(
            isPresented: $isSourcePickerPresented,
            title: "Choose a file to print",
            message: "Select where your file is stored",
            onLibrary: { isLibraryPickerPresented = true },
            onBrowse: { isPickerPresented = true }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
        Group {
            if url.pathExtension.lowercased() == "pdf" {
                ReadOnlyPDFPreviewPane(url: url)
            } else {
                PrintQLPreview(url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundSecondary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { isSourcePickerPresented = true } label: {
                Label("Select other file", systemImage: "folder")
                    .font(DSFont.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.md)
            .background(Color.dsBackgroundSecondary)
        }
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

// MARK: - QuickLook preview (non-PDF)

/// Embeds a `QLPreviewController` inline — handles Word, Excel, PowerPoint,
/// RTF, and any other Office format that AirPrint can also render.
private struct PrintQLPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
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

