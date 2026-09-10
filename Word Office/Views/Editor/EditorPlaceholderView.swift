import SwiftUI

/// Sprint 0.1 editor placeholder. Sprint 0.2 replaces with SDKEditorHostView
/// (`UIViewControllerRepresentable` wrapping the Artifex editor) — see arch v2.1 §5.
///
/// Session 12 (2026-09-04) — PDFs get real preview via `ReadOnlyPDFPreviewPane`
/// (PDFKit native), not the placeholder. Tool outputs (Merge/Split/Convert/
/// Sign/Fill Form) are all PDFs, so the auto-open editor after a tool save
/// showing "coming when SDK licensed" was misleading — the file WAS saved,
/// just not viewable. PDFView side-steps the Artifex block entirely.
struct EditorPlaceholderView: View {
    let container: DependencyContainer
    let ref: DocumentRef

    @State private var editorVM: EditorViewModel?

    var body: some View {
        // Office formats (DOCX, XLSX, PPTX, DOC, XLS, PPT) → ONLYOFFICE offline editor
        // Runs x2t.wasm + virtual document server in WKWebView — no server needed.
        if ref.kind.isOfficeFormat {
            OfficeEditorView(ref: ref)
        } else {
            nativeEditorView
        }
    }

    // PDF + plain text formats use native rendering
    @ViewBuilder
    private var nativeEditorView: some View {
        Group {
            if let vm = editorVM {
                content(for: vm)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            let vm = container.makeEditorViewModel(for: ref)
            editorVM = vm
            await vm.load()
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            guard let vm = editorVM else { return }
            Task {
                await vm.flushIfNeeded()
                await vm.stopAutosaving()
            }
        }
    }

    @ViewBuilder
    private func content(for vm: EditorViewModel) -> some View {
        VStack(spacing: DSSpacing.md) {
            if vm.isLoading {
                ProgressView()
            }

            if let errorMessage = vm.errorMessage {
                ErrorBanner(message: errorMessage) {
                    vm.errorMessage = nil
                }
                .padding(.horizontal, DSSpacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            switch ref.kind {
            case .txt, .rtf, .markdown, .docx:
                // Sprint 0.1: real editing via a simple TextEditor bridge.
                // Sprint 0.2 upgrades to UITextView bridge (rich text + UndoManager + selection binding).
                @Bindable var bindableVM = vm
                TextEditor(text: Binding(
                    get: { String(bindableVM.content.attributedText.characters) },
                    set: { newValue in
                        bindableVM.content.attributedText = AttributedString(newValue)
                        vm.markDirty()
                    }
                ))
                .font(DSFont.body)
                .padding(DSSpacing.md)
                .background(Color.dsDocumentPage)

            case .pdf:
                // PDFKit native preview — read-only, zoomable, scrollable.
                // Every tool in the Tools tab produces a PDF, so this is
                // what the auto-navigate-after-save flow actually shows.
                ReadOnlyPDFPreviewPane(url: ref.url)

            default:
                EmptyStateView(
                    icon: ref.kind.systemImage,
                    title: "\(ref.kind.displayName) preview",
                    message: "Full editing available once the Artifex SDK is licensed (Sprint 0.2)"
                )
            }
        }
        .animation(.default, value: vm.errorMessage)
        .background(Color.dsDocumentCanvas)
    }
}
