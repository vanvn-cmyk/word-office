import Foundation
import Observation

/// Shared state for the Library core loop (§10 v2). Owned at app scope,
/// injected via `.environment(_:)` — a re-render on `entries` change touches
/// only views that observe this store (not `SessionStore`/`ThemeStore`).
///
/// Writes come from `LibraryViewModel` / `FolderPermissionViewModel`;
/// views read only.
@Observable
@MainActor
final class LibraryStore {
    var entries: [LibraryEntry] = []
    var folderPermissionState: FolderPermissionState = .checking
    /// True once the user has completed a real folder-picker grant
    /// (`FolderPermissionViewModel.requestPermission()` → a bookmark
    /// saved). False while the library is still just the Session 19
    /// auto-seeded sample files in the app's own sandbox `Documents/`
    /// — i.e. no bookmark saved yet, `.granted` only via the
    /// `SampleFileSeeder` fallback. Set by `LibraryViewModel.loadLibrary()`
    /// (the one place that already computes this to decide which
    /// folder to scan) — drives `LibraryView`'s "these are sample
    /// files" banner.
    var hasExternalFolder: Bool = false

    /// Set when the user taps "Skip for now" on the permission onboarding screen.
    /// In-memory only (never persisted) — a fresh cold launch re-shows onboarding
    /// as long as no folder is granted, keeping the core-loop conversion chance alive.
    var didSkipFolderOnboarding: Bool = false

    /// Drives the badge count on `LibraryView`. Derived — never write directly.
    /// See Library-Architecture.md §4 scenario 4 (status change → draftCount decreases automatically).
    var draftCount: Int {
        entries.reduce(0) { $0 + ($1.metadata.status == .draft ? 1 : 0) }
    }

    // MARK: - Mutations (called from ViewModels only)

    func replaceAll(_ new: [LibraryEntry]) {
        entries = new
    }

    /// Insert if the id is new, otherwise update in place — preserves list order.
    func upsert(_ entry: LibraryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        entries = []
    }
}

/// Runtime state for the granted folder. `.checking` covers the async gap
/// between app launch and the first Keychain resolve — RootView shows a spinner
/// during this window instead of flashing the onboarding screen.
enum FolderPermissionState: Equatable, Sendable {
    case checking
    case notGranted
    case granted
    case revoked
}
