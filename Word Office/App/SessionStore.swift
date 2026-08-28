import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {
    var currentDocument: DocumentRef?
    var isDirty: Bool = false
    var autosaveStatus: AutosaveStatus = .idle

    enum AutosaveStatus: Equatable {
        case idle
        case pending
        case saving
        case saved(at: Date)
        case failed(message: String)
    }

    func open(_ ref: DocumentRef) {
        currentDocument = ref
        isDirty = false
        autosaveStatus = .idle
    }

    func close() {
        currentDocument = nil
        isDirty = false
        autosaveStatus = .idle
    }
}
