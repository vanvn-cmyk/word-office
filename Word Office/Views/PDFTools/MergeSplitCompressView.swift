// Sprint 0.3 — Merge/Split (§7.1). Compress excluded, moved to Phase 1.

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Merge

struct MergeView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urls: [URL] = []
    @State private var isPickerPresented = false
    @State private var didFinish = false

    var body: some View {
        Group {
            if didFinish, let merged = viewModel.lastMergedURL {
                MergeSuccessView(url: merged, fileCount: urls.count, viewModel: viewModel, dismiss: dismiss)
            } else if urls.isEmpty {
                EmptyStateView(
                    icon: "doc.on.doc",
                    title: "Add PDF files",
                    message: "Pick 2 or more files to combine, in the order you want them merged",
                    action: ("Choose files", { isPickerPresented = true })
                )
            } else {
                fileList
            }
        }
        .navigationTitle("Merge PDFs")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !didFinish {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge") { Task { await performMerge() } }
                    .fontWeight(.semibold)
                    .disabled(urls.count < 2 || viewModel.isProcessing)
            }
        }
    }

    private func handleFilesPicked(_ result: Result<[URL], Error>) {
        if case .success(let picked) = result { urls.append(contentsOf: picked) }
    }

    private var fileList: some View {
        List {
            Section("\(urls.count) files · will merge in this order") {
                ForEach(urls, id: \.self) { url in
                    DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: .now, kind: .pdf))
                }
                .onDelete { urls.remove(atOffsets: $0) }
                .onMove { urls.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    isPickerPresented = true
                } label: {
                    Label("Add more files", systemImage: "plus")
                }
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }

    private func performMerge() async {
        await viewModel.merge(urls)
        if viewModel.lastMergedURL != nil { didFinish = true }
    }
}

private struct MergeSuccessView: View {
    let url: URL
    let fileCount: Int
    @Bindable var viewModel: PDFToolsViewModel
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            SuccessBadge(title: "Merged successfully", subtitle: "Saved to your Documents — it'll show up in Library too")
            DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: .now, kind: .pdf))
                .padding(DSSpacing.sm)
                .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))

            DSPrimaryButton(title: "Print") { Task { await viewModel.print(url, jobName: url.lastPathComponent) } }
            DSSecondaryButton(title: "Done") { dismiss() }
            Spacer()
        }
        .padding(DSSpacing.md)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Split

struct SplitView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Wraps a page range with a stable identity — `ClosedRange<Int>` alone
    /// isn't `Identifiable`, and using the array index/offset as `ForEach` id
    /// (the tempting shortcut) breaks on delete: SwiftUI would reuse the wrong
    /// row's identity/state for whatever shifted into that offset.
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
    @State private var didFinish = false

    var body: some View {
        Group {
            if didFinish {
                SplitSuccessView(urls: viewModel.lastSplitURLs, dismiss: dismiss)
            } else if let sourceURL {
                configureState(sourceURL)
            } else {
                EmptyStateView(
                    icon: "square.split.2x1",
                    title: "Choose a PDF",
                    message: "Pick one file, then define the page ranges you want split out",
                    action: ("Choose a file", { isPickerPresented = true })
                )
            }
        }
        .navigationTitle("Split PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.pdf], onCompletion: handleFilePicked)
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Splitting into \(ranges.count) files", subtitle: "Running in the background — won't block the app")
            }
        }
        .errorAlert($viewModel.errorMessage)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !didFinish {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if sourceURL != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { Task { await performSplit() } }
                        .fontWeight(.semibold)
                        .disabled(ranges.isEmpty || viewModel.isProcessing)
                }
            }
        }
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        sourceURL = url
        Task {
            // Off the main actor — opening/parsing a large PDF just to read its
            // page count can still be a noticeable synchronous stall otherwise.
            let count = await Task.detached(priority: .utility) {
                PDFPageCounter.pageCount(of: url)
            }.value
            pageCount = count
            rangeEnd = count
        }
    }

    private func configureState(_ url: URL) -> some View {
        Form {
            Section {
                DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: .now, kind: .pdf))
            }

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
                // `max(pageCount, 1)` — `sourceURL` renders this Form synchronously
                // (line ~188) before the async page-count fetch resolves, so
                // `pageCount` is briefly still its initial `0`; `1...0` is an
                // invalid `ClosedRange` and traps immediately on every file pick.
                Stepper("From page \(rangeStart)", value: $rangeStart, in: 1...max(pageCount, 1))
                Stepper("To page \(rangeEnd)", value: $rangeEnd, in: 1...max(pageCount, 1))
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

    private func performSplit() async {
        guard let sourceURL else { return }
        await viewModel.split(sourceURL, ranges: ranges.map(\.range))
        if !viewModel.lastSplitURLs.isEmpty { didFinish = true }
    }
}

private struct SplitSuccessView: View {
    let urls: [URL]
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            SuccessBadge(title: "Split into \(urls.count) files", subtitle: "Saved to your Documents")
            List {
                ForEach(urls, id: \.self) { url in
                    DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: .now, kind: .pdf))
                }
            }
            .listStyle(.plain)
        }
        .padding(.top, DSSpacing.md)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }
}

/// Reads a PDF's page count purely for stepper bounds — not routed through
/// `PDFToolsViewModel` since it's local UI state, not a tool operation.
enum PDFPageCounter {
    nonisolated static func pageCount(of url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 1
    }
}
