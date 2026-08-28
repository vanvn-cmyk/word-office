import Foundation

/// Time-window buckets for grouping library entries by `modifiedAt` (UC16 first-scan familiarity).
/// The order in `CaseIterable` matches the reading order on `LibraryView` — do not reorder.
enum DateBucket: CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var displayName: String {
        switch self {
        case .today:     "Today"
        case .yesterday: "Yesterday"
        case .thisWeek:  "Previous 7 Days"
        case .thisMonth: "Previous 30 Days"
        case .older:     "Older"
        }
    }

    /// Classify a date relative to `now`. `.thisWeek` covers 2–7 days ago;
    /// `.thisMonth` covers 8–30 days ago. Older dates fall into `.older`.
    static func bucket(for date: Date,
                       now: Date = .now,
                       calendar: Calendar = .autoupdatingCurrent) -> DateBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysDiff <= 7 { return .thisWeek }
        if daysDiff <= 30 { return .thisMonth }
        return .older
    }
}
