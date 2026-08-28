import Foundation

protocol DocumentExporting: Sendable {
    /// Export document to PDF at the given destination URL.
    func exportPDF(from source: URL, to destination: URL) async throws
}
