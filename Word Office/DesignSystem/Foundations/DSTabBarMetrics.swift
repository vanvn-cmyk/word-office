import CoreGraphics

/// Bottom-clearance constants for `RootView`'s floating custom tab bar —
/// previously 4 independent magic numbers across `RootView.swift`,
/// `ToolsTabView.swift`, `LibraryView.swift`, and `SettingsView.swift` with
/// no shared source of truth (Session 12 code-review finding). Grouped here
/// so a future tab-bar height change starts from one canonical place instead
/// of a re-derive-by-trial-and-error hunt through 4 files.
enum DSTabBarMetrics {
    /// `RootView.libraryShell`'s CONSTANT bottom `safeAreaInset` reserved for
    /// the tab bar pill + FAB — never conditional (Session 12 Code Review
    /// finding #1: a conditional version left `isTabBarInsetCollapsed` stuck
    /// true after a destination pop).
    static let safeAreaReservation: CGFloat = 150

    /// Extra trailing spacer `ToolsTabView`'s card-grid content appends on
    /// top of `safeAreaReservation` as the final guaranteed clearance for
    /// that screen — tuned separately from the list screens below because a
    /// `LazyVGrid`'s bottom row sits closer to the safe-area edge than a
    /// `List`'s last row does at the same reserved inset.
    static let gridContentTrailingSpacer: CGFloat = 100

    /// Same role as `gridContentTrailingSpacer`, for `LibraryView`'s and
    /// `SettingsView`'s `List`-based content.
    static let listContentTrailingSpacer: CGFloat = 80
}
