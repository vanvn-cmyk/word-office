import UIKit
import UniformTypeIdentifiers

/// Presents `UIDocumentPickerViewController` directly via UIKit, bypassing
/// SwiftUI's `.fileImporter` queuing rule that forces the presenter sheet to
/// fully dismiss before the picker can appear.
///
/// Usage: schedule `present(...)` with `Task { @MainActor in }` from inside
/// the source-sheet button action — AFTER `dismiss()` has been called on the
/// sheet. UIKit clears `presentedViewController` synchronously on `dismiss()`,
/// so the next run-loop tick (when the Task fires) finds the root VC free and
/// can present the picker while the sheet's dismiss animation is still in
/// progress. Result: both animations play concurrently with no dead gap.
@MainActor
final class DeviceFilePickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let onCompletion: (Result<[URL], Error>) -> Void

    // Strong self-reference so ARC doesn't collect us while the picker is open.
    private static var current: DeviceFilePickerCoordinator?

    private init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
        self.onCompletion = onCompletion
    }

    /// Finds the foreground key-window root VC and presents a document picker
    /// from it. Call from a `Task { @MainActor in }` block so the call executes
    /// on the next run-loop tick, after the source sheet's `dismiss()` has
    /// cleared `rootVC.presentedViewController`.
    static func present(
        allowedTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) {
        guard let rootVC = keyWindowRootVC() else { return }
        let coordinator = DeviceFilePickerCoordinator(onCompletion: onCompletion)
        Self.current = coordinator

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = coordinator
        rootVC.present(picker, animated: true)
    }

    private static func keyWindowRootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    // MARK: UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        onCompletion(.success(urls))
        Self.current = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCompletion(.failure(CocoaError(.userCancelled)))
        Self.current = nil
    }
}
