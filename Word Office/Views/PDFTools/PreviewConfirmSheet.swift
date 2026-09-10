// Session 12 (2026-09-04) — preview + confirm sheet used by Fill Form
// and Sign after they stage a filled/signed PDF into temp. User sees
// the exact PDF that would land in Documents/ + confirms explicitly
// before it commits. Cancelling deletes the temp file — nothing
// lingers in Library that the user didn't explicitly approve.
//
// Session 19 (2026-09-09) — added the two-way save choice.
// Tap Save → confirmationDialog with:
//   • "Save as new file"     — non-destructive (safe default, listed first)
//   • "Replace original"     — destructive, marked with `role: .destructive`
//                              for the system's automatic red tint
//   • "Cancel"               — automatic via `role: .cancel`
//
// `confirmationDialog` (iOS 15+) is the Apple HIG pattern for a
// multi-choice action that includes a destructive option (see the
// swiftui-expert-skill `references/latest-apis.md` §Presentation and
// Apple HIG "Action Sheets"). The system handles the button ordering,
// destructive tinting, keyboard-escape mapping, and VoiceOver reading
// order — no custom styling needed here, which is why the two options
// are NOT laid out as DS-styled buttons inside the sheet body: system
// dialogs must look like system dialogs so the user recognises the
// decision surface across every iOS app.

import SwiftUI
import UIKit

/// Where the staged preview should land when the user commits.
/// Declared at file scope (not nested in `PreviewConfirmSheet`) so
/// view-model commit methods can accept it as a parameter without
/// importing view types — keeps the VM → View dependency direction
/// intact per the app's MVVM+SOLID convention.
enum PreviewSaveMode: Sendable {
    /// Move the staged temp file into `Documents/` under a
    /// non-conflicting name (`foo signed.pdf`, `foo signed (2).pdf`,
    /// ...). Original source PDF stays untouched — zero data-loss
    /// risk. This is the default action.
    case newFile

    /// Overwrite the source PDF with the staged temp file's contents
    /// via `FileManager.replaceItemAt` (wrapped in
    /// `NSFileCoordinator` write coordination and a security-scoped
    /// resource claim — see `LocalPreviewCommitter`). **The old
    /// contents are unrecoverable on iOS** — the OS overwrites them
    /// in place; there is no user-visible trash/bin to restore from.
    /// (An earlier version of this comment claimed the original went
    /// to a trash bin; iOS has no such thing — code-review finding
    /// #4.) Marked `role: .destructive` in the dialog to communicate
    /// that irreversibility.
    case replaceOriginal
}

struct PreviewConfirmSheet: View {
    let url: URL
    let title: LocalizedStringKey
    /// Toolbar Save button label (e.g., "Save to Home"). The two
    /// save-mode buttons live inside the confirmation dialog with
    /// their own fixed labels.
    let confirmLabel: LocalizedStringKey
    /// True when the source file lives inside the app's library folder
    /// and is therefore safe to overwrite in place (worst case: user
    /// re-runs the operation to recover). False for source URLs picked
    /// through `.fileImporter` from outside the sandbox (iCloud Drive,
    /// third-party Files providers) — those overwrites sync instantly
    /// to every device / collaborator with no client-side recovery
    /// path, so the destructive option is hidden entirely rather than
    /// buried behind an inline warning (code-review finding #13: a
    /// single-tap "Replace original" is too dangerous when the file
    /// isn't the app's own copy).
    let canReplaceOriginal: Bool
    let onConfirm: (PreviewSaveMode) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Set true from either dialog action so `.onDisappear` knows this
    /// dismissal was a commit, not a cancel. Without this flag, a
    /// swipe-to-dismiss (which bypasses the Back button's `onCancel`
    /// call) would leak the staged temp file — see Code Review #2.
    @State private var didCommit = false
    @State private var isChoiceDialogPresented = false
    /// Guards against double-tapping Print while the sheet is already up.
    @State private var isPrinting = false

    var body: some View {
        NavigationStack {
            ReadOnlyPDFPreviewPane(url: url)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmLabel) {
                            // When the source lives outside the app's
                            // library folder, "Replace original"
                            // isn't a safe option to expose (see
                            // `canReplaceOriginal` doc) — skip the
                            // choice dialog and commit directly as a
                            // new file into `documentsURL`. Same one-
                            // tap experience the user got before this
                            // choice dialog was added, no surprise.
                            if canReplaceOriginal {
                                isChoiceDialogPresented = true
                            } else {
                                didCommit = true
                                onConfirm(.newFile)
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            Task { await performPrint() }
                        } label: {
                            Label("Share & Print", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isPrinting)
                    }
                }
                // System confirmation dialog — Apple's own pattern for
                // multi-choice actions that include a destructive
                // option (see `references/latest-apis.md`
                // §Presentation). System styling is intentional: users
                // recognise this surface across iOS, so bespoke DS
                // buttons here would fight the recognition instead of
                // helping it.
                //
                // Order matters: safer action first, destructive
                // second, cancel automatic (`role: .cancel` places it
                // separately at the bottom). Matches iOS Files.app's
                // own "Keep Both / Replace / Cancel" ordering.
                .confirmationDialog(
                    "Save changes",
                    isPresented: $isChoiceDialogPresented,
                    titleVisibility: .visible
                ) {
                    Button("Save as new file") {
                        didCommit = true
                        onConfirm(.newFile)
                    }
                    Button("Replace original", role: .destructive) {
                        didCommit = true
                        onConfirm(.replaceOriginal)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Keep the original untouched, or overwrite it with these changes?")
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Uniform cleanup path — fires for Back tap, swipe-down, AND
        // any other dismissal SwiftUI may add. `didCommit` guards
        // against firing onCancel on the happy path.
        .onDisappear {
            if !didCommit {
                onCancel()
            }
        }
    }

    // MARK: - Print

    private func performPrint() async {
        guard !isPrinting else { return }
        isPrinting = true
        defer { isPrinting = false }

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = url.deletingPathExtension().lastPathComponent
        info.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            controller.present(animated: true) { _, _, _ in cont.resume() }
        }
    }
}
