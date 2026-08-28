import Foundation
import UIKit
import UniformTypeIdentifiers

/// Presents `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`
/// and returns a `FolderBookmark` when the user grants access. See
/// Phase0-Implementation-Logic-v2.md §4.1 (folder permission + auto-scan).
///
/// Locates the presenting view controller via key window scene walk — safe to call
/// from anywhere in the SwiftUI hierarchy without threading a UIViewController down.
@MainActor
final class FolderPermissionPicker: NSObject, FolderPermissionGranting {
    private var continuation: CheckedContinuation<FolderBookmark?, Error>?

    func requestFolderAccess() async throws -> FolderBookmark? {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presentPicker()
        }
    }

    // MARK: - Presenting

    private func presentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false

        guard let topVC = Self.topViewController() else {
            resumeContinuation(with: .failure(FolderPermissionError.pickerFailed(underlying: "Couldn't find a view controller to present from.")))
            return
        }
        topVC.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func resumeContinuation(with result: Result<FolderBookmark?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let bookmark): continuation.resume(returning: bookmark)
        case .failure(let error):    continuation.resume(throwing: error)
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension FolderPermissionPicker: UIDocumentPickerDelegate {
    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { @MainActor in
            guard let url = urls.first else {
                resumeContinuation(with: .success(nil))
                return
            }
            do {
                let bookmark = try Self.makeBookmark(for: url)
                resumeContinuation(with: .success(bookmark))
            } catch {
                resumeContinuation(with: .failure(error))
            }
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in
            resumeContinuation(with: .success(nil))
        }
    }

    // MARK: Bookmark creation

    @MainActor
    private static func makeBookmark(for url: URL) throws -> FolderBookmark {
        guard url.startAccessingSecurityScopedResource() else {
            throw FolderPermissionError.securityScopeAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let displayPath = displayPath(for: url)
            return FolderBookmark(bookmarkData: data, displayPath: displayPath)
        } catch {
            throw FolderPermissionError.bookmarkCreationFailed(underlying: error.localizedDescription)
        }
    }

    private static func displayPath(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
           let name = values.localizedName {
            return name
        }
        return url.lastPathComponent
    }
}
