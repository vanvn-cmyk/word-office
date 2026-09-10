import SwiftUI

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
struct OfficeEditorView: View {
    let ref: DocumentRef

    @State private var errorMessage: String? = nil
    @State private var saveCount = 0

    var body: some View {
        Group {
            if let msg = errorMessage {
                ContentUnavailableView(
                    "Could Not Open Document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            } else {
                _OfficeWebView(ref: ref, onFileSaved: handleSave, onError: handleError)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        if saveCount > 0 {
                            saveBadge
                        }
                    }
            }
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
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
            try? data.write(to: dest, options: .atomic)
            await MainActor.run { saveCount += 1 }
        }
    }

    private func handleError(_ message: String) {
        Task { @MainActor in errorMessage = message }
    }
}

// MARK: - UIViewControllerRepresentable

private struct _OfficeWebView: UIViewControllerRepresentable {
    let ref: DocumentRef
    let onFileSaved: (Data, String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        // Set the file URL before viewDidLoad so it's available when the page finishes loading
        vc.openFile(at: ref.url)
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}
