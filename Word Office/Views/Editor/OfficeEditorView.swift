import SwiftUI
import UIKit
import Network
import PhotosUI

// UserDefaults key — set true the first time the editor fully loads (sdkjs cached).
private let kCacheReadyKey = "officeEditorCacheReady"

/// Bubbles the editor's unsaved-changes state up through the SwiftUI hierarchy
/// so EditorSheet can intercept the Done button without needing a direct binding.
struct EditorDirtyPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct OfficeEditorView: View {
    let ref: DocumentRef

    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String? = nil
    @State private var saveCount = 0
    @State private var isDirty = false
    @State private var editorVC: OfficeEditorViewController?
    @State private var lastSaveTime: Date? = nil
    @State private var wordCount: Int = 0
    @State private var slideProgress: (current: Int, total: Int) = (1, 1)

    // Native photo insertion
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem? = nil

    // Native filter sheet (replaces ONLYOFFICE's web filter panel)
    @State private var filterItems: [NativeFilterItem] = []
    @State private var showFilterSheet = false

    // Native insert sheets
    @State private var showLinkSheet    = false
    @State private var showCommentSheet = false
    @State private var showChartSheet   = false
    @State private var showShapeSheet   = false
    @State private var pendingLink: (url: String, text: String)? = nil
    @State private var pendingComment: String? = nil
    @State private var pendingChart: String? = nil
    @State private var pendingShape: String? = nil

    private var fileKind: EditorTopToolbar.FileKind {
        EditorTopToolbar.FileKind(ext: ref.url.pathExtension)
    }

    var body: some View {
        Group {
            if let msg = errorMessage {
                ContentUnavailableView(
                    "Could Not Open Document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            } else {
                VStack(spacing: 0) {
                    EditorTopToolbar(
                        kind: fileKind,
                        slideInfo: fileKind == .ppt ? slideProgress : nil,
                        onCommand: handleCommand
                    )

                    _OfficeWebView(
                        ref: ref,
                        onFileSaved: handleSave,
                        onError: handleError,
                        onReady: handleReady,
                        onDirtyChange: { isDirty = $0 },
                        onVCReady: { editorVC = $0 },
                        onFilterRequest: { items in
                            filterItems = items
                            showFilterSheet = true
                        },
                        onSlideChange: { c, t in slideProgress = (c, t) }
                    )

                    if fileKind == .word {
                        wordStatusBar
                    }
                }
                // Native photo picker — triggered by "insert-image" command
                .photosPicker(
                    isPresented: $showImagePicker,
                    selection: $imagePickerItem,
                    matching: .images
                )
                .onChange(of: imagePickerItem) { _, item in
                    guard let item else { return }
                    Task { await sendPickedImage(item) }
                }
                // Native filter + sort sheet
                .sheet(isPresented: $showFilterSheet) {
                    NativeFilterView(
                        items: filterItems,
                        onSort: { ascending in
                            showFilterSheet = false
                            editorVC?.execEditorCommand(ascending ? "sort-asc" : "sort-desc")
                            // Cancel the hidden OO filter panel (no changes to values)
                            editorVC?.applyNativeFilter(selectedIds: [], cancel: true)
                        },
                        onCommit: { selectedIds, cancelled in
                            showFilterSheet = false
                            editorVC?.applyNativeFilter(selectedIds: selectedIds, cancel: cancelled)
                        }
                    )
                }
                // Native hyperlink insert sheet — insertHyperlink fires in onDismiss so the
                // WKWebView has fully regained focus before JS is evaluated.
                .sheet(isPresented: $showLinkSheet, onDismiss: {
                    if let link = pendingLink {
                        editorVC?.insertHyperlink(url: link.url, displayText: link.text)
                        pendingLink = nil
                    }
                }) {
                    NativeLinkView(
                        onCommit: { url, text in
                            pendingLink = (url, text)
                            showLinkSheet = false
                        },
                        onCancel: { showLinkSheet = false }
                    )
                }
                // Native comment insert sheet — addComment fires in onDismiss for the
                // same reason as link: WKWebView must fully regain focus first.
                .sheet(isPresented: $showCommentSheet, onDismiss: {
                    if let text = pendingComment {
                        editorVC?.addComment(text: text)
                        pendingComment = nil
                    }
                }) {
                    NativeCommentView(
                        onCommit: { text in
                            pendingComment = text
                            showCommentSheet = false
                        },
                        onCancel: { showCommentSheet = false }
                    )
                }
                // Native chart insert sheet — insertChart fires in onDismiss after WKWebView regains focus.
                .sheet(isPresented: $showChartSheet, onDismiss: {
                    if let chartType = pendingChart {
                        editorVC?.insertChart(type: chartType)
                        pendingChart = nil
                    }
                }) {
                    NativeChartView(
                        onCommit: { type in
                            pendingChart = type
                            showChartSheet = false
                        },
                        onCancel: { showChartSheet = false }
                    )
                }
                // Native shape insert sheet — insertShape fires in onDismiss after WKWebView regains focus.
                .sheet(isPresented: $showShapeSheet, onDismiss: {
                    if let shapeType = pendingShape {
                        editorVC?.insertShape(type: shapeType)
                        pendingShape = nil
                    }
                }) {
                    NativeShapeView(
                        onCommit: { type in
                            pendingShape = type
                            showShapeSheet = false
                        },
                        onCancel: { showShapeSheet = false }
                    )
                }
            }
        }
        .preference(key: EditorDirtyPreferenceKey.self, value: isDirty)
        .navigationTitle(fileKind == .word ? "" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorNavPill }
        .task { await checkNetworkOnFirstLaunch() }
        .onReceive(NotificationCenter.default.publisher(for: .editorSaveRequested)) { _ in
            editorVC?.execEditorCommand("save")
        }
    }

    // MARK: - Command routing

    private func handleCommand(_ cmd: String) {
        switch cmd {
        case "insert-image":   showImagePicker  = true
        case "insert-link":    showLinkSheet     = true
        case "insert-comment": showCommentSheet  = true
        case "insert-chart":   showChartSheet    = true
        case "insert-shape":   showShapeSheet    = true
        case "print":          editorVC?.printDocument()
        default:               editorVC?.execEditorCommand(cmd)
        }
    }

    // MARK: - Image insertion

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        defer { imagePickerItem = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }

        // Resize to max 1600px and target ≤ 600 KB before handing off to OO.
        // Images are now served via office:// scheme (no base64 bridge), but smaller
        // images still reduce OO's rendering memory footprint inside WKWebView.
        let imageData: Data
        if let src = UIImage(data: raw) {
            let maxPx: CGFloat = 1600
            let scale = min(maxPx / src.size.width, maxPx / src.size.height, 1.0)
            let size  = CGSize(width: (src.size.width * scale).rounded(),
                               height: (src.size.height * scale).rounded())
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: fmt)
                .image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
            // Iterate quality down until under 600 KB
            var q: CGFloat = 0.75
            var out = resized.jpegData(compressionQuality: q) ?? raw
            while out.count > 600_000 && q > 0.35 {
                q -= 0.1
                out = resized.jpegData(compressionQuality: q) ?? out
            }
            imageData = out
        } else {
            imageData = raw
        }

        editorVC?.insertImage(data: imageData, mimeType: "image/jpeg")
    }

    // MARK: - Ready / network

    private func handleReady() {
        UserDefaults.standard.set(true, forKey: kCacheReadyKey)
    }

    @MainActor
    private func checkNetworkOnFirstLaunch() async {
        guard !UserDefaults.standard.bool(forKey: kCacheReadyKey) else { return }
        let isOnline = await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
        if !isOnline {
            errorMessage = "An internet connection is required to download the editor engine (~86 MB). After downloading once, editing works fully offline."
        }
    }

    // MARK: - Nav pill (Word + Excel)

    @ToolbarContentBuilder
    private var editorNavPill: some ToolbarContent {
        if fileKind == .word || fileKind == .excel || fileKind == .ppt {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    pillIconBtn("arrow.uturn.backward", cmd: "undo",           label: "Undo")
                    pillIconBtn("arrow.uturn.forward",  cmd: "redo",           label: "Redo")
                    pillIconBtn("printer",              cmd: "print",          label: "Print")
                    pillIconBtn("text.bubble",          cmd: "insert-comment", label: "Comment")
                    Button {
                        NotificationCenter.default.post(name: .editorSaveRequested, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
                    } label: {
                        Text("Done").fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func pillIconBtn(_ icon: String, cmd: String, label: String) -> some View {
        Button { handleCommand(cmd) } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(label)
    }

    private var wordStatusBar: some View {
        HStack {
            if let t = lastSaveTime {
                Text("Saved at \(t, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(isDirty ? "Unsaved changes" : "No changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if wordCount > 0 {
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Save / error

    private var saveBadge: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding([.top, .trailing], 12)
    }

    private func handleSave(data: Data, fileName: String) {
        Task {
            let dest = ref.url
            let accessing = dest.startAccessingSecurityScopedResource()
            defer { if accessing { dest.stopAccessingSecurityScopedResource() } }

            var writeError: Error?
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            coordinator.coordinate(
                writingItemAt: dest, options: .forReplacing,
                error: &coordError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }

            let finalError = writeError ?? coordError
            if let err = finalError {
                await MainActor.run {
                    errorMessage = "Could not save \"\(fileName)\": \(err.localizedDescription)"
                }
            } else {
                await MainActor.run {
                    saveCount += 1
                    lastSaveTime = Date()
                }
            }
        }
    }

    private func handleError(_ message: String) {
        if message.contains("editor engine could not load") {
            UserDefaults.standard.set(false, forKey: kCacheReadyKey)
        }
        Task { @MainActor in errorMessage = message }
    }
}

// MARK: - UIViewControllerRepresentable

private struct _OfficeWebView: UIViewControllerRepresentable {
    let ref: DocumentRef
    let onFileSaved: (Data, String) -> Void
    let onError: (String) -> Void
    let onReady: () -> Void
    let onDirtyChange: (Bool) -> Void
    let onVCReady: (OfficeEditorViewController) -> Void
    let onFilterRequest: ([NativeFilterItem]) -> Void
    let onSlideChange: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        vc.onReady = { Task { @MainActor in onReady() } }
        vc.onDirtyChange = { dirty in Task { @MainActor in onDirtyChange(dirty) } }
        vc.onFilterRequest = { items in Task { @MainActor in onFilterRequest(items) } }
        vc.onSlideChange = { c, t in Task { @MainActor in onSlideChange(c, t) } }
        vc.openFile(at: ref.url)
        Task { @MainActor in onVCReady(vc) }
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}
