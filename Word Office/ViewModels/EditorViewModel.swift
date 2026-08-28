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
        Task { [autosave] in
            await autosave.scheduleChange(id: refID) {
                try await writer.write(snapshot, to: url)
            }
        }
    }

    /// Called when the app is about to background or the editor is dismissed.
    func flushIfNeeded() async {
        guard isDirty else { return }
        await autosave.flush(id: ref.id)
        isDirty = false
    }
}
