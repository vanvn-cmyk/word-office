import Foundation

/// Dispatch-only — the actual mock lists live one file per kind:
/// `TemplateCatalog+Word.swift`, `TemplateCatalog+Excel.swift`,
/// `TemplateCatalog+PowerPoint.swift`. Keeping this switch here (rather
/// than in `DocumentTemplate.swift`) means adding a real per-kind catalog
/// later never touches this file's own list of cases — `DocumentKind`
/// itself is the fixed, closed set this switches on.
enum TemplateCatalog {
    static func templates(for kind: DocumentKind) -> [DocumentTemplate] {
        switch kind {
        case .docx: return wordTemplates
        case .xlsx: return excelTemplates
        case .pptx: return powerPointTemplates
        default:    return []
        }
    }
}
