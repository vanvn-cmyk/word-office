import Foundation

/// Wraps the SDK's session lifecycle. Opens a document, exposes a runtime handle,
/// and closes cleanly. The concrete impl bridges Artifex (Mock/Real).
protocol DocumentSessionManaging: Sendable {
    func openDocument(at url: URL) async throws -> DocumentSessionHandle
    func closeDocument(_ handle: DocumentSessionHandle) async
}

/// Opaque handle to a live document session held by the engine.
/// The View layer receives this and passes it to SDKEditorHostView; it never
/// inspects the internals.
struct DocumentSessionHandle: Hashable, Sendable {
    let id: UUID
    let ref: DocumentRef
}
