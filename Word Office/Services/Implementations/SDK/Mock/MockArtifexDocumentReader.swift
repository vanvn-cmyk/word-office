import Foundation
import UIKit  // NSAttributedString.DocumentType.rtf requires UIKit under Swift 6 MemberImportVisibility

/// Mock reader. Sprint 0.1: RTF/TXT/Markdown read qua NSAttributedString/String
/// (real, so end-to-end can be tested). DOCX/XLSX/PPTX/PDF return placeholder text so the View
/// shows an "SDK not licensed" placeholder. Real reader swap in Sprint 0.2.
final class MockArtifexDocumentReader: DocumentReading {
    let kind: DocumentKind

    init(kind: DocumentKind) {
        self.kind = kind
    }

    func read(from url: URL) async throws -> DocumentContent {
        switch kind {
        case .txt, .markdown:
            let raw = try String(contentsOf: url, encoding: .utf8)
            return DocumentContent(attributedText: AttributedString(raw), kind: kind)

        case .rtf:
            let data = try Data(contentsOf: url)
            let ns = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return DocumentContent(attributedText: AttributedString(ns), kind: kind)

        case .docx, .xlsx, .pptx, .pdf, .doc, .xls, .ppt, .hwp, .hwpx:
            let placeholder = AttributedString(
                "[Mock SDK] \(kind.displayName) preview will load when Artifex license is enabled (Sprint 0.2)."
            )
            return DocumentContent(attributedText: placeholder, kind: kind)
        }
    }
}
