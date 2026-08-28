import Foundation

/// Debounced autosave scheduler. Coalesces rapid change signals into a single
/// write via a debounce window + a hard-interval fallback. See
/// Phase0-Implementation-Logic.md §2 for staging-file + atomic-rename rationale.
protocol AutosaveScheduling: Sendable {
    /// Signal that content has changed. Resets the debounce window.
    func scheduleChange(id: UUID, save: @escaping @Sendable () async throws -> Void) async

    /// Cancel any pending save for the given id.
    func cancel(id: UUID) async

    /// Flush any pending save immediately (e.g. app enters background).
    func flush(id: UUID) async
}
