import Foundation

enum DocumentKind: String, Codable, Hashable, Sendable, CaseIterable {
    case txt
    case rtf
    case markdown
    case docx
    case xlsx
    case pptx
    case pdf
    // Legacy formats — Phase 4 (optional)
    case doc
    case xls
    case ppt
    // Korean format — check UTI support Sprint 0.1
    case hwp
    case hwpx
    // Archive — added S18 for "Convert to ZIP" kebab action so scanner
    // doesn't drop the produced .zip; not editable, kind is used purely
    // for icon + display in the Library list.
    case zip

    var displayName: String { rawValue.uppercased() }

    var systemImage: String {
        switch self {
        case .txt, .markdown:      "doc.text"
        case .rtf:                 "doc.richtext"
        case .docx, .doc:          "doc.text.fill"
        case .xlsx, .xls:          "tablecells.fill"
        case .pptx, .ppt:          "rectangle.on.rectangle.fill"
        case .pdf:                 "doc.fill"
        case .hwp, .hwpx:          "doc.text"
        case .zip:                 "doc.zipper"
        }
    }

    var isOfficeFormat: Bool {
        switch self {
        case .docx, .xlsx, .pptx, .doc, .xls, .ppt, .hwp, .hwpx: true
        default: false
        }
    }

    /// Formats the offline ONLYOFFICE editor (x2t.wasm) can actually open.
    /// HWP/HWPX are office formats but x2t does not support them.
    var isOnlyOfficeEditable: Bool {
        switch self {
        case .docx, .xlsx, .pptx, .doc, .xls, .ppt: return true
        default: return false
        }
    }
}
