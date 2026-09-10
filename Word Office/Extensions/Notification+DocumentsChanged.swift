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
    /// new file into the app's Documents/ directory. Payload is empty
    /// — LibraryVM re-scans on receipt rather than trying to insert
    /// the single new URL, since the scanner is the source of truth
    /// for metadata + iCloud state.
    static let documentsDidChange = Notification.Name("com.wordoffice.documentsDidChange")
}
