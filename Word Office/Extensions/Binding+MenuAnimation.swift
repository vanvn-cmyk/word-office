import SwiftUI

extension Binding where Value == Bool {
    /// Closes a FAB / drop-down menu backed by a `Bool` binding with the
    /// project's shared close cadence — 0.15s ease-out, gated by the
    /// caller's `accessibilityReduceMotion` flag.
    ///
    /// Consolidated in Session 14 from two byte-for-byte identical closers
    /// (`RootView.closeFABMenu` and `LibraryAddButton.closeMenu`) that
    /// both animated the SAME shared `isFABMenuOpen` state. Any future
    /// tweak to the closing motion now happens in exactly one place, so
    /// scrim-tap dismissal and FAB-toggle dismissal can never drift apart
    /// (which is what made the previous `.popover`-based close feel
    /// sluggish — different transactions in flight for the same state
    /// change).
    ///
    /// Idempotent: if the binding is already `false`, this is a no-op and
    /// no animation transaction is opened. Opening one on a no-op state
    /// change spends a frame animating nothing (a real symptom that
    /// showed up when the scrim tap fired one tick before a menu row's
    /// action).
    func closeMenuAnimated(reduceMotion: Bool) {
        guard wrappedValue else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            wrappedValue = false
        }
    }
}
