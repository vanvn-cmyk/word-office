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

    /// Circle-wrapped family so the four statuses share one visual weight
    /// across chip / context menu / filter popover — `signature` (the
    /// literal scribble) stood out and broke the row rhythm. `checkmark.seal`
    /// reads as "signed & completed", closest circle-shaped SF Symbol.
    var systemImage: String {
        switch self {
        case .draft:    "pencil.circle"
        case .reviewed: "eye.circle"
        case .signed:   "checkmark.seal"
        case .sent:     "paperplane.circle"
        }
    }
}
