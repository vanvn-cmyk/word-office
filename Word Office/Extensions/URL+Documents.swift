import Foundation

extension URL {
    static var documentsDirectory: URL {
        // Fallback for iOS < 16 removed since deployment target is iOS 17+.
        // URL.documentsDirectory is available iOS 16+, we can use it directly.
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// POSIX content modification date via `URLResourceValues`. Falls back
    /// to `.now` when the attribute can't be read (broken bookmark, revoked
    /// permission, file just deleted) — same `Date` shape `DSFileRow`'s
    /// relative-time formatter expects, so a read failure renders as "just
    /// now" instead of exploding on the missing attribute. Meant for rows
    /// that represent a file the USER picked (Convert / Merge / Split
    /// pickers): hardcoding `.now` there displays as "2 secs" and counts
    /// up in real time because the relative-time formatter compares against
    /// `Date()`, which is misleading — that row is not a live counter.
    /// Rows that represent a file the APP just wrote (Success screens) can
    /// keep `.now` since it's truthful there.
    var contentModificationDateOrNow: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
    }
}
