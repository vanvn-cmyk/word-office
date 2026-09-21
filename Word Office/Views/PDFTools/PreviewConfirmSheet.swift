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

import PDFKit
import SwiftUI

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
    @State private var didCommit = false
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PreviewPagedPDFView(url: url, currentPage: $currentPage, totalPages: $totalPages)

                if totalPages > 1 {
                    pageNavigator
                        .padding(.bottom, DSSpacing.md)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            if !didCommit { onCancel() }
        }
    }

    // MARK: - Page navigator pill

    private var pageNavigator: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                currentPage = max(1, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(currentPage <= 1)

            Text("\(currentPage) / \(totalPages)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.primary)
                .frame(minWidth: 52)

            Button {
                currentPage = min(totalPages, currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .disabled(currentPage >= totalPages)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    // MARK: - Save action bar (bottom inset)

    private var saveBar: some View {
        VStack(spacing: DSSpacing.xs) {
            Button {
                didCommit = true
                onConfirm(.newFile)
            } label: {
                Text("Save as new file")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)

            if canReplaceOriginal {
                Button(role: .destructive) {
                    didCommit = true
                    onConfirm(.replaceOriginal)
                } label: {
                    Text("Replace original")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.dsStatusError)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.dsBackgroundSecondary)
    }
}

// MARK: - Single-page PDFView with page-change binding

/// PDFView in single-page mode, wired to parent `currentPage`/`totalPages`
/// bindings so the page-navigator pill in `PreviewConfirmSheet` drives
/// navigation. Matches the same pattern used in `PrintFlowView`.
private struct PreviewPagedPDFView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.autoScales = true
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        let count = view.document?.pageCount ?? 1
        DispatchQueue.main.async {
            self.totalPages = count
            self.currentPage = 1
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
            let count = uiView.document?.pageCount ?? 1
            DispatchQueue.main.async {
                self.totalPages = count
                self.currentPage = 1
            }
            return
        }
        guard let doc = uiView.document,
              let target = doc.page(at: currentPage - 1),
              uiView.currentPage !== target else { return }
        uiView.go(to: target)
    }

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        init(currentPage: Binding<Int>) { _currentPage = currentPage }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let doc  = pdfView.document else { return }
            let idx = doc.index(for: page) + 1
            Task { @MainActor [weak self] in self?.currentPage = idx }
        }
    }
}
