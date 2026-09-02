import Foundation
import ZIPFoundation

/// Real (non-mock) DOCX text read/write via raw OOXML — lets `MockArtifexDocumentReader`/
/// `MockArtifexDocumentWriter` show and save actual `.docx` content while the Artifex license
/// is pending. Plain text only (no run-level bold/italic/underline) — the current editor
/// (`EditorPlaceholderView`) is a plain `TextEditor` with no formatting UI, so preserving
/// character-level formatting would be lost on every keystroke anyway.
///
/// `write` refuses (throws `.richContentUnsupported`) rather than silently overwriting
/// a document that already has images or tables — this writer has no way to preserve
/// either, and destroying them on save would be worse than declining to save at all.
///
/// Only ever called from the **Mock** SDK path (`MockArtifexDocumentReader`/`Writer`'s
/// `.docx` case) — when `ArtifexDocumentReader`/`Writer` land in `SDK/Real/` (Sprint 0.2,
/// once the Artifex license arrives), the real SDK's document session handles `.docx`
/// with full fidelity and never touches this type. This file can then either stay as a
/// Mock-only convenience (harmless — Real path never calls it) or be retired by reverting
/// Mock's `.docx` case to a placeholder like `.xlsx`/`.pptx`/`.pdf` already are.
enum DOCXCodec {
    static func read(from url: URL) throws -> AttributedString {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw DOCXCodecError.cannotOpenArchive
        }
        guard let entry = archive["word/document.xml"] else {
            throw DOCXCodecError.missingDocumentXML
        }

        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }

        let delegate = ParagraphTextExtractor()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DOCXCodecError.malformedXML(parser.parserError)
        }

        var text = delegate.paragraphs.joined(separator: "\n")
        // Mirror `write`'s rich-content check (§7.3 "never silent data loss") —
        // `write` refuses outright since it would destroy this content, but `read`
        // has no such alternative (the document must still open); surface a
        // visible warning inline instead of quietly showing text-only content
        // with no indication tables/images exist and aren't rendered.
        if containsRichContent(in: archive) {
            text = "[Content not shown] This document has images or tables that this preview doesn't render — only the plain text below.\n\n" + text
        }
        return AttributedString(text)
    }

    static func write(_ text: AttributedString, to url: URL) throws {
        // This writer only ever produces a minimal plain-text package (see header
        // comment). Silently overwriting a document that already has images/tables
        // would destroy them for good — refuse instead, per §7.3's "never silent
        // data loss" pattern used elsewhere in this codebase.
        if FileManager.default.fileExists(atPath: url.path),
           let existingArchive = try? Archive(url: url, accessMode: .read),
           containsRichContent(in: existingArchive) {
            throw DOCXCodecError.richContentUnsupported
        }

        let plain = String(text.characters)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = plain.isEmpty ? [""] : plain.components(separatedBy: "\n")
        let bodyXML = lines.map { paragraphXML(for: $0) }.joined()
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(bodyXML)<w:sectPr/></w:body></w:document>
        """

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        let tempZipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        guard let archive = try? Archive(url: tempZipURL, accessMode: .create) else {
            throw DOCXCodecError.archiveCreationFailed
        }
        try archive.addEntry(with: "[Content_Types].xml", relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "_rels/.rels", relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "word/document.xml", relativeTo: tempDir, compressionMethod: .deflate)
        defer { try? FileManager.default.removeItem(at: tempZipURL) }

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempZipURL)
        } else {
            try FileManager.default.moveItem(at: tempZipURL, to: url)
        }
    }

    // MARK: - XML building

    private static func paragraphXML(for line: String) -> String {
        guard !line.isEmpty else { return "<w:p/>" }
        return "<w:p><w:r><w:t xml:space=\"preserve\">\(xmlEscape(line))</w:t></w:r></w:p>"
    }

    private static func xmlEscape(_ text: String) -> String {
        let sanitized = String(String.UnicodeScalarView(text.unicodeScalars.filter { isValidXMLCharacter($0) }))
        return sanitized
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// XML 1.0 forbids most control characters — writing one verbatim (e.g. from
    /// pasted PDF/terminal content) produces a `document.xml` that fails to parse
    /// back on the very next `read(from:)`. Strip rather than escape: there's no
    /// valid numeric-character-reference form for these in XML 1.0.
    private static func isValidXMLCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x9, 0xA, 0xD: true
        case 0x20...0xD7FF: true
        case 0xE000...0xFFFD: true
        case 0x10000...0x10FFFF: true
        default: false
        }
    }

    /// Detects content this plain-text-only writer would silently destroy:
    /// embedded media (images) or table/drawing markup in `document.xml`.
    private static func containsRichContent(in archive: Archive) -> Bool {
        if archive.first(where: { $0.path.hasPrefix("word/media/") }) != nil {
            return true
        }
        guard let entry = archive["word/document.xml"] else { return false }
        var data = Data()
        _ = try? archive.extract(entry) { data.append($0) }
        guard let xml = String(data: data, encoding: .utf8) else { return false }
        return ["<w:tbl", "<w:drawing", "<w:pict", "<w:object"].contains { xml.contains($0) }
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    // MARK: - Minimal SAX parser: <w:p> paragraphs, joining <w:t> runs, no namespace processing
    // (avoids fighting XMLParser's namespace mode over a schema whose w:pPr/w:rPr wrapper
    // elements vary a lot between real-world documents).

    private final class ParagraphTextExtractor: NSObject, XMLParserDelegate {
        private(set) var paragraphs: [String] = []
        private var currentParagraph = ""
        private var isInText = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch localName(of: elementName) {
            case "p": currentParagraph = ""
            case "t": isInText = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard isInText else { return }
            currentParagraph += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch localName(of: elementName) {
            case "t": isInText = false
            case "p": paragraphs.append(currentParagraph)
            default: break
            }
        }

        private func localName(of elementName: String) -> String {
            guard let colonIndex = elementName.firstIndex(of: ":") else { return elementName }
            return String(elementName[elementName.index(after: colonIndex)...])
        }
    }
}

enum DOCXCodecError: LocalizedError {
    case cannotOpenArchive
    case missingDocumentXML
    case malformedXML(Error?)
    case archiveCreationFailed
    case richContentUnsupported

    var errorDescription: String? {
        switch self {
        case .cannotOpenArchive:
            "Couldn't open the file as a DOCX (ZIP) archive"
        case .missingDocumentXML:
            "This file has no word/document.xml — not a valid Word document"
        case .malformedXML(let underlying):
            "The document's XML is malformed" + (underlying.map { ": \($0.localizedDescription)" } ?? "")
        case .archiveCreationFailed:
            "Couldn't create the DOCX ZIP archive"
        case .richContentUnsupported:
            "This document has images or tables that can't be preserved yet — editing here would remove them"
        }
    }
}
