import Foundation

protocol DocumentReading: Sendable {
    func read(from url: URL) async throws -> DocumentContent
}
