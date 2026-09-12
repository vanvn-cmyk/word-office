import SwiftUI
import Network

/// Full-screen offline ONLYOFFICE editor for Office formats (DOCX, XLSX, PPTX).
///
/// Runs x2t.wasm + virtual document server entirely in WKWebView — no server needed.
///
/// Flow:
///   1. WKWebView loads `office://host/editor.html` (from OfficeBundle in app bundle).
///   2. After the page loads, `OfficeEditorViewController` sends the file via
///      `callAsyncJavaScript("receiveFileFromIOS(...)")`.
///   3. x2t.wasm converts DOCX→internal format; ONLYOFFICE editor renders.
///   4. User saves → JS intercepts `a.click()` → Swift receives `Data` → writes to original URL.
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
    @State private var showFormatStudio = false
    @State private var editorVC: OfficeEditorViewController?

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
                        onCommand: { cmd in editorVC?.execEditorCommand(cmd) },
                        onFormat: { showFormatStudio = true }
                    )

                    _OfficeWebView(
                        ref: ref,
                        onFileSaved: handleSave,
                        onError: handleError,
                        onReady: handleReady,
                        onDirtyChange: { isDirty = $0 },
                        onShowFormatStudio: { showFormatStudio = true },
                        onVCReady: { editorVC = $0 }
                    )
                    .overlay(alignment: .topTrailing) {
                        if saveCount > 0 { saveBadge }
                    }
                }
                .sheet(isPresented: $showFormatStudio) {
                    let vc = editorVC
                    FormatStudioView { cmd in
                        vc?.execEditorCommand(cmd)
                    }
                }
            }
        }
        .preference(key: EditorDirtyPreferenceKey.self, value: isDirty)
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkNetworkOnFirstLaunch() }
    }

    // Once the editor fires onReady the sdkjs is cached by WKWebView — mark it
    // so subsequent launches skip the network check and work offline.
    private func handleReady() {
        UserDefaults.standard.set(true, forKey: kCacheReadyKey)
    }

    // Only block if sdkjs has never been cached AND there's no network.
    // After the first successful launch the WKWebView disk cache covers offline use.
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
            // NSFileCoordinator is required for iCloud Drive documents: the cloud
            // daemon may be reading or uploading the file concurrently. Without it,
            // writing races the provider and can produce iCloud conflict copies.
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
        // If the editor engine failed to load, the WKWebView cache was likely evicted
        // (low storage, OS cleanup, app update). Reset the flag so the next launch
        // proactively checks network instead of silently failing again.
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
    let onShowFormatStudio: () -> Void
    let onVCReady: (OfficeEditorViewController) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        vc.onReady = { Task { @MainActor in onReady() } }
        vc.onDirtyChange = { dirty in Task { @MainActor in onDirtyChange(dirty) } }
        vc.onShowFormatStudio = { Task { @MainActor in onShowFormatStudio() } }
        vc.openFile(at: ref.url)
        // Defer to avoid mutating @State during the render pass
        Task { @MainActor in onVCReady(vc) }
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}
