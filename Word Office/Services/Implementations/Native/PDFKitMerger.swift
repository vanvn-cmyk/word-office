import Foundation
import PDFKit

/// Merges PDFs with `PDFKit` — native, independent of the Artifex SDK license.
/// See Phase0-Implementation-Logic-v2.md §7.1 + §7.3 (validate-on-write, not just "wrote without error").
final class PDFKitMerger: PDFMerging {
    func merge(_ urls: [URL], into destination: URL) async throws {
        guard !urls.isEmpty else { throw PDFMergeError.emptyInput }

        // §7.3 — must run off the caller's actor. `async` alone doesn't guarantee
        // that: with no `await` inside, the body would otherwise run synchronously
        // on whatever context called it (often MainActor from a ViewModel).
        try await Task.detached(priority: .utility) {
            let output = PDFDocument()
            for url in urls {
                guard let doc = PDFDocument(url: url) else {
                    throw PDFMergeError.unreadableDocument(url)
                }
                for pageIndex in 0..<doc.pageCount {
                    guard let page = doc.page(at: pageIndex) else { continue }
                    output.insert(page, at: output.pageCount)
                }
            }

            guard output.write(to: destination) else {
                throw PDFMergeError.writeFailed
            }

            // A successful write can still be structurally broken — confirm it re-opens.
            guard PDFDocument(url: destination) != nil else {
                throw PDFMergeError.writeFailed
            }
        }.value
    }
}
