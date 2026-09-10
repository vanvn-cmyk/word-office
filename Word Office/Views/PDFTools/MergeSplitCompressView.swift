// Sprint 0.3 — Merge/Split (§7.1). Compress excluded, moved to Phase 1.

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Merge

struct MergeView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    /// Callback fired after a successful merge — parent (`ToolsTabView`)
    /// uses it to open the merged file in the editor. Optional so this view
    /// can be used stand-alone (e.g. previews) without navigation wiring.
    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil

    @State private var urls: [URL] = []
    @State private var isPickerPresented = false
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// Set to the exact `urls` that produced the last successful merge —
    /// the file list deliberately stays populated after success so the
    /// user can add more files and merge again, but re-tapping "Merge" on
    /// that SAME unchanged selection used to silently write a second,
    /// distinctly-named output. Disabled only while `urls` matches this;
    /// any add/remove/reorder changes `urls` and re-enables it.
    @State private var lastMergedSnapshot: [URL]?

    var body: some View {
        // No didFinish branch: success shows a toast (see `performMerge`) and
        // the file list stays visible so the user can add more files and
        // merge again without navigating back and re-tapping the tool card.
        Group {
            if urls.isEmpty {
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
        .prominentInlineTitle("Merge PDFs")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleFilesPicked
        )
        .sheet(isPresented: $isLibraryPickerPresented) {
            LibraryFilePicker(
                entries: store.entries,
                filter: { $0.document.kind == .pdf },
                allowsMultipleSelection: true,
                emptyTitle: "No PDFs in Library",
                emptyMessage: "Import PDF files first, then come back."
            ) { picked in
                urls.append(contentsOf: picked)
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Merging \(urls.count) files", subtitle: "Running in the background — won't block the app")
            }
        }
        .errorAlert($viewModel.errorMessage)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent, let source = initialSource, urls.isEmpty else { return }
            didAutoPresent = true
            switch source {
            case .library: isLibraryPickerPresented = true
            case .browse:  isPickerPresented = true
            }
        }
        // `viewModel` (`pdfToolsVM`) is shared across Merge/Split/Convert/
        // Print — a failure left over from whichever of those the user
        // visited last otherwise pops up here as if it were a Merge error.
        .onAppear { viewModel.errorMessage = nil }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // No explicit Cancel — this view is only reached via `NavigationLink`
        // push from `ToolsTabView`, so the system back chevron already covers
        // dismissal. Adding a leading Cancel next to it reads as a duplicate.
        ToolbarItem(placement: .confirmationAction) {
            Button("Merge") { Task { await performMerge() } }
                .fontWeight(.semibold)
                .disabled(urls.count < 2 || viewModel.isProcessing || urls == lastMergedSnapshot)
        }
    }

    private func handleFilesPicked(_ result: Result<[URL], Error>) {
        if case .success(let picked) = result { urls.append(contentsOf: picked) }
    }

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
                        Label("From Library", systemImage: "tray.fill")
                    }
                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("Browse Files", systemImage: "folder")
                    }
                } label: {
                    Label("Add more files", systemImage: "plus")
                }
            } header: {
                // EditButton inline with the section title — keeps the
                // toolbar unambiguous ("Merge" = sole primary CTA) while
                // the Edit/Done toggle lives near the list it controls.
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

    private func performMerge() async {
        await viewModel.merge(urls)
        if let url = viewModel.lastMergedURL {
            lastMergedSnapshot = urls
            toaster.show(.success, title: "Your document was saved to your Library", filename: url.lastPathComponent)
            // Navigate straight to the merged file so the user lands on the
            // result instead of the picker they just used — matches the
            // "toast then jump to the new file's screen" flow.
            onOpenFile?(url)
        }
    }
}

// MARK: - Split

struct SplitView: View {
    @Bindable var viewModel: PDFToolsViewModel
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(LibraryStore.self) private var store
    /// Fires when the split produces exactly one file (single range) — the
    /// user lands directly in the editor for that file, matching Merge and
    /// the single-output Convert flows.
    var initialSource: FilePickerSource? = nil
    var onOpenFile: ((URL) -> Void)? = nil
    /// Fires when the split produces two or more files — parent presents
    /// `ToolResultGalleryView` so the user can review, save-all, share-all,
    /// or open any individual output. Session 10 gap fix (2026-09-04) —
    /// the old "navigate to first, hide the rest" default lost visibility
    /// of the other N-1 outputs behind the tab-back button.
    var onShowGallery: (([URL]) -> Void)? = nil

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
    @State private var isLibraryPickerPresented = false
    @State private var isSourcePickerPresented = false
    @State private var didAutoPresent = false
    /// Same guard as `MergeView.lastMergedSnapshot` — `ranges` stays
    /// populated after a successful split so the user can add more ranges
    /// and split again, but re-tapping "Split" on the SAME unchanged
    /// ranges used to silently write a second set of output files.
    @State private var lastSplitSnapshot: [ClosedRange<Int>]?

    var body: some View {
        // No didFinish branch: success shows a toast (see `performSplit`) and
        // the configure view stays visible so the user can add more ranges
        // and split again without navigating back and re-tapping the tool.
        Group {
            if let sourceURL {
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
        .prominentInlineTitle("Split PDF")
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.pdf], onCompletion: handleFilePicked)
        .sheet(isPresented: $isLibraryPickerPresented) {
            LibraryFilePicker(
                entries: store.entries,
                filter: { $0.document.kind == .pdf },
                allowsMultipleSelection: false,
                emptyTitle: "No PDFs in Library",
                emptyMessage: "Import PDF files first, then come back."
            ) { picked in
                guard let url = picked.first else { return }
                handleFilePicked(.success(url))
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay(title: "Splitting into \(ranges.count) files", subtitle: "Running in the background — won't block the app")
            }
        }
        .errorAlert($viewModel.errorMessage)
        .fileSourcePicker(isPresented: $isSourcePickerPresented,
                          onLibrary: { isLibraryPickerPresented = true },
                          onBrowse: { isPickerPresented = true })
        .task {
            guard !didAutoPresent, let source = initialSource, sourceURL == nil else { return }
            didAutoPresent = true
            switch source {
            case .library: isLibraryPickerPresented = true
            case .browse:  isPickerPresented = true
            }
        }
        // `viewModel` (`pdfToolsVM`) is shared across Merge/Split/Convert/
        // Print — a failure left over from whichever of those the user
        // visited last otherwise pops up here as if it were a Split error.
        .onAppear { viewModel.errorMessage = nil }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // No explicit Cancel — same rationale as `MergeView.toolbarContent`:
        // push-only, system back chevron handles dismissal.
        if sourceURL != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Split") { Task { await performSplit() } }
                    .fontWeight(.semibold)
                    .disabled(ranges.isEmpty || viewModel.isProcessing || ranges.map(\.range) == lastSplitSnapshot)
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

    @ViewBuilder
    private func configureState(_ url: URL) -> some View {
        if pageCount == 1 {
            singlePageWarning(url)
        } else {
            splitForm(url)
        }
    }

    // A single-page PDF has nothing to split. Instead of a second disconnected
    // card section, use ContentUnavailableView to fill the screen meaningfully
    // and give the user a direct action to recover.
    private func singlePageWarning(_ url: URL) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    DSFileRow(ref: DocumentRef(name: url.lastPathComponent, url: url, modifiedAt: url.contentModificationDateOrNow, kind: .pdf))
                }
            }
            .listStyle(.insetGrouped)
            .frame(height: 90)
            .disabled(true)

            ContentUnavailableView {
                Label("Can't Split This PDF", systemImage: "exclamationmark.triangle")
            } description: {
                Text("This file has only 1 page. Choose a PDF with at least 2 pages.")
            } actions: {
                Button("Choose a PDF") { isSourcePickerPresented = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.dsBrandPrimary)
            }
        }
        .background(Color.dsBackgroundSecondary)
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
            // pageCount == 0: async fetch still in flight — show nothing
            // until the real count lands (avoids a flash of wrong UI).
        }
    }

    private func performSplit() async {
        guard let sourceURL else { return }
        let requestedRanges = ranges.map(\.range)
        await viewModel.split(sourceURL, ranges: requestedRanges)
        let outputs = viewModel.lastSplitURLs
        guard !outputs.isEmpty else { return }
        lastSplitSnapshot = requestedRanges
        let count = outputs.count
        toaster.show(.success, title: "\(count) file\(count == 1 ? "" : "s") saved to your Library")
        // Single output → straight to editor, matching Merge and single-
        // range Convert flows. Multi-output → gallery so the user can
        // review, save-all, share-all, or pick any file to open.
        if count == 1, let only = outputs.first {
            onOpenFile?(only)
        } else {
            onShowGallery?(outputs)
        }
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
