import Foundation
import Observation

@Observable
@MainActor
final class EditorViewModel {
    let ref: DocumentRef
    var content: DocumentContent
    private(set) var isLoading: Bool = false
    private(set) var isDirty: Bool = false
    var errorMessage: String?

    private let reader: any DocumentReading
    private let writer: any DocumentWriting
    private let autosave: any AutosaveScheduling
    /// Tracks `markDirty()`'s in-flight `scheduleChange` registration so
    /// `flushIfNeeded()` can wait for it — see that method's comment.
    private var registrationTask: Task<Void, Never>?

    init(
        ref: DocumentRef,
        reader: any DocumentReading,
        writer: any DocumentWriting,
        autosave: any AutosaveScheduling
    ) {
        self.ref = ref
        self.reader = reader
        self.writer = writer
        self.autosave = autosave
        self.content = DocumentContent(kind: ref.kind)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            content = try await reader.read(from: ref.url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markDirty() {
        isDirty = true
        let refID = ref.id
        let url = ref.url
        let snapshot = content
        let writer = self.writer
        // Chains onto the previous registration instead of firing a sibling
        // unstructured `Task` — two separate `Task { await actor... }` calls
        // have no ordering guarantee relative to each other even when created
        // one after another, so two rapid keystrokes could reach the actor
        // out of order and leave the *older* snapshot's save closure as the
        // one `AutosaveScheduler` actually runs. Awaiting `previous` first
        // makes registration order match call order.
        let previous = registrationTask
        registrationTask = Task { [autosave] in
            _ = await previous?.value
            await autosave.scheduleChange(
                id: refID,
                save: { try await writer.write(snapshot, to: url) },
                onResult: { [weak self] outcome in
                    self?.handleAutosaveOutcome(outcome, for: snapshot)
                }
            )
        }
    }

    /// Called when the app is about to background or the editor is dismissed.
    ///
    /// `markDirty()` registers with `AutosaveScheduler` (an actor) from an
    /// unstructured `Task`, so the registration isn't guaranteed to have landed
    /// yet the instant `markDirty()` returns. Without waiting for it here, a
    /// flush that lands in that gap finds nothing pending in the scheduler and
    /// silently no-ops — `isDirty` stays true but no save happens. Awaiting the
    /// same task `markDirty()` started closes the gap deterministically.
    func flushIfNeeded() async {
        guard isDirty else { return }
        await registrationTask?.value
        await autosave.flush(id: ref.id)
        // `isDirty` is left to `handleAutosaveOutcome` — flush still goes through
        // the same `onResult` path, so a failed flush correctly keeps it `true`
        // instead of lying that the content is safely on disk.
    }

    /// Call when the editor screen is going away for good (not just backgrounding
    /// — that path wants `flushIfNeeded()`, not this). `AutosaveScheduler` runs a
    /// hard-interval task per `id` that repeats forever every 30s until
    /// `cancel(id:)` is called — nothing was calling it, so every closed editor
    /// leaked a timer that kept re-writing its last captured snapshot to disk
    /// indefinitely for the rest of the process lifetime, silently clobbering
    /// any newer write to the same file (iCloud sync, another editor session).
    func stopAutosaving() async {
        await autosave.cancel(id: ref.id)
    }

    /// Never swallows a failed autosave (§7.3 "never silent data loss") — surfaces
    /// it via `errorMessage` and keeps `isDirty` true so the UI still shows unsaved work.
    @MainActor
    private func handleAutosaveOutcome(_ outcome: AutosaveOutcome, for snapshot: DocumentContent) {
        switch outcome {
        case .saved:
            errorMessage = nil
            // Only clear the flag if nothing changed since this save started —
            // a newer edit already scheduled its own save that must still run.
            if content == snapshot { isDirty = false }
        case .failed(let message):
            errorMessage = message
        }
    }
}
