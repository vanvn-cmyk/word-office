import Foundation

/// Present a folder picker (`UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`),
/// return the resulting `FolderBookmark` when the user grants access.
/// Called once from onboarding (§10 Library core loop) — Aha moment entry point.
protocol FolderPermissionGranting: Sendable {
    /// Nil if the user cancels the picker. Throws on picker/bookmark failure.
    func requestFolderAccess() async throws -> FolderBookmark?
}

enum FolderPermissionError: Error, Sendable, LocalizedError {
    case pickerFailed(underlying: String)
    case bookmarkCreationFailed(underlying: String)
    case securityScopeAccessDenied

    var errorDescription: String? {
        switch self {
        case .pickerFailed(let u):            "Couldn't open the folder picker: \(u)"
        case .bookmarkCreationFailed(let u):  "Couldn't create folder access: \(u)"
        case .securityScopeAccessDenied:      "The system denied folder access."
        }
    }
}
