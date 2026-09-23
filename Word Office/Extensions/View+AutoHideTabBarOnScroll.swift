// Direction-aware tab bar auto-hide: scroll DOWN → hide, scroll UP → show.
// This mirrors the pattern used in Safari, YouTube, and iOS Mail.
//
// Detection: `.onScrollGeometryChange` (iOS 18+, deployment target 26.2)
// tracks raw content-offset deltas. A ±4pt threshold ignores layout-jitter
// (safe-area recompute, momentum tail micro-ticks) without masking real
// intentional drags. When the user reaches the very top (offset ≤ 0) the
// bar is always restored — prevents the bar from staying hidden on a
// pull-to-refresh bounce or rubber-band.
//
// Visual hide only — safeAreaInset (constant 150pt in RootView) is never
// collapsed, so content position is stable regardless of bar visibility.

import SwiftUI

extension View {
    /// Attach to a ScrollView / List / Form — hides the custom tab bar
    /// on downward scroll, restores it on upward scroll or when the
    /// user reaches the top of the content.
    func autoHidesTabBarOnScroll() -> some View {
        modifier(AutoHideTabBarOnScrollModifier())
    }
}

private struct AutoHideTabBarOnScrollModifier: ViewModifier {
    @State private var isHidden = false
    /// Last offset we made a hide/show decision at. Updated only when
    /// the delta clears the threshold so small jitter doesn't shift the
    /// reference point.
    @State private var lastDecisionOffset: CGFloat = 0

    /// Minimum offset change before we commit a new hide/show decision.
    /// 4pt is enough to ignore inertia micro-ticks but not real swipes.
    private let threshold: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                let delta = newOffset - lastDecisionOffset

                // Always restore when at or above the top of the list.
                if newOffset <= 0 {
                    lastDecisionOffset = 0
                    if isHidden { isHidden = false }
                    return
                }

                if delta > threshold {
                    // Scrolling down — hide.
                    lastDecisionOffset = newOffset
                    if !isHidden { isHidden = true }
                } else if delta < -threshold {
                    // Scrolling up — show.
                    lastDecisionOffset = newOffset
                    if isHidden { isHidden = false }
                }
            }
            .hidesTabBarVisually(isHidden)
    }
}
