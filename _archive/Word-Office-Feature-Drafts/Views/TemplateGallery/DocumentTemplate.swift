import SwiftUI

/// Model for the "Templates" gallery (see `TemplateGalleryView`). Mock data
/// lives in per-kind extension files — `TemplateCatalog+Word.swift`,
/// `TemplateCatalog+Excel.swift`, `TemplateCatalog+PowerPoint.swift` — not
/// in this file, so each kind's list can be read/edited on its own (rule.md
/// #5 OCP: a 4th kind's templates would be a new extension file, not a
/// change here).
///
/// All content is placeholder/mock — no real template files exist yet, so
/// `TemplateGalleryView` shows "Coming soon" when one is tapped (same
/// pattern `LibraryAddButton` already uses for unsupported blank kinds).
struct DocumentTemplate: Identifiable, Hashable {
    let id: String
    let kind: DocumentKind
    let title: String
    let accentColor: Color
    let thumbnail: ThumbnailStyle
    /// Word-only content shape (Excel/PowerPoint already get their own
    /// kind-specific layout regardless of this — see `TemplateThumbnailView`).
    /// Defaults to `.paragraph`, so only templates that need a different
    /// shape (Invoice, Meeting Notes) pass this explicitly.
    var contentShape: ContentShape = .paragraph

    /// A Word template's real-world genre, so its thumbnail resembles what
    /// it actually is instead of every `.docx` template sharing one
    /// generic "page of paragraph lines" look.
    enum ContentShape: Hashable {
        case paragraph
        /// "Bill to" header + a few label/amount line-item rows + a bolder
        /// total row — an invoice's actual structure.
        case invoiceLines
        /// Bulleted short lines instead of full-width paragraph capsules —
        /// notes/checklist content.
        case bulletList
    }

    /// Placeholder "page preview" look — drawn programmatically in
    /// `TemplateThumbnailView` (no image assets) so the draft has zero
    /// asset-catalog dependency until a real template renderer exists.
    ///
    /// `TemplateThumbnailView` picks the actual layout (paragraph page /
    /// spreadsheet grid / slide + outline) from `kind` — a Word template
    /// should look like a page, an Excel one a grid, a PowerPoint one a
    /// slide, so they read as their own format instead of all three kinds
    /// sharing one generic "page of gray lines" look. These two cases only
    /// control how much *emphasis* that kind-specific layout gets: `lines`
    /// draws an optional accent-colored heading/header (`hasAccentTitle`),
    /// `linesWithHighlight` adds one bigger featured block (an image
    /// placeholder on a page, a highlighted row on a grid, a fuller cover
    /// on a slide).
    enum ThumbnailStyle: Hashable {
        case lines(hasAccentTitle: Bool)
        case linesWithHighlight

        var hasAccentTitle: Bool {
            if case .lines(let hasAccentTitle) = self { return hasAccentTitle }
            return false
        }

        var isFeatured: Bool {
            if case .linesWithHighlight = self { return true }
            return false
        }
    }
}
