// Session 12 (2026-09-04) — Safari/Notes-style behaviour: hide the
// custom bottom tab bar while the user is actively scrolling, bring
// it back when scrolling stops. Reduces UI-chrome overlap with
// content mid-scroll and gives back the full screen for reading.
//
// Detection uses `.onScrollGeometryChange` (iOS 18+, target 26.2) +
// a 350ms debounce timer to define "stopped scrolling". Simpler
// `.onScrollPhaseChange` was tried first but proved unreliable on
// mixed input paths (trackpad two-finger scroll, momentum scroll
// tails on List) — geometry change catches every offset delta,
// which is what we actually care about.
//
// Publishes the "hidden" state via `TabBarHiddenPreferenceKey`;
// `RootView` observes and collapses both the tab pill and its
// 130pt safe-area inset with a matched animation.

import SwiftUI

extension View {
    /// Attach to a ScrollView / List / Form — tracks its content
    /// offset; when the offset moves, ask `RootView` to hide the
    /// custom tab bar. After 350ms of no offset change, ask it to
    /// show again.
    func autoHidesTabBarOnScroll() -> some View {
        modifier(AutoHideTabBarOnScrollModifier())
    }
}

private struct AutoHideTabBarOnScrollModifier: ViewModifier {
    @State private var isScrolling = false
    /// Cancellable debounce timer — starts fresh every time the
    /// content offset changes. If no change arrives for 350ms, we
    /// mark scrolling as stopped and republish the preference.
    @State private var idleTask: Task<Void, Never>?

    private let idleDelay: Duration = .milliseconds(350)

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                // Tiny threshold to ignore layout-caused jitter (e.g.
                // safe-area recompute) without missing real user drags.
                guard abs(newValue - oldValue) > 0.5 else { return }
                if !isScrolling {
                    isScrolling = true
                }
                // Restart the idle countdown on every offset tick.
                idleTask?.cancel()
                idleTask = Task { @MainActor in
                    try? await Task.sleep(for: idleDelay)
                    guard !Task.isCancelled else { return }
                    isScrolling = false
                }
            }
            // Visual hide only — MUST NOT collapse the safeAreaInset,
            // otherwise the scroll content reflows mid-scroll (content
            // jumps up as the reserved space disappears, then back
            // down when the pill returns). `.hidesTabBarVisually`
            // keeps the inset reserved.
            .hidesTabBarVisually(isScrolling)
            .onDisappear {
                // Clean up the timer if the view goes away mid-scroll —
                // otherwise a pending isScrolling=false could fire after
                // the view unmounts (harmless but wasteful).
                idleTask?.cancel()
                idleTask = nil
            }
    }
}
