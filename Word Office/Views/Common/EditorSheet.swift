import SwiftUI

/// Sheet wrapper for `EditorPlaceholderView` — owns its own `dismiss`
/// environment so the Done button closes via `dismiss()` instead of writing
/// to the parent's `editingRef` binding from outside (swiftui-expert-skill
/// convention: "sheets own their actions").
///
/// Hosts its own `.toastHost(_:)` overlay so any success toast fired right
/// before the sheet appears (or while it's up) stays visible — SwiftUI
/// sheets sit above the scene-root overlay in z-order, so the presenter
/// installed in `Word_OfficeApp` alone would render below and stay hidden.
///
/// Consolidated in Session 14 from two byte-for-byte identical wrappers
/// (`LibraryEditorSheet` in `RootView`, `ToolsEditorSheet` in `ToolsTabView`)
/// so future changes to the editor's toolbar / dismiss / toast-hosting
/// pattern land in exactly one place.
struct EditorSheet: View {
    let container: DependencyContainer
    let ref: DocumentRef

    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    var body: some View {
        NavigationStack {
            EditorPlaceholderView(container: container, ref: ref)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .toastHost(toaster)
    }
}
