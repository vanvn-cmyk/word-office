import Foundation
import PDFKit
import UIKit

/// Exports PDF pages as PNG — native `PDFKit`, rendering each page via
/// `PDFPage.thumbnail(of:for:)`. See Phase0-Implementation-Logic-v2.md §7.4.
final class PDFKitImageExporter: PDFImageExporting {
    func exportImages(from url: URL, pageRange: ClosedRange<Int>?, into directory: URL) async throws -> [URL] {
        try await Task.detached(priority: .utility) {
            guard let document = PDFDocument(url: url) else {
                throw PDFImageExportError.unreadableDocument
            }
            let pageCount = document.pageCount
            let range = pageRange ?? 0...max(0, pageCount - 1)
            guard pageCount > 0, range.lowerBound >= 0, range.upperBound < pageCount else {
                throw PDFImageExportError.rangeOutOfBounds(range, pageCount: pageCount)
            }

            let stem = url.deletingPathExtension().lastPathComponent
            let fileManager = FileManager.default
            var outputURLs: [URL] = []

            for pageIndex in range {
                guard let page = document.page(at: pageIndex) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2 // ~144dpi — sharp enough for screen/share, not print-grade
                let targetSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
                let image = page.thumbnail(of: targetSize, for: .mediaBox)
                guard let data = image.pngData() else {
                    throw PDFImageExportError.writeFailed
                }
                let destination = fileManager.nonConflictingURL(for: "\(stem) \(pageIndex + 1).png", in: directory)
                try data.write(to: destination)
                outputURLs.append(destination)
            }

            return outputURLs
        }.value
    }
}
