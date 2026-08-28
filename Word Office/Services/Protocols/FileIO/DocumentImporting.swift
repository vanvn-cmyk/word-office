import Foundation

/// Import files from external sources (Files app, iCloud Drive) into app sandbox.
/// Handles security-scoped resource access, iCloud placeholder download, and duplicate-name resolution.
protocol DocumentImporting: Sendable {
    /// Import multiple URLs. Returns per-URL result — one failure does not stop the batch (§5.3).
    func importFiles(from urls: [URL]) async -> [ImportOutcome]
}

struct ImportOutcome: Sendable {
    let sourceURL: URL
    let result: Result<DocumentRef, ImportError>
}

enum ImportError: Error, Sendable, LocalizedError {
    case securityScopeAccessDenied
    case iCloudDownloadFailed(underlying: String)
    case unsupportedType(extension: String)
    case copyFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .securityScopeAccessDenied:  "Can't access the file — the system blocked permission."
        case .iCloudDownloadFailed(let u):"iCloud download failed: \(u)"
        case .unsupportedType(let ext):   "File type .\(ext) is not supported yet."
        case .copyFailed(let u):          "Couldn't copy the file into the app: \(u)"
        }
    }
}
