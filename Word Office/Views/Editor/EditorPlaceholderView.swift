import SwiftUI

/// Sprint 0.1 editor placeholder. Sprint 0.2 replaces with SDKEditorHostView
/// (`UIViewControllerRepresentable` wrapping the Artifex editor) — see arch v2.1 §5.
struct EditorPlaceholderView: View {
    let container: DependencyContainer
    let ref: DocumentRef

    @State private var editorVM: EditorViewModel?

    var body: some View {
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
    }

    @ViewBuilder
    private func content(for vm: EditorViewModel) -> some View {
        VStack(spacing: DSSpacing.md) {
            if vm.isLoading {
                ProgressView()
            }

            switch ref.kind {
            case .txt, .rtf, .markdown:
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

            default:
                EmptyStateView(
                    icon: ref.kind.systemImage,
                    title: "\(ref.kind.displayName) preview",
                    message: "Full editing available once the Artifex SDK is licensed (Sprint 0.2)."
                )
            }
        }
        .background(Color.dsDocumentCanvas)
    }
}
