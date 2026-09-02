import Foundation
import PDFKit
import UIKit

/// Combines images into a multi-page PDF — native `UIGraphicsPDFRenderer`, each
/// page sized to its own image. See Phase0-Implementation-Logic-v2.md §7.4.
final class UIGraphicsImagePDFExporter: ImagePDFExporting {
    func exportPDF(from images: [UIImage], to destination: URL) async throws {
        guard !images.isEmpty else { throw ImagePDFExportError.emptyInput }

        // `UIImage` isn't `Sendable` — encode to PNG `Data` (which is) on the
        // caller's actor before crossing into `Task.detached`, rather than
        // capturing the `UIImage`s themselves. Typical input here is a handful
        // of photos, so this main-actor encoding cost is small.
        let pngDatas = images.compactMap { $0.pngData() }
        guard pngDatas.count == images.count else {
            throw ImagePDFExportError.encodingFailed
        }

        try await Task.detached(priority: .utility) {
            let renderer = UIGraphicsPDFRenderer(bounds: .zero)
            let data = renderer.pdfData { context in
                for pngData in pngDatas {
                    guard let image = UIImage(data: pngData) else { continue }
                    let pageRect = CGRect(origin: .zero, size: image.size)
                    context.beginPage(withBounds: pageRect, pageInfo: [:])
                    image.draw(in: pageRect)
                }
            }
            try data.write(to: destination)
            guard PDFDocument(url: destination) != nil else {
                throw ImagePDFExportError.writeFailed
            }
        }.value
    }
}
