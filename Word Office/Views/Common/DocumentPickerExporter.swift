import SwiftUI
import UIKit

/// Presents `UIDocumentPickerViewController(forExporting:asCopy: true)` —
/// the system "Save to Files" flow that lets the user pick a destination
/// folder (iCloud Drive, On My iPhone, third-party providers). `asCopy: true`
/// so the source file in the app's Documents directory stays put; the picker
/// duplicates it into the chosen location.
///
/// Used from `LibraryView`'s file-row kebab menu → "Save to Files". The
/// picker's own Cancel/pick affordance walks up the containment chain and
/// dismisses whatever presented it — here, the enclosing SwiftUI sheet —
/// so this view must NOT also dismiss it via an injected closure: that
/// caused a double dismiss-animation race, visibly janky on iPad where the
/// sheet's adaptive presentation style differs from iPhone's full sheet.
/// Callers use `.sheet(item:onDismiss:)`/`.sheet(isPresented:onDismiss:)`'s
/// own `onDismiss` — which SwiftUI calls exactly once regardless of how the
/// dismissal happened — to clear their binding.
///
/// Session 19 (2026-09-09) — added `onExportComplete` so callers can
/// distinguish "user picked a destination, files copied" from "user tapped
/// Cancel" without inferring intent from `onDismiss` (which fires on both).
/// Fires with the destination URLs the picker reports; cancel path stays
/// silent (HIG: canceling is user intent, no toast needed).
struct DocumentPickerExporter: UIViewControllerRepresentable {
    let urls: [URL]
    var onExportComplete: ([URL]) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onExportComplete: onExportComplete)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onExportComplete: ([URL]) -> Void

        init(onExportComplete: @escaping ([URL]) -> Void) {
            self.onExportComplete = onExportComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onExportComplete(urls)
        }

        // Deliberately empty — HIG: canceling is user intent, no toast.
        // Kept present so the delegate contract is complete; UIKit routes
        // the cancel path through this method regardless of listener.
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
