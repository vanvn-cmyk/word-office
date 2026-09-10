// Session 12 (2026-09-04, revision — Code Review finding #1) —
// hide the custom bottom tab bar in `RootView.customTabBar`.
//
// Previous revision used TWO preferences (visual + inset-collapse)
// intending to let destinations reclaim the safe-area strip while
// scroll auto-hide only affected visual. That design had a real bug:
// `onPreferenceChange` doesn't fire reliably when a NavigationStack
// destination unmounts and its preference reduces back to the default.
// The safe-area stayed collapsed on the parent tab home, and content
// extended into the tab bar zone (the persistent "Tools overlap"
// complaint).
//
// Fix (per code-review finding #1): drop the inset-collapse
// preference entirely. Parent `safeAreaInset` in `RootView` is a
// CONSTANT 150pt — never conditional — so there's no state to fail
// to reset. Destinations that want to reclaim that strip apply
// `.ignoresSafeArea(.container, edges: .bottom)` themselves; the
// `hidesTabBar()` modifier does this for them.

import SwiftUI

/// Visual hide — the pill isn't rendered when true. Reduced with `||`.
struct TabBarVisualHiddenPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Full hide for pushed destinations — hides the pill visually
    /// AND ignores the parent's 150pt bottom safe-area so the
    /// destination's own layout (action bar via its own
    /// `.safeAreaInset`, PDF canvas) uses the full available bottom
    /// strip. Idempotent — call once at the outer container of the
    /// pushed destination view.
    func hidesTabBar() -> some View {
        preference(key: TabBarVisualHiddenPreferenceKey.self, value: true)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Visual hide only — pill hides, safeAreaInset (constant 150pt)
    /// stays reserved. Use for scroll-based auto-hide where the pill
    /// flickers away mid-scroll but content position must NOT change.
    func hidesTabBarVisually(_ hidden: Bool = true) -> some View {
        preference(key: TabBarVisualHiddenPreferenceKey.self, value: hidden)
    }

    /// Zeroes out this subtree's `TabBarVisualHiddenPreferenceKey` contribution
    /// when `isActive` is false. Needed because `RootView.libraryShell` keeps
    /// all 3 tabs mounted at once (to preserve each `NavigationStack`'s depth
    /// across tab switches) inside one `ZStack` — without this, a pushed
    /// destination's `.hidesTabBar()` on the INACTIVE tab still reaches the
    /// shared `||`-reducing ancestor and hides the tab bar app-wide until the
    /// user navigates back into that tab and pops the destination.
    func suppressTabBarHiddenPreference(unless isActive: Bool) -> some View {
        transformPreference(TabBarVisualHiddenPreferenceKey.self) { value in
            if !isActive { value = false }
        }
    }
}
