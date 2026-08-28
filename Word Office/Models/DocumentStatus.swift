import Foundation

enum DocumentStatus: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case draft
    case reviewed
    case signed
    case sent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft:    "Draft"
        case .reviewed: "Reviewed"
        case .signed:   "Signed"
        case .sent:     "Sent"
        }
    }

    var systemImage: String {
        switch self {
        case .draft:    "pencil.circle"
        case .reviewed: "eye.circle"
        case .signed:   "signature"
        case .sent:     "paperplane.circle"
        }
    }
}
