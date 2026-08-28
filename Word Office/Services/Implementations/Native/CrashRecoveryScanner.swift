import Foundation

/// Scans app sandbox `Documents/` for `<original>.autosave.tmp` orphans.
/// See `CrashRecoveryScanning` for the recovery flow rationale.
///
/// Naming convention (matches `AutosaveScheduler` staging-file writes):
///   `report.txt`  →  `report.txt.autosave.tmp`
/// A crash between "write to staging" and "atomic rename" leaves the `.tmp`
/// behind — this scanner surfaces those on next launch.
final class CrashRecoveryScanner: CrashRecoveryScanning {
    static let orphanSuffix = ".autosave.tmp"

    private let documentsURL: URL
    private let fileManager = FileManager.default

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
    }

    func scanForOrphans() async -> [CrashRecoveryOrphan] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items.compactMap { url -> CrashRecoveryOrphan? in
            let name = url.lastPathComponent
            guard name.hasSuffix(Self.orphanSuffix) else { return nil }
            guard
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .isRegularFileKey
                ]),
                values.isRegularFile == true
            else {
                return nil
            }

            let originalName = String(name.dropLast(Self.orphanSuffix.count))
            let originalURL = documentsURL.appendingPathComponent(originalName)

            return CrashRecoveryOrphan(
                originalURL: originalURL,
                autosaveURL: url,
                name: originalName,
                modifiedAt: values.contentModificationDate ?? Date()
            )
        }
    }

    func discardOrphan(_ orphan: CrashRecoveryOrphan) async throws {
        do {
            try fileManager.removeItem(at: orphan.autosaveURL)
        } catch {
            throw CrashRecoveryError.discardFailed(underlying: error.localizedDescription)
        }
    }
}
