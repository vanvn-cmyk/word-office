import Foundation

/// Groups `DocumentKind` into the type tabs shown on `LibraryView`.
/// `.all` matches every kind, including formats with no dedicated tab
/// (`.txt`, `.rtf`, `.markdown`, `.hwp`, `.hwpx`).
enum DocumentTypeFilter: CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case word
    case excel
    case powerPoint
    case pdf

    var id: Self { self }

    var displayName: String {
        switch self {
        case .all:        "All"
        case .word:       "Word"
        case .excel:      "Excel"
        case .powerPoint: "PowerPoint"
        case .pdf:        "PDF"
        }
    }

    /// `nil` means "match every kind" (`.all`).
    var kinds: Set<DocumentKind>? {
        switch self {
        case .all:        nil
        case .word:       [.docx, .doc]
        case .excel:      [.xlsx, .xls]
        case .powerPoint: [.pptx, .ppt]
        case .pdf:        [.pdf]
        }
    }

    func matches(_ kind: DocumentKind) -> Bool {
        kinds?.contains(kind) ?? true
    }
}
