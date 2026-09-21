// Session 12 (2026-09-04) — cross-tab signal: a tool wrote a file
// into the app's Documents/ (Merge/Split/Convert/Scan/Sign/Fill Form),
// LibraryVM should reload so the new file appears without the user
// having to pull-to-refresh Library manually.
//
// NotificationCenter (rather than a shared observable or direct
// LibraryVM injection into every tool VM) — the tools tab is
// architecturally independent of Library, and threading a LibraryVM
// reference through every tool VM constructor would couple layers that
// currently don't know about each other. A named notification keeps
// the direction correct: tools broadcast a fact, Library listens.

import Foundation

extension Notification.Name {
    /// Posted (on the main queue) after a tool successfully writes a
    /// new file into the app's Documents/ directory. LibraryVM re-scans
    /// on receipt — the scanner is the source of truth for metadata +
    /// iCloud state.
    ///
    /// Optional `userInfo` key: `documentsDidChangeSuggestedStatuses`
    /// — `[String: String]` mapping `url.absoluteString → DocumentStatus.rawValue`.
    /// For brand-new files (no existing metadata), LibraryVM uses this
    /// to assign a meaningful initial status instead of always defaulting
    /// to `.draft`. Example: Sign → `.done`, Merge → `.draft`.
    static let documentsDidChange = Notification.Name("com.wordoffice.documentsDidChange")

    /// `userInfo` key for `documentsDidChange` — value is `[String: String]`.
    static let documentsDidChangeSuggestedStatuses = "documentsDidChangeSuggestedStatuses"
}

extension NotificationCenter {
    /// Posts `.documentsDidChange` with an optional per-URL status hint.
    /// Call from the main queue (all tool VMs are `@MainActor`).
    func postDocumentsDidChange(_ statuses: [URL: DocumentStatus] = [:]) {
        var userInfo: [AnyHashable: Any]? = nil
        if !statuses.isEmpty {
            userInfo = [
                Notification.Name.documentsDidChangeSuggestedStatuses:
                    Dictionary(uniqueKeysWithValues: statuses.map { ($0.key.absoluteString, $0.value.rawValue) })
            ]
        }
        post(name: .documentsDidChange, object: nil, userInfo: userInfo)
    }
}
