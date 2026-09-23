import SwiftUI

extension Notification.Name {
    static let editorSaveRequested = Notification.Name("editorSaveRequested")
    /// Posted by the Done button in OfficeEditorView after the save delay.
    /// EditorSheet listens and calls onDone + dismiss — only this path sets .done.
    /// The ✕ button path (closeEditor) does NOT call onDone.
    static let editorDoneRequested = Notification.Name("editorDoneRequested")
}

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
    /// Called immediately before dismiss — use to record status changes.
    var onDone: (() -> Void)? = nil
    /// Called (before dismiss) when the user wants to Sign the current PDF.
    var onSign: ((URL) -> Void)? = nil
    /// Called (before dismiss) when the user wants to Print the current PDF.
    var onPrint: ((URL) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    @AppStorage("hasSeenRotateHint") private var hasSeenRotateHint = false

    @State private var isDirty = false
    @State private var showDiscardAlert = false
    @State private var showRotateHint = false

    var body: some View {
        NavigationStack {
            EditorPlaceholderView(container: container, ref: ref)
                .toolbar {
                    // x — plain icon, no extra background (nav bar already provides hit area)
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if isDirty { showDiscardAlert = true } else { closeEditor() }
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.light)
                        }
                    }
                    // Sign & Print quick actions — only for PDFs (read-only in editor)
                    if ref.url.pathExtension.lowercased() == "pdf", onSign != nil || onPrint != nil {
                        ToolbarItem(placement: .primaryAction) {
                            HStack(spacing: DSSpacing.xs) {
                                if let onSign {
                                    Button {
                                        onSign(ref.url)
                                        closeEditor()
                                    } label: {
                                        Label("Sign", systemImage: "signature")
                                    }
                                }
                                if let onPrint {
                                    Button {
                                        onPrint(ref.url)
                                        closeEditor()
                                    } label: {
                                        Label("Print", systemImage: "printer")
                                    }
                                }
                            }
                        }
                    }
                }
        }
        .interactiveDismissDisabled(isDirty)
        .onPreferenceChange(EditorDirtyPreferenceKey.self) { isDirty = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .editorDoneRequested)) { _ in
            onDone?()
            dismiss()
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showDiscardAlert,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { closeEditor() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unsaved edits will be lost.")
        }
        .overlay {
            if showRotateHint {
                RotateHintOverlay { showRotateHint = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showRotateHint)
        .toastHost(toaster)
        .onAppear {
            OrientationManager.shared.allowAll()
            scheduleRotateHintIfNeeded()
        }
        .onDisappear { OrientationManager.shared.lockToPortrait() }
    }

    private func closeEditor() {
        dismiss()
    }

    private func scheduleRotateHintIfNeeded() {
        guard !hasSeenRotateHint,
              ref.kind.isOnlyOfficeEditable,
              UIDevice.current.userInterfaceIdiom == .phone
        else { return }
        hasSeenRotateHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showRotateHint = true
        }
    }
}
