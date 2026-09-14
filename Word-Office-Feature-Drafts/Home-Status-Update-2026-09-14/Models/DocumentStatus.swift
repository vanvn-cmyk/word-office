import SwiftUI

/// 3-stage status (2026-09-13, was 4 with `.sent` — dropped: "sent" only
/// applies to shared/emailed files, too narrow to be a universal document
/// stage, and this is now the PRIMARY grouping key for `LibraryView` — see
/// `LibraryViewModel+Grouping.groupedByStatus`, not just a filter).
/// `MetadataStoreImpl.fetchAll` decodes with `?? .draft` as a fallback, so an
/// old persisted row still carrying the removed "sent" rawValue degrades
/// safely to Draft instead of failing to decode.
enum DocumentStatus: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case draft
    case reviewed
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft:    "Draft"
        case .reviewed: "Reviewed"
        case .done:     "Done"
        }
    }

    /// Circle-wrapped family so all statuses share one visual weight across
    /// chip / context menu / section header — `signature` (the literal
    /// scribble) stood out and broke the row rhythm. `checkmark.seal` reads
    /// as "completed" generically, not tied to e-signing specifically.
    var systemImage: String {
        switch self {
        case .draft:    "pencil.circle"
        case .reviewed: "eye.circle"
        case .done:     "checkmark.seal"
        }
    }

    /// Single canonical color per status — was duplicated slightly
    /// differently across `DocumentCard.StatusPill`, `DocumentGrid
    /// .StatusPillTag`, and `LibraryView.statusIconColor` (all mirrors of
    /// each other "kept in sync" by comment convention, not by the
    /// compiler) before 2026-09-14. Hoisted here once a 4th near-identical
    /// switch (`StatusSectionHeader` + the row accent bar) made the
    /// duplication a real drift risk rather than a one-off. Every
    /// consumer should read this instead of re-deriving its own palette.
    var tintColor: Color {
        switch self {
        case .draft:    Color.dsStatusWarning
        // Was `dsTextSecondary` (neutral gray) — matched the original
        // `StatusPill` scheme, but reads as "inactive/no color" rather
        // than a real category, and the Draft→Reviewed segment of
        // `libraryList`'s connector gradient blended orange + gray into
        // a muddy brown (user-flagged: "gì thế này"). Brand blue gives a
        // clean, vivid 3-color set (orange/blue/green) with no gradient
        // segment landing on a dull color.
        case .reviewed: Color.dsBrandPrimary
        case .done:     Color.dsStatusSuccess
        }
    }
}
