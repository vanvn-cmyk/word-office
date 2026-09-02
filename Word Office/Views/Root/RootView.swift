import SwiftUI

/// Root switch based on `LibraryStore.folderPermissionState` — core loop MVP §10 v2.
///
/// State handling:
/// - `.checking`  → spinner (200-500ms window while Keychain resolves).
/// - `.notGranted` → `FolderPermissionOnboarding`, or `libraryShell` if the user
///   already tapped "Skip for now" (`LibraryStore.didSkipFolderOnboarding`).
/// - `.granted`   → 3-tab shell (Library/Tools/Settings) — `libraryShell`.
/// - `.revoked`   → `ReauthorizePermissionCTA` (trap #4: never silently empty).
struct RootView: View {
    let container: DependencyContainer

    @Environment(LibraryStore.self) private var libraryStore
    @State private var libraryVM: LibraryViewModel?
    @State private var permissionVM: FolderPermissionViewModel?
    @State private var selectedTab: RootTab = .library

    var body: some View {
        Group {
            switch libraryStore.folderPermissionState {
            case .checking:
                checkingView

            case .notGranted:
                if libraryStore.didSkipFolderOnboarding {
                    libraryShell
                } else if let permissionVM {
                    FolderPermissionOnboarding(viewModel: permissionVM) {
                        permissionVM.skipOnboarding()
                    }
                } else {
                    checkingView
                }

            case .granted:
                libraryShell

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

    // MARK: - Library shell

    /// Shown for `.granted`, and for `.notGranted` after "Skip for now" — Library
    /// itself renders the no-folder-yet empty state with its own CTA in that case.
    ///
    /// Custom bottom bar instead of `TabView`/`Tab` — two native mechanisms for
    /// putting the FAB on the same row as the tab bar were tried and both broke
    /// real rendering (see `LibraryAddButton`'s history before this rewrite: a
    /// `.overlay` on the outer `TabView` produced a corner-clipping artifact on
    /// the bar itself, and `.tabViewBottomAccessory` wraps content in its own
    /// fixed-size pill and clips the FAB's popup menu). Drawing the tab bar
    /// ourselves means there's no system layer left to fight — the pill and the
    /// FAB are just two sibling views in one `HStack`, guaranteed to share a row.
    @ViewBuilder
    private var libraryShell: some View {
        if let libraryVM, let permissionVM {
            ZStack(alignment: .bottom) {
                // All 3 kept mounted simultaneously (not a `switch` that only
                // instantiates the selected one) — matches real `TabView` semantics,
                // where an unselected tab keeps its `NavigationStack` depth, scroll
                // position, and in-progress form state instead of losing it every
                // time the user switches away and back.
                ZStack {
                    LibraryView(viewModel: libraryVM) {
                        await permissionVM.requestPermission()
                    }
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                    .accessibilityHidden(selectedTab != .library)

                    ToolsTabView(container: container)
                        .opacity(selectedTab == .tools ? 1 : 0)
                        .allowsHitTesting(selectedTab == .tools)
                        .accessibilityHidden(selectedTab != .tools)

                    SettingsView {
                        await permissionVM.resetPermission()
                    }
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                    .accessibilityHidden(selectedTab != .settings)
                }
                .safeAreaInset(edge: .bottom) {
                    // Reserves the space the floating bar occupies so List/ScrollView
                    // content isn't hidden behind it — a real safe-area inset, not
                    // just visual padding, so `.refreshable`/scroll insets stay correct.
                    // Kept in sync with `customTabBar`'s actual height by hand (56pt
                    // buttons + 12pt capsule padding + 8pt bottom padding, some slack).
                    Color.clear.frame(height: 84)
                }

                customTabBar
            }
        } else {
            checkingView
        }
    }

    private var customTabBar: some View {
        // `.bottom` alignment — `LibraryAddButton` grows upward when its menu
        // opens (its popup sits above the "+" in its own VStack), which would
        // otherwise vertically re-center against the shorter tab pill and
        // visibly shift the "+" up/down as the menu opens/closes.
        HStack(alignment: .bottom, spacing: DSSpacing.sm) {
            HStack(spacing: 2) {
                tabBarButton(.library, label: "Library", systemImage: "tray.full")
                tabBarButton(.tools, label: "Tools", systemImage: "wrench.and.screwdriver")
                tabBarButton(.settings, label: "Settings", systemImage: "gearshape")
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.dsBorderSubtle))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)

            if let libraryVM {
                LibraryAddButton(viewModel: libraryVM, container: container)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
    }

    private func tabBarButton(_ tab: RootTab, label: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 72, height: 56)
            .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextTertiary)
            .background(isSelected ? Color.dsBrandPrimarySubtle : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

private enum RootTab: Hashable {
    case library
    case tools
    case settings
}

#Preview("Root — checking") {
    let store = LibraryStore()
    return RootView(container: DependencyContainer())
        .environment(store)
        .environment(AppState())
        .environment(ThemeStore())
        .environment(SessionStore())
}
