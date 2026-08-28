import Foundation

/// Scans the app sandbox `Documents/` for orphan `.autosave.tmp` files left by a
/// previous crash — the counterpart to `AutosaveScheduler`'s staging-file writes
/// (Phase0-Implementation-Logic.md §2). If autosave crashed mid-write, the
/// staging file survives without ever being atomically renamed onto the
/// original; on next launch this scanner surfaces those so the user can decide
/// to keep or discard.
protocol CrashRecoveryScanning: Sendable {
    /// Enumerate orphan staging files. Called once on app launch. Safe to call
    /// again — the scanner is stateless and does not consume orphans until
    /// `discardOrphan(_:)` is invoked.
    func scanForOrphans() async -> [CrashRecoveryOrphan]

    /// Remove the staging file. Used both when the user rejects recovery and
    /// after a successful restore (once the caller has copied the content over
    /// the original).
    func discardOrphan(_ orphan: CrashRecoveryOrphan) async throws
}

/// One recoverable orphan pair. `originalURL` is the intended target of the
/// autosave write — the caller can compare it against the current file on disk
/// to offer a diff, or overwrite outright.
struct CrashRecoveryOrphan: Hashable, Sendable {
    let originalURL: URL
    let autosaveURL: URL
    let name: String
    let modifiedAt: Date
}

enum CrashRecoveryError: Error, Sendable, LocalizedError {
    case discardFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .discardFailed(let u): "Could not remove recovery file: \(u)"
        }
    }
}
