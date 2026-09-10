import Foundation
import UIKit  // NSAttributedString RTF data(from:documentAttributes:) requires UIKit under Swift 6 MemberImportVisibility

/// Mock writer. Sprint 0.1: real RTF/TXT/Markdown writes so autosave round-trip can be tested.
/// DOCX now writes a real minimal OOXML package via `DOCXCodec` (plain text only — see that
/// file's header comment). XLSX/PPTX/PDF still no-op. Real writer swap in Sprint 0.2.
final class MockArtifexDocumentWriter: DocumentWriting {
    let kind: DocumentKind

    init(kind: DocumentKind) {
        self.kind = kind
    }

    func write(_ content: DocumentContent, to url: URL) async throws {
        switch kind {
        case .txt, .markdown:
            let plain = String(content.attributedText.characters)
            try plain.write(to: url, atomically: true, encoding: .utf8)

        case .rtf:
            let ns = NSAttributedString(content.attributedText)
            let data = try ns.data(
                from: NSRange(location: 0, length: ns.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try data.write(to: url, options: .atomic)

        case .docx:
            // Same reasoning as MockArtifexDocumentReader's .docx case — must run
            // off the caller's actor (autosave calls this from MainActor).
            let text = content.attributedText
            try await Task.detached(priority: .utility) {
                try DOCXCodec.write(text, to: url)
            }.value

        case .xlsx, .pptx, .pdf, .doc, .xls, .ppt, .hwp, .hwpx, .zip:
            // Mock: no-op. Real writer via Artifex SDK arrives Sprint 0.2.
            break
        }
    }
}
