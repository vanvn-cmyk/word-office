import Foundation

/// Actor-isolated autosave scheduler.
///
/// Combines two triggers per document (Phase0-Implementation-Logic.md §2):
/// - Debounce window: 2 s of quiet after the last change → save.
/// - Hard interval: guaranteed save every 30 s even if the debounce keeps resetting.
///
/// Actual staging-file + atomic-rename is the responsibility of the writer
/// passed in — the scheduler only decides WHEN to invoke it.
actor AutosaveScheduler: AutosaveScheduling {
    private struct Pending {
        var debounceTask: Task<Void, Never>
        var hardIntervalTask: Task<Void, Never>
        var save: @Sendable () async throws -> Void
    }

    private var pending: [UUID: Pending] = [:]

    private let debounceDelay: Duration
    private let hardIntervalDelay: Duration

    init(
        debounceDelay: Duration = .seconds(2),
        hardIntervalDelay: Duration = .seconds(30)
    ) {
        self.debounceDelay = debounceDelay
        self.hardIntervalDelay = hardIntervalDelay
    }

    // MARK: - AutosaveScheduling

    func scheduleChange(id: UUID, save: @escaping @Sendable () async throws -> Void) async {
        // Cancel the previous debounce task; keep the hard-interval running.
        pending[id]?.debounceTask.cancel()

        let debounceTask = Task { [debounceDelay, weak self] in
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }
            await self?.performSave(id: id)
        }

        let hardTask: Task<Void, Never>
        if let existing = pending[id] {
            hardTask = existing.hardIntervalTask
        } else {
            hardTask = Task { [hardIntervalDelay, weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: hardIntervalDelay)
                    if Task.isCancelled { return }
                    await self?.performSave(id: id)
                }
            }
        }

        pending[id] = Pending(
            debounceTask: debounceTask,
            hardIntervalTask: hardTask,
            save: save
        )
    }

    func cancel(id: UUID) async {
        pending[id]?.debounceTask.cancel()
        pending[id]?.hardIntervalTask.cancel()
        pending.removeValue(forKey: id)
    }

    func flush(id: UUID) async {
        guard let entry = pending[id] else { return }
        entry.debounceTask.cancel()
        do {
            try await entry.save()
        } catch {
            // Sprint 0.1: swallow; Sprint 0.5 wire to SessionStore.autosaveStatus.failed
        }
    }

    // MARK: - Private

    private func performSave(id: UUID) async {
        guard let entry = pending[id] else { return }
        do {
            try await entry.save()
        } catch {
            // Sprint 0.1: swallow; Sprint 0.5 wire to SessionStore.autosaveStatus.failed
        }
    }
}
