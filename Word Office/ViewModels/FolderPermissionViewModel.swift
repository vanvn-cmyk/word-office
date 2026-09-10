import Foundation
import Observation

/// Owns the permission-grant / revoke / reset flow for the granted library folder.
/// Never triggers `LibraryViewModel.loadLibrary()` directly — RootView observes
/// `LibraryStore.folderPermissionState` and reacts, keeping this VM decoupled.
///
/// See Library-Architecture.md §4 scenario 1 (first grant) + scenario 2 (revoked).
@Observable
@MainActor
final class FolderPermissionViewModel {
    var errorMessage: String?
    private(set) var isRequesting: Bool = false

    private let store: LibraryStore
    private let picker: any FolderPermissionGranting
    private let bookmarkStore: any FolderBookmarkResolving

    init(store: LibraryStore,
         picker: any FolderPermissionGranting,
         bookmarkStore: any FolderBookmarkResolving) {
        self.store = store
        self.picker = picker
        self.bookmarkStore = bookmarkStore
    }

    /// Called from RootView.task on first appear — moves store out of `.checking`.
    /// A saved bookmark that fails to resolve is `.revoked` (surfaces CTA),
    /// never silent empty (Library-Architecture.md §7 trap #4).
    ///
    /// Session 19 — added "auto-grant to app's Documents/" fallback. When
    /// no user bookmark is saved BUT the first-launch sample-file seeder
    /// has already run (`SampleFileSeeder.didSeedDefaultsKey == true`),
    /// treat the app's own `Documents/` folder as the granted library
    /// source. Skips the folder-permission onboarding entirely on first
    /// launch; the user opens the app and finds Word Office
    /// pre-populated with three tour files instead of a "Choose Folder"
    /// gate. `LibraryViewModel.loadLibrary` picks up the same
    /// no-bookmark + granted state and scans `documentsURL` directly.
    func checkExistingPermission() async {
        if let saved = bookmarkStore.loadSaved() {
            do {
                _ = try bookmarkStore.resolve(saved)
                store.folderPermissionState = .granted
            } catch {
                store.folderPermissionState = .revoked
            }
            return
        }

        if UserDefaults.standard.bool(forKey: SampleFileSeeder.didSeedDefaultsKey) {
            store.folderPermissionState = .granted
            return
        }

        store.folderPermissionState = .notGranted
    }

    /// User taps "Choose folder" (onboarding) or "Re-grant access" (reauth CTA).
    /// Cancels are non-errors — state stays as-is so the same CTA is still available.
    func requestPermission() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        do {
            guard let bookmark = try await picker.requestFolderAccess() else { return }
            try bookmarkStore.save(bookmark)
            store.folderPermissionState = .granted
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// User taps "Skip for now" on the permission onboarding screen — lets them
    /// reach the Library shell without granting yet (Library shows its own CTA).
    func skipOnboarding() {
        store.didSkipFolderOnboarding = true
    }

    /// User picks "Change folder" in settings. Clears Keychain + library entries.
    func resetPermission() async {
        do {
            try bookmarkStore.delete()
            store.folderPermissionState = .notGranted
            store.didSkipFolderOnboarding = false
            store.clear()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
