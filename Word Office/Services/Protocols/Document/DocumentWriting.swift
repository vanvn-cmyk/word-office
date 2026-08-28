import Foundation

protocol DocumentWriting: Sendable {
    func write(_ content: DocumentContent, to url: URL) async throws
}
