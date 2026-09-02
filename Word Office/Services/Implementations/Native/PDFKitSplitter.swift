import Foundation
import PDFKit

/// Splits a PDF into multiple files by page range with `PDFKit` — native,
/// independent of the Artifex SDK license.
/// See Phase0-Implementation-Logic-v2.md §7.1 + §7.3 (validate-on-write).
final class PDFKitSplitter: PDFSplitting {
    func split(_ url: URL, ranges: [ClosedRange<Int>], into directory: URL) async throws -> [URL] {
        guard !ranges.isEmpty else { throw PDFSplitError.emptyRanges }

        // §7.3 — must run off the caller's actor, same reasoning as `PDFKitMerger`.
        return try await Task.detached(priority: .utility) {
            guard let source = PDFDocument(url: url) else { throw PDFSplitError.unreadableDocument }

            let pageCount = source.pageCount
            for range in ranges {
                guard range.lowerBound >= 0, range.upperBound < pageCount else {
                    throw PDFSplitError.rangeOutOfBounds(range, pageCount: pageCount)
                }
            }

            let stem = url.deletingPathExtension().lastPathComponent
            var outputURLs: [URL] = []
            let fileManager = FileManager.default

            for (index, range) in ranges.enumerated() {
                let part = PDFDocument()
                for pageIndex in range {
                    guard let page = source.page(at: pageIndex) else { continue }
                    part.insert(page, at: part.pageCount)
                }

                // Non-conflicting name — splitting the same source twice (or a
                // second source sharing this stem) must not silently overwrite
                // a prior split's output (§4.4).
                let destination = fileManager.nonConflictingURL(for: "\(stem) (\(index + 1)).pdf", in: directory)
                guard part.write(to: destination) else {
                    throw PDFSplitError.writeFailed
                }
                // Confirm the written part re-opens before reporting success.
                guard PDFDocument(url: destination) != nil else {
                    throw PDFSplitError.writeFailed
                }
                outputURLs.append(destination)
            }

            return outputURLs
        }.value
    }
}
