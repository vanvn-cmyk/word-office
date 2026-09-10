// Session 12 (2026-09-04) — replaces `.navigationTitle` + default
// display mode across the tools tab and its destinations. Two goals:
//
// 1. Reclaim the ~55pt of vertical space that SwiftUI's large-title
//    mode reserves above content. Every tool screen (Tools home,
//    Merge, Split, Convert × 4, Scan, Sign, Fill Form, Print) has a
//    tight action-bar layout below the nav bar, so the fixed large-
//    title strip felt wasteful (user report: "Tools still wastes too
//    much vertical space at the top").
//
// 2. The default inline title in the nav bar is 17pt semibold —
//    noticeably smaller than a large title. When the large title
//    collapses on scroll it shrinks by half. User wanted the visible
//    title to STAY prominent, matching the pre-scroll size ("the
//    scrolled title is too small — bump it up to the original tool
//    title size").
//
// Applies `.navigationBarTitleDisplayMode(.inline)` (no large-title
// area) + a `.principal` toolbar item styled at `.title2.bold()`
// (~22pt bold) — bigger than default inline, still fits inside the
// standard nav bar height. `.navigationTitle` stays on the underlying
// view for accessibility + parent back-button label; `.principal`
// overrides only the visual title.

import SwiftUI

extension View {
    /// Apply an inline nav-bar title styled prominently (bigger than
    /// SwiftUI's 17pt default). Keeps `.navigationTitle` for
    /// accessibility + back-button semantics; overrides visual
    /// display via a `.principal` toolbar item.
    func prominentInlineTitle(_ title: LocalizedStringKey) -> some View {
        modifier(ProminentInlineTitleModifier(title: .key(title)))
    }

    /// String overload — for dynamic titles like `ConvertDirection.title`
    /// and `ScanFlowView.navigationTitle` that aren't backed by a
    /// LocalizedStringKey literal at the call site.
    func prominentInlineTitle(_ title: String) -> some View {
        modifier(ProminentInlineTitleModifier(title: .plain(title)))
    }
}

private struct ProminentInlineTitleModifier: ViewModifier {
    let title: Title

    enum Title {
        case key(LocalizedStringKey)
        case plain(String)
    }

    func body(content: Content) -> some View {
        content
            .modifier(NavigationTitleModifier(title: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleText
                        .font(.title2.bold())
                        .foregroundStyle(Color.dsTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }

    @ViewBuilder
    private var titleText: some View {
        switch title {
        case .key(let key):    Text(key)
        case .plain(let str):  Text(str)
        }
    }
}

/// Small shim so both title flavours reach `.navigationTitle` without
/// duplicating the modifier chain — `.navigationTitle` also has separate
/// overloads for `LocalizedStringKey` vs `String`.
private struct NavigationTitleModifier: ViewModifier {
    let title: ProminentInlineTitleModifier.Title

    @ViewBuilder
    func body(content: Content) -> some View {
        switch title {
        case .key(let key):    content.navigationTitle(key)
        case .plain(let str):  content.navigationTitle(str)
        }
    }
}
