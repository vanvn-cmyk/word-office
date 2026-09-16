import SwiftUI

/// 3-stage status (2026-09-13, was 4 with `.sent` — dropped: "sent" only
/// applies to shared/emailed files, too narrow to be a universal document
/// stage, and this is now the PRIMARY grouping key for `LibraryView` — see
/// `LibraryViewModel+Grouping.groupedByStatus`, not just a filter).
/// `MetadataStoreImpl.fetchAll` decodes with `?? .draft` as a fallback, so an
/// old persisted row still carrying the removed "sent" rawValue degrades
/// safely to Draft instead of failing to decode.
enum DocumentStatus: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    /// Auto-assigned to seeded sample files only — signals "tutorial content,
    /// not a real working document yet". Never selectable by the user via the
    /// status picker; use `userSelectableCases` to build picker UIs.
    case getStarted
    case draft
    case reviewed
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .getStarted: "Get Started"
        case .draft:      "Draft"
        case .reviewed:   "Reviewed"
        case .done:       "Done"
        }
    }

    /// Circle-wrapped family so all statuses share one visual weight across
    /// chip / context menu / section header.
    var systemImage: String {
        switch self {
        case .getStarted: "flag.fill"
        case .draft:      "pencil.circle"
        case .reviewed:   "eye.circle"
        case .done:       "checkmark.seal"
        }
    }

    /// Single canonical color per status.
    var tintColor: Color {
        switch self {
        case .getStarted: Color.dsBrandPrimary
        case .draft:      Color.dsStatusWarning
        case .reviewed:   Color.dsBrandPrimary
        case .done:       Color.dsStatusSuccess
        }
    }

    /// Cycles forward through user-facing statuses. `.getStarted` advances
    /// to `.draft` so tapping "next" on a sample file promotes it naturally.
    var next: DocumentStatus {
        switch self {
        case .getStarted: .draft
        case .draft:      .reviewed
        case .reviewed:   .done
        case .done:       .draft
        }
    }

    /// Status values the user can choose manually (excludes `.getStarted`
    /// which is system-assigned to sample files only).
    static var userSelectableCases: [DocumentStatus] { [.draft, .reviewed, .done] }
}
