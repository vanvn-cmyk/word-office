import Foundation

extension URL {
    static var documentsDirectory: URL {
        // Fallback for iOS < 16 removed since deployment target is iOS 17+.
        // URL.documentsDirectory is available iOS 16+, we can use it directly.
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
