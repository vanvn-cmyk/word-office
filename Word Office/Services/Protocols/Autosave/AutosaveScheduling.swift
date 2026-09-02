import Foundation

/// Debounced autosave scheduler. Coalesces rapid change signals into a single
/// write via a debounce window + a hard-interval fallback. See
/// Phase0-Implementation-Logic.md §2 for staging-file + atomic-rename rationale.
protocol AutosaveScheduling: Sendable {
    /// Signal that content has changed. Resets the debounce window.
    /// `onResult` fires on `MainActor` after every attempted save (scheduled or
    /// flushed) — callers must not swallow it silently (§7.3 "never silent data loss").
    func scheduleChange(
        id: UUID,
        save: @escaping @Sendable () async throws -> Void,
        onResult: @escaping @MainActor @Sendable (AutosaveOutcome) -> Void
    ) async

    /// Cancel any pending save for the given id.
    func cancel(id: UUID) async

    /// Flush any pending save immediately (e.g. app enters background).
    func flush(id: UUID) async
}

/// Result of one attempted autosave write, reported back to the caller via
/// `scheduleChange`'s `onResult`. `message` is already a display-ready string
/// (`Error.localizedDescription`) so `AutosaveOutcome` stays `Sendable` without
/// requiring the underlying `Error` type to be.
enum AutosaveOutcome: Equatable, Sendable {
    case saved
    case failed(message: String)
}
