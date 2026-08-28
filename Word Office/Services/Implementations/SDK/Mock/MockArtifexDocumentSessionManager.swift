import Foundation

/// Mock implementation of DocumentSessionManaging.
/// Sprint 0.1: return dummy session handle. Real Artifex SDK swap in Sprint 0.2
/// when the license lands — behind #if USE_MOCK_SDK in DependencyContainer.
final class MockArtifexDocumentSessionManager: DocumentSessionManaging {
    func openDocument(at url: URL) async throws -> DocumentSessionHandle {
        let kind = DocumentKind.fromUTI(url: url) ?? .txt
        let ref = DocumentRef(
            name: url.lastPathComponent,
            url: url,
            modifiedAt: Date(),
            kind: kind
        )
        return DocumentSessionHandle(id: UUID(), ref: ref)
    }

    func closeDocument(_ handle: DocumentSessionHandle) async {
        // Mock: no-op
    }
}
