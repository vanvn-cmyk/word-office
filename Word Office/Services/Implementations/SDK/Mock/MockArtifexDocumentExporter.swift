import Foundation
import PDFKit
import UIKit

/// Mock `DocumentExporting`. Sprint 0.3, §7.4 — DOCX export is real (extracts text
/// via `DOCXCodec`, renders to a single-page PDF), same "real where cheap" pattern
/// `MockArtifexDocumentReader` already uses. XLSX/PPTX render a placeholder-notice
/// PDF until the real Artifex SDK lands (still blocked — see memory
/// `artifex-sdk-integration-blocked`) and its `exportAs(.pdf)` swaps in behind
/// `#if USE_MOCK_SDK` in `DependencyContainer`.
///
/// Plain-text, single-page only — no pagination, no formatting/images/tables.
/// Good enough for a Mock fallback; the real SDK replaces this entirely.
final class MockArtifexDocumentExporter: DocumentExporting {
    func exportPDF(from source: URL, to destination: URL) async throws {
        let kind = DocumentKind.fromUTI(url: source) ?? .txt
        let text: String
        switch kind {
        case .docx:
            let attributed = try await Task.detached(priority: .utility) {
                try DOCXCodec.read(from: source)
            }.value
            text = String(attributed.characters)
        case .txt, .markdown:
            text = try String(contentsOf: source, encoding: .utf8)
        default:
            text = "[Mock SDK] \(kind.displayName) → PDF export will use the real Artifex SDK once the license is enabled (Sprint 0.2)"
        }

        try await Task.detached(priority: .utility) {
            try Self.renderSinglePagePDF(text, to: destination)
            guard PDFDocument(url: destination) != nil else {
                throw DocumentExportingError.writeFailed
            }
        }.value
    }

    /// US Letter, single page — long documents get clipped rather than paginated.
    /// Fine for a Mock fallback; not meant to be the final-quality renderer.
    private static func renderSinglePagePDF(_ text: String, to destination: URL) throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let textRect = pageBounds.insetBy(dx: margin, dy: margin)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
        try data.write(to: destination)
    }
}

enum DocumentExportingError: Error, Sendable, LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            "Couldn't write the exported PDF"
        }
    }
}
