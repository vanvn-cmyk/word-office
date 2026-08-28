import Foundation

/// Adaptive hero copy for `LibraryView` (UC16). Four discrete states so `LibraryView`
/// stays declarative — no branching on raw counts in the view.
///
/// State selection lives in `LibraryViewModel.heroCopy` (see `LibraryViewModel+Grouping`).
enum LibraryHeroCopy: Equatable, Sendable {
    /// No entries at all — folder is empty or hasn't been scanned yet.
    case empty
    /// draftCount == total — first-run, or the user hasn't changed any file's status. Welcoming.
    case welcoming(total: Int)
    /// 0 < draftCount < total — some drafts are unfinished. Zeigarnik signal.
    case zeigarnik(draft: Int, total: Int)
    /// draftCount == 0 — everything has moved off .draft. Celebration.
    case celebration(total: Int)

    /// Number shown large in the hero card. 0 for the empty state.
    var count: Int {
        switch self {
        case .empty:                 0
        case .welcoming(let n):      n
        case .zeigarnik(let d, _):   d
        case .celebration(let n):    n
        }
    }

    var title: String {
        switch self {
        case .empty:       "No documents yet"
        case .welcoming:   "Documents tracked"
        case .zeigarnik:   "Drafts in progress"
        case .celebration: "All caught up"
        }
    }

    var subtitle: String {
        switch self {
        case .empty:
            return "Folder is empty or hasn't been scanned"
        case .welcoming:
            return "Freshly scanned — everything starts as a draft"
        case .zeigarnik(_, let total):
            return "Out of \(total) tracked"
        case .celebration:
            return "Nothing left in drafts"
        }
    }
}
