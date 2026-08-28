import Foundation

enum DocumentSortOrder: String, CaseIterable, Sendable {
    case nameAscending
    case nameDescending
    case modifiedAscending
    case modifiedDescending

    var displayName: String {
        switch self {
        case .nameAscending:      "Name (A–Z)"
        case .nameDescending:     "Name (Z–A)"
        case .modifiedAscending:  "Oldest first"
        case .modifiedDescending: "Recent first"
        }
    }
}
