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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var libraryVM: LibraryViewModel?
    @State private var permissionVM: FolderPermissionViewModel?
    @State private var onboardingVM: OnboardingViewModel?
    /// First-run gate. Persists after the user completes S1→S4 (grant OR
    /// "Maybe Later"). Reset from Settings → "Reset Onboarding" if we ever
    /// expose that. Key intentionally namespaced under `root.` so future
    /// per-feature flags stay grouped.
    @AppStorage("root.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedTab: RootTab = .library
    /// FAB "+" menu open state — lifted from `LibraryAddButton` so
    /// `libraryShell` can render a screen-wide invisible scrim that
    /// dismisses the menu on any outside tap, matching native `Menu`/
    /// `.popover` UX. Also lets `.onChange(of: selectedTab)` close the menu
    /// automatically when the user switches tab with menu open.
    @State private var isFABMenuOpen = false
    /// Editor sheet target — driven by `LibraryView`'s kebab-menu "Edit"
    /// callback. Lives at this level (not inside `LibraryView`) because
    /// `EditorPlaceholderView(container:ref:)` needs the app-scope
    /// `container` and `LibraryView` doesn't take a container param.
    @State private var editingRef: DocumentRef?
    /// Visual hide state — pill isn't rendered when true. Set by
    /// either scroll auto-hide (`hidesTabBarVisually`) or by pushed
    /// destinations (`hidesTabBar`). The parent `safeAreaInset` is a
    /// CONSTANT 150pt regardless — destinations that want to reclaim
    /// that strip use `.ignoresSafeArea(.container, edges: .bottom)`
    /// (baked into `hidesTabBar()`). Fixes Code Review finding #1:
    /// the previous dual-preference design left `insetCollapsed`
    /// stuck true after popping from a destination.
    @State private var isTabBarVisualHidden = false

    var body: some View {
        Group {
            // First-run onboarding gate. Wraps S1→S4; S4 delegates to
            // `permissionVM` for the folder grant. Once completed (grant or
            // "Maybe Later"), `hasCompletedOnboarding` flips true and the
            // permission-state switch below owns routing from here on.
            // Session 19 — bundle-seeded first launch skips onboarding
            // entirely. `SampleFileSeeder` (fires from
            // `DependencyContainer.init`) flips `didSeedDefaultsKey`
            // to true before the view hierarchy first renders, so
            // this branch reads the flag on the first appearance and
            // marks onboarding done in the same tick. Users open the
            // app for the first time and land straight in Library
            // with the three tour files already visible — no folder-
            // permission gate.
            if !hasCompletedOnboarding {
                if UserDefaults.standard.bool(forKey: SampleFileSeeder.didSeedDefaultsKey) {
                    checkingView
                        .onAppear { hasCompletedOnboarding = true }
                } else if let onboardingVM, let permissionVM {
                    OnboardingContainerView(
                        viewModel: onboardingVM,
                        permissionVM: permissionVM
                    )
                } else {
                    checkingView
                }
            } else {
                switch libraryStore.folderPermissionState {
                case .checking:
                    checkingView

                // `.revoked` currently falls through to the same handler as
                // `.notGranted` — the dedicated "Folder access lost" screen
                // (`ReauthorizePermissionCTA`) is TEMPORARILY hidden per user
                // request. Re-enable by restoring the split branch below.
                case .notGranted, .revoked:
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

                // TEMPORARILY DISABLED — see the merged `.notGranted, .revoked`
                // branch above.
                //
                // case .revoked:
                //     if let permissionVM {
                //         ReauthorizePermissionCTA(viewModel: permissionVM)
                //     } else {
                //         checkingView
                //     }
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
                    LibraryView(
                        viewModel: libraryVM,
                        onRequestPermission: { await permissionVM.requestPermission() },
                        onOpenEditor: { editingRef = $0 }
                    )
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                    .accessibilityHidden(selectedTab != .library)
                    .suppressTabBarHiddenPreference(unless: selectedTab == .library)

                    ToolsTabView(container: container)
                        .opacity(selectedTab == .tools ? 1 : 0)
                        .allowsHitTesting(selectedTab == .tools)
                        .accessibilityHidden(selectedTab != .tools)
                        .suppressTabBarHiddenPreference(unless: selectedTab == .tools)

                    SettingsView {
                        await permissionVM.resetPermission()
                    }
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                    .accessibilityHidden(selectedTab != .settings)
                    .suppressTabBarHiddenPreference(unless: selectedTab == .settings)
                }
                .safeAreaInset(edge: .bottom) {
                    // CONSTANT 150pt bottom safe-area reservation for
                    // the floating tab bar — never conditional.
                    // Previous conditional design left the state stuck
                    // after destination pops (Code Review #1). Now
                    // destinations reclaim this strip themselves via
                    // `.ignoresSafeArea(.container, edges: .bottom)`
                    // (baked into the `hidesTabBar()` modifier).
                    Color.clear.frame(height: DSTabBarMetrics.safeAreaReservation)
                }
                .onPreferenceChange(TabBarVisualHiddenPreferenceKey.self) { hidden in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        isTabBarVisualHidden = hidden
                    }
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
                    // Semi-transparent scrim — matches the kebab bottom
                    // sheet's `black.opacity(0.28)` so both modals share
                    // one backdrop language. Beyond consistency, dimming
                    // fixes two issues seen in the FAB video: the menu's
                    // white background bleeds into the Library grid
                    // without visible boundary, and the tab pill / last
                    // few rows can overlap the menu's edge — the scrim
                    // pushes them back so the menu reads as the focused
                    // surface.
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { $isFABMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion) }
                        .transition(.opacity)
                }

                if !isTabBarVisualHidden {
                    customTabBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Switching tab with the FAB menu open would leave the menu
            // dangling over an unrelated tab. Close it as part of the same
            // interaction.
            .onChange(of: selectedTab) { $isFABMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion) }
            .sheet(item: $editingRef) { ref in
                EditorSheet(container: container, ref: ref)
            }
        } else {
            checkingView
        }
    }

    private var customTabBar: some View {
        // `GlassEffectContainer` — wraps the pill + FAB in one shared
        // glass-sampling region so both draw a coherent Liquid Glass
        // appearance. Glass surfaces sample nearby content to refract
        // it; without a container each glass surface samples
        // independently and they can visibly disagree on tone.
        //
        // `.bottom` alignment inside — the tab pill (72pt: 60pt buttons
        // + 12pt capsule padding) is 12pt taller than the FAB (60pt).
        // Anchoring both to bottom keeps a shared baseline.
        GlassEffectContainer(spacing: DSSpacing.sm) {
            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                HStack(spacing: 2) {
                    tabBarButton(.library, label: "Library", systemImage: "tray.full")
                    tabBarButton(.tools, label: "Tools", systemImage: "IconFourSquares", isCustomAsset: true)
                    tabBarButton(.settings, label: "Settings", systemImage: "gearshape")
                }
                .padding(6)
                .tabBarPillStyle()

                if let libraryVM {
                    LibraryAddButton(viewModel: libraryVM, container: container, isMenuOpen: $isFABMenuOpen)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
    }

    private func tabBarButton(_ tab: RootTab, label: String, systemImage: String, isCustomAsset: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                if isCustomAsset {
                    // Custom template asset (Tools tab) — no SF Symbol
                    // filled/outline variant to switch between, so selection
                    // reads through foreground color + the capsule background
                    // alone, same as the label text below it. The asset's
                    // `template-rendering-intent` in Contents.json makes the
                    // black-on-transparent PNG pick up `foregroundStyle`
                    // automatically; `.renderingMode(.template)` here is a
                    // belt-and-braces guard for the same behaviour.
                    //
                    // Frame bumped 24 → 28 to match the visual weight of
                    // the sibling SF Symbols. `.font(.system(size: 24))`
                    // on an SF Symbol renders a glyph whose visible mark
                    // occupies ~26-28pt (font size sets cap-height, not
                    // bounding box), so a raster asset clamped to a
                    // 24×24pt frame reads noticeably smaller in the tab
                    // bar than its neighbours. 28pt lands the custom
                    // icon within a hair of the SF Symbols' optical size.
                    Image(systemImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolVariant(isSelected ? .fill : .none)
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 76, height: 60)
            // Original subtle brand pill + brand-blue foreground —
            // matches the pattern users learned before this session —
            // with an added `.glassEffect(.regular.interactive())`
            // overlay so the selected tab still carries the iOS 26
            // wet-glass sheen when touched. Solid-brand + white
            // foreground (the earlier "loud" variant) read too far
            // from the app's other stateful chrome; this middle path
            // keeps the mark clearly readable without changing the
            // visual language.
            .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextTertiary)
            .background {
                if isSelected {
                    Capsule().fill(Color.dsBrandPrimarySubtle)
                }
            }
            .glassEffect(
                isSelected ? .regular.interactive() : .identity,
                in: .capsule
            )
            // Reduce-motion gated — Session 13 CHANGELOG Group 5 enforced this
            // app-wide but the tab-bar button was missed.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        // Closure filter — fire haptic ONLY on false→true (the newly-selected
        // tab). Without it, tapping a different tab produces two haptics: the
        // previously-selected button transitions true→false + the new one
        // transitions false→true, back-to-back within one runloop tick.
        // Same pattern Session 14 applied to `TypeTabButton`.
        .sensoryFeedback(.selection, trigger: isSelected) { _, newValue in
            newValue
        }
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

    private func initializeViewModelsIfNeeded() {
        if permissionVM == nil {
            permissionVM = container.makeFolderPermissionViewModel(store: libraryStore)
        }
        if libraryVM == nil {
            libraryVM = container.makeLibraryViewModel(store: libraryStore)
        }
        if onboardingVM == nil {
            // Weak capture would be ideal but `@State` on a value is already
            // owned by the view — the closure only fires while this view
            // exists, so a plain capture is safe.
            onboardingVM = OnboardingViewModel {
                hasCompletedOnboarding = true
            }
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
        // Downstream views (Merge/Split/Convert/Scan, LibraryAddButton,
        // `EditorSheet`) read the presenter via `@Environment` and would
        // trap-fatalError if it were missing in the preview once state
        // advances beyond `.checking`.
        .environment(DSToastPresenter())
}
