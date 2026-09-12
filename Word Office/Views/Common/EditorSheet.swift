import SwiftUI

/// Full-screen cover wrapper for `EditorPlaceholderView`.
///
/// Owns dismiss so the Done button closes via `dismiss()` (swiftui-expert-skill
/// convention: "sheets own their actions"). Intercepts dismiss when the document
/// has unsaved changes — shows a destructive confirmation dialog first.
///
/// Receives dirty state via `EditorDirtyPreferenceKey` which bubbles up through
/// the view hierarchy from `OfficeEditorView` without requiring a direct binding
/// through the intermediate `EditorPlaceholderView`.
///
/// Hosts its own `.toastHost(_:)` overlay so success toasts fired while the
/// cover is up remain visible above the cover's z-order.
struct EditorSheet: View {
    let container: DependencyContainer
    let ref: DocumentRef

    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            EditorPlaceholderView(container: container, ref: ref)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if isDirty { showDiscardAlert = true } else { dismiss() }
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        // Disable swipe-to-dismiss gesture when there are unsaved changes.
        .interactiveDismissDisabled(isDirty)
        // Receive dirty state bubbled up from OfficeEditorView.
        .onPreferenceChange(EditorDirtyPreferenceKey.self) { isDirty = $0 }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showDiscardAlert,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unsaved edits will be lost.")
        }
        .toastHost(toaster)
        .onAppear { OrientationManager.shared.allowAll() }
        .onDisappear { OrientationManager.shared.lockToPortrait() }
    }
}
