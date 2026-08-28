import Foundation
import UniformTypeIdentifiers

extension DocumentKind {
    /// Determine kind from UTI (not file extension — attacker or user may rename).
    /// See Phase0-Implementation-Logic.md §1.
    static func fromUTI(url: URL) -> DocumentKind? {
        // Try type from resourceValues first — most reliable.
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return fromType(type)
        }
        // Fallback: extension-based UTI.
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            return fromType(type)
        }
        return nil
    }

    private static func fromType(_ type: UTType) -> DocumentKind? {
        // Markdown first: some systems classify it as plainText, so this check
        // must run before the plainText fallback below.
        if let mdType = UTType(filenameExtension: "md"), type == mdType { return .markdown }
        if let mdType = UTType(filenameExtension: "markdown"), type == mdType { return .markdown }

        switch true {
        case type.conforms(to: .rtf):                                             return .rtf
        case type.conforms(to: .plainText):                                       return .txt
        case type.identifier == "org.openxmlformats.wordprocessingml.document":   return .docx
        case type.identifier == "org.openxmlformats.spreadsheetml.sheet":         return .xlsx
        case type.identifier == "org.openxmlformats.presentationml.presentation": return .pptx
        case type.identifier == "com.microsoft.word.doc":                         return .doc
        case type.identifier == "com.microsoft.excel.xls":                        return .xls
        case type.identifier == "com.microsoft.powerpoint.ppt":                   return .ppt
        case type.conforms(to: .pdf):                                             return .pdf
        default:                                                                  return nil
        }
    }
}
