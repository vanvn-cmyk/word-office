import SwiftUI

/// Tab-bar pill surface — Liquid Glass. Glass renders a consistent surface
/// across whatever content sits behind the pill (Library's list card vs
/// Settings's grouped form); `.regularMaterial` did not — that material
/// samples underlying content and visibly shifted tone between tabs.
/// Border + shadow intentionally omitted: glass already provides its own
/// edge highlight and depth, and stacking them produces a double-outline.
/// Applied after `.padding(6)` on the pill per the skill's modifier-order
/// rule (visual-effect modifiers go last).
///
/// No `#available` gate: `IPHONEOS_DEPLOYMENT_TARGET = 26.2` and this
/// target ships only for iphoneos/iphonesimulator, so every runtime device
/// satisfies iOS 26+. If deployment target is ever lowered, re-add a
/// `.regularMaterial + strokeBorder + shadow` fallback branch here.
fileprivate extension View {
    func tabBarPillStyle() -> some View {
        glassEffect(.regular, in: .capsule)
    }
}

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
    /// FAB "+" menu open state — lifted from `LibraryAddButton` so
    /// `libraryShell` can render a screen-wide invisible scrim that
    /// dismisses the menu on any outside tap, matching native `Menu`/
    /// `.popover` UX. Also lets `.onChange(of: selectedTab)` close the menu
    /// automatically when the user switches tab with menu open.
    @State private var isFABMenuOpen = false

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

                // Full-screen invisible scrim — captures outside taps while
                // the FAB menu is open so any tap outside the FAB or menu
                // dismisses it, matching native `Menu`/`.popover` UX. Sits
                // between the tab content ZStack (below it) and
                // `customTabBar` (above it) — the pill's tab buttons and the
                // FAB itself stay interactive above the scrim; a tap-driven
                // tab switch is handled separately via
                // `.onChange(of: selectedTab)` below.
                if isFABMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { closeFABMenu() }
                        .transition(.opacity)
                }

                customTabBar
            }
            // Switching tab with the FAB menu open would leave the menu
            // dangling over an unrelated tab. Close it as part of the same
            // interaction.
            .onChange(of: selectedTab) { closeFABMenu() }
        } else {
            checkingView
        }
    }

    /// Closes the FAB "+" menu with the same 0.15s ease-out as
    /// `LibraryAddButton.closeMenu()`, so scrim-driven and FAB-toggle-driven
    /// dismissals animate identically.
    private func closeFABMenu() {
        guard isFABMenuOpen else { return }
        withAnimation(.easeOut(duration: 0.15)) { isFABMenuOpen = false }
    }

    private var customTabBar: some View {
        // `.bottom` alignment — the tab pill (68pt: 56pt buttons + 12pt
        // capsule inner padding) is 12pt taller than the FAB (56pt).
        // Anchoring both to their bottoms keeps a shared baseline that
        // reads as a coherent floating bar.
        //
        // Historical note: this alignment also used to guard against the
        // FAB re-centering when the popup menu opened, back when the menu
        // was a VStack sibling of the FAB and expanded the enclosing view
        // upward. After the menu moved to `.overlay` on the FAB in
        // `LibraryAddButton`, `LibraryAddButton` no longer changes size
        // when the menu opens — the re-centering risk is gone. The
        // alignment stays purely for the visual baseline above.
        HStack(alignment: .bottom, spacing: DSSpacing.sm) {
            HStack(spacing: 2) {
                tabBarButton(.library, label: "Library", systemImage: "tray.full")
                tabBarButton(.tools, label: "Tools", systemImage: "wrench.and.screwdriver")
                tabBarButton(.settings, label: "Settings", systemImage: "gearshape")
            }
            .padding(6)
            .tabBarPillStyle()

            if let libraryVM {
                LibraryAddButton(viewModel: libraryVM, container: container, isMenuOpen: $isFABMenuOpen)
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
