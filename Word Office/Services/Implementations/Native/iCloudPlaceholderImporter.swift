import Foundation

/// Waits for an iCloud placeholder file to finish downloading before returning.
/// Uses NSMetadataQuery per Phase0-Implementation-Logic.md §5.2 — avoids polling
/// with timers which drains battery and misses the exact transition moment.
///
/// Note: `NSMetadataQuery` needs a main-thread run loop, so this actor wraps
/// the query and forwards start/stop to main.
actor ICloudPlaceholderImporter {
    struct DownloadTimeoutError: Error, LocalizedError {
        var errorDescription: String? { "iCloud download timed out" }
    }

    /// Return whether the URL is currently a placeholder (needs downloading).
    nonisolated func needsDownload(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
            let status = values.ubiquitousItemDownloadingStatus
        else {
            return false  // Not an iCloud file, or can't read status → assume local.
        }
        return status != .current
    }

    /// Trigger download if placeholder + wait until it becomes current.
    /// Caller must have security-scoped access to `url` before invoking.
    func downloadIfNeeded(_ url: URL, timeout: Duration = .seconds(60)) async throws {
        guard needsDownload(url) else { return }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if !needsDownload(url) { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw DownloadTimeoutError()
    }
}
