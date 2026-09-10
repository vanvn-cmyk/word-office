import SwiftUI
import UniformTypeIdentifiers

struct PrintFlowView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(LibraryStore.self) private var store

    @State private var sourceURL: URL?
    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false

    // UTTypes AirPrint / Quick Look can render on device — PDF natively,
    // Office formats through iOS's built-in Quick Look renderers.
    private static let printableTypes: [UTType] = [.pdf, .rtf, .plainText]
        + ["docx", "doc", "xlsx", "xls", "pptx", "ppt"]
            .compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Group {
            if let sourceURL {
                configureState(sourceURL)
            } else {
                printEmptyState
            }
        }
        .prominentInlineTitle("Print")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: Self.printableTypes,
            onCompletion: handleFilePicked
        )
        .sheet(isPresented: $isLibraryPickerPresented) {
            LibraryPrintPicker(entries: store.entries) { entry in
                sourceURL = entry.document.url
                isLibraryPickerPresented = false
            }
        }
        .errorAlert($viewModel.errorMessage)
        .onAppear { viewModel.errorMessage = nil }
        .task { isSourcePickerPresented = true }
        .fileSourcePicker(
            isPresented: $isSourcePickerPresented,
            message: "Select where your file is stored",
            onLibrary: { isLibraryPickerPresented = true },
            onBrowse: { isPickerPresented = true }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Print") { Task { await performPrint() } }
                .fontWeight(.semibold)
                .disabled(sourceURL == nil || viewModel.isProcessing)
        }
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        if case .success(let url) = result { sourceURL = url }
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
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            DSFileRow(ref: DocumentRef(
                name: url.lastPathComponent,
                url: url,
                modifiedAt: url.contentModificationDateOrNow,
                kind: DocumentKind.fromUTI(url: url) ?? .pdf
            ))
            .padding(.horizontal, DSSpacing.md)
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .padding(.horizontal, DSSpacing.md)

            Text("Tap Print above to open the AirPrint sheet — pick a printer, page range, copies, and other options.")
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextSecondary)
                .padding(.horizontal, DSSpacing.lg)

            Spacer(minLength: 0)
        }
        .padding(.top, DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundSecondary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                Button {
                    isLibraryPickerPresented = true
                } label: {
                    Label("Library", systemImage: "tray.fill")
                        .font(DSFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.dsBrandPrimary)

                Button {
                    isPickerPresented = true
                } label: {
                    Label("Browse", systemImage: "folder")
                        .font(DSFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.dsBrandPrimary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.sm)
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

// MARK: - Library picker sheet

/// Simple list of all library entries — user taps one to choose it for
/// printing. No type filter: AirPrint / Quick Look handles any format the
/// library accepts (PDF, Word, Excel, PowerPoint).
private struct LibraryPrintPicker: View {
    let entries: [LibraryEntry]
    let onPick: (LibraryEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No documents in Library",
                        systemImage: "tray",
                        description: Text("Import files first, then come back to print.")
                    )
                } else {
                    List(entries) { entry in
                        Button {
                            onPick(entry)
                        } label: {
                            DSFileRow(ref: entry.document)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pick from Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
