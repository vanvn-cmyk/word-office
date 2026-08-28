import Foundation

struct FolderBookmark: Hashable, Sendable, Codable {
    let bookmarkData: Data
    let displayPath: String
    let grantedAt: Date

    init(bookmarkData: Data, displayPath: String, grantedAt: Date = Date()) {
        self.bookmarkData = bookmarkData
        self.displayPath = displayPath
        self.grantedAt = grantedAt
    }
}
