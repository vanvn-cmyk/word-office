import Foundation

extension FileManager {
    /// Auto-suffix "(2)", "(3)"... on collision — shared by every call site that
    /// writes a new file into a shared directory and must not silently overwrite
    /// an existing one. See Phase0-Implementation-Logic-v2.md §4.4.
    func nonConflictingURL(for fileName: String, in directory: URL) -> URL {
        let base = directory.appendingPathComponent(fileName)
        guard fileExists(atPath: base.path) else { return base }

        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension(ext)
            if !fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
