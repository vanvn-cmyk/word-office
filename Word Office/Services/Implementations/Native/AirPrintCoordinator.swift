import Foundation
import UIKit

/// Presents `UIPrintInteractionController` (AirPrint) for a document URL — native,
/// independent of the Artifex SDK license. Both tracked competitors call
/// `ARDKPrintPageRenderer`/`UIPrintPageRenderer` directly, so this is low-risk,
/// system-provided territory. See Phase0-Implementation-Logic-v2.md §3.3.
///
/// Locates the presenting view controller via key window scene walk, same
/// approach as `FolderPermissionPicker` — safe to call from anywhere in the
/// SwiftUI hierarchy without threading a UIViewController down.
@MainActor
final class AirPrintCoordinator: NSObject, DocumentPrinting {
    private var continuation: CheckedContinuation<Void, Error>?

    func print(_ url: URL, jobName: String) async throws {
        // Only one print sheet (and one continuation) can be in flight at a time —
        // `UIPrintInteractionController.shared` is itself a singleton. A second
        // concurrent call must fail loudly instead of silently clobbering the
        // first caller's continuation, which would otherwise hang that Task forever.
        guard continuation == nil else {
            throw DocumentPrintingError.printFailed("Another print job is already in progress")
        }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentPrintSheet(for: url, jobName: jobName)
        }
    }

    // MARK: - Presenting

    private func presentPrintSheet(for url: URL, jobName: String) {
        // UIPrintInteractionController presents itself over the key window — no VC
        // to hand it. Still verify a foreground scene exists so failures surface
        // clearly instead of silently doing nothing.
        guard Self.hasForegroundScene() else {
            resumeContinuation(with: .failure(DocumentPrintingError.noPresentingViewController))
            return
        }

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url

        controller.present(animated: true) { [weak self] _, _, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.resumeContinuation(with: .failure(DocumentPrintingError.printFailed(error.localizedDescription)))
                } else {
                    // Second param `completed == false` covers user cancellation — not an error.
                    self.resumeContinuation(with: .success(()))
                }
            }
        }
    }

    private static func hasForegroundScene() -> Bool {
        UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }

    private func resumeContinuation(with result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
