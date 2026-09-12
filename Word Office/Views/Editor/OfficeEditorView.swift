import SwiftUI
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

    @State private var errorMessage: String? = nil
    @State private var saveCount = 0
    @State private var isDirty = false
    @State private var editorVC: OfficeEditorViewController?

    // Native photo insertion
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem? = nil

    // Native filter sheet (replaces ONLYOFFICE's web filter panel)
    @State private var filterItems: [NativeFilterItem] = []
    @State private var showFilterSheet = false

    // Native insert sheets
    @State private var showLinkSheet    = false
    @State private var showCommentSheet = false

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
                        }
                    )
                    .overlay(alignment: .topTrailing) {
                        if saveCount > 0 { saveBadge }
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
                // Native hyperlink insert sheet
                .sheet(isPresented: $showLinkSheet) {
                    NativeLinkView(
                        onCommit: { url, text in
                            showLinkSheet = false
                            editorVC?.insertHyperlink(url: url, displayText: text)
                        },
                        onCancel: { showLinkSheet = false }
                    )
                }
                // Native comment insert sheet
                .sheet(isPresented: $showCommentSheet) {
                    NativeCommentView(
                        onCommit: { text in
                            showCommentSheet = false
                            editorVC?.addComment(text: text)
                        },
                        onCancel: { showCommentSheet = false }
                    )
                }
            }
        }
        .preference(key: EditorDirtyPreferenceKey.self, value: isDirty)
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkNetworkOnFirstLaunch() }
    }

    // MARK: - Command routing

    private func handleCommand(_ cmd: String) {
        switch cmd {
        case "insert-image":   showImagePicker = true
        case "insert-link":    showLinkSheet    = true
        case "insert-comment": showCommentSheet = true
        default:               editorVC?.execEditorCommand(cmd)
        }
    }

    // MARK: - Image insertion

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        defer { imagePickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        // Detect MIME type from magic bytes
        let mime: String
        if data.prefix(2) == Data([0xFF, 0xD8]) { mime = "image/jpeg" }
        else if data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) { mime = "image/png" }
        else { mime = "image/jpeg" }

        // Resize large images to stay within WKWebView JS string limit (~60 MB base64)
        let imageData: Data
        if data.count > 4_000_000, let img = UIImage(data: data),
           let compressed = img.jpegData(compressionQuality: 0.7) {
            imageData = compressed
        } else {
            imageData = data
        }

        let b64 = imageData.base64EncodedString()
        let dataURL = "data:\(mime);base64,\(b64)"
        editorVC?.insertImage(dataURL: dataURL)
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
                await MainActor.run { saveCount += 1 }
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        vc.onReady = { Task { @MainActor in onReady() } }
        vc.onDirtyChange = { dirty in Task { @MainActor in onDirtyChange(dirty) } }
        vc.onFilterRequest = { items in Task { @MainActor in onFilterRequest(items) } }
        vc.openFile(at: ref.url)
        Task { @MainActor in onVCReady(vc) }
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}
