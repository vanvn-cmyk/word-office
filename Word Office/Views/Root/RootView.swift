import SwiftUI

/// Root switch based on `LibraryStore.folderPermissionState` — core loop MVP §10 v2.
///
/// State handling:
/// - `.checking`  → spinner (200-500ms window while Keychain resolves).
/// - `.notGranted` → `FolderPermissionOnboarding`.
/// - `.granted`   → `LibraryView`.
/// - `.revoked`   → `ReauthorizePermissionCTA` (trap #4: never silently empty).
///
/// Legacy adaptive TabView / NavigationSplitView code lived here through Sprint 0.1
/// and will return in Sprint 0.3 alongside the Tools tab; keep out of `LibraryView`
/// core loop for now.
struct RootView: View {
    let container: DependencyContainer

    @Environment(LibraryStore.self) private var libraryStore
    @State private var libraryVM: LibraryViewModel?
    @State private var permissionVM: FolderPermissionViewModel?

    var body: some View {
        Group {
            switch libraryStore.folderPermissionState {
            case .checking:
                checkingView

            case .notGranted:
                if let permissionVM {
                    FolderPermissionOnboarding(viewModel: permissionVM)
                } else {
                    checkingView
                }

            case .granted:
                if let libraryVM, let permissionVM {
                    LibraryView(viewModel: libraryVM) {
                        await permissionVM.resetPermission()
                    }
                } else {
                    checkingView
                }

            case .revoked:
                if let permissionVM {
                    ReauthorizePermissionCTA(viewModel: permissionVM)
                } else {
                    checkingView
                }
            }
        }
        .task {
            initializeViewModelsIfNeeded()
            await permissionVM?.checkExistingPermission()
        }
    }

    // MARK: - Loading state

    private var checkingView: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.dsBrandPrimary)
            Text("Restoring permission…")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundPrimary)
    }

    // MARK: - Lazy VM init
    //
    // VMs are created once, on first appear, so `LibraryStore` (from environment)
    // is bound before construction — cannot happen in the parent's init.

    @MainActor
    private func initializeViewModelsIfNeeded() {
        if permissionVM == nil {
            permissionVM = container.makeFolderPermissionViewModel(store: libraryStore)
        }
        if libraryVM == nil {
            libraryVM = container.makeLibraryViewModel(store: libraryStore)
        }
    }
}

#Preview("Root — checking") {
    let store = LibraryStore()
    return RootView(container: DependencyContainer())
        .environment(store)
        .environment(AppState())
        .environment(ThemeStore())
        .environment(SessionStore())
}
