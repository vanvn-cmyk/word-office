import Foundation
import Observation
import SwiftUI
import UIKit

/// Global toast presenter injected via `.environment(_:)` at the app root
/// (`Word_OfficeApp`). One toast at a time — a new `show(...)` replaces the
/// current toast (its dismiss timer is cancelled) so quick successive
/// completions (e.g. batched merges) don't queue up behind a stale toast.
///
/// Callers read via `@Environment(DSToastPresenter.self)` and call
/// `.show(.success, title: "…", filename: url.lastPathComponent)` — the
/// overlay in `Word_OfficeApp.body` reads `current` and renders `DSToast`.
@Observable
@MainActor
final class DSToastPresenter {
    /// Individual toast payload. `id` is a per-show UUID so the presentation
    /// overlay can key its transition off it (`.id(item.id)` forces a fresh
    /// transition when one toast replaces another mid-display).
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let filename: String?
        let style: Style

        enum Style {
            case success
            case error
            case info

            /// `~/CLAUDE.md` Toast Notifications convention: success auto-
            /// dismisses at 4s, error is persistent (`nil`) until the user
            /// dismisses it, info at 6s.
            var defaultAutoDismissDuration: Duration? {
                switch self {
                case .success: .seconds(4)
                case .error: nil
                case .info: .seconds(6)
                }
            }
        }
    }

    private(set) var current: Item?
    private var dismissTask: Task<Void, Never>?

    /// Show a toast. Auto-dismisses after `duration` unless replaced or
    /// manually dismissed first — `nil` (the `.error` default) means
    /// persistent, no auto-dismiss timer at all.
    ///
    /// Default duration follows style, per `~/CLAUDE.md`'s Toast
    /// Notifications convention: success 4s, error persistent until
    /// dismissed, info 6s. Pass an explicit `duration` to override.
    ///
    /// Also posts a VoiceOver announcement so users without visual feedback
    /// still hear the confirmation — a bottom/top overlay that appears with
    /// no focus change is otherwise invisible to VoiceOver. Combines
    /// `title` + `filename` for the announcement, matching the visual card.
    func show(_ style: Item.Style, title: String, filename: String? = nil, duration: Duration? = nil) {
        dismissTask?.cancel()
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.25)) {
            current = Item(title: title, filename: filename, style: style)
        }
        let announcement = filename.map { "\(title), \($0)" } ?? title
        UIAccessibility.post(notification: .announcement, argument: announcement)
        guard let resolvedDuration = duration ?? style.defaultAutoDismissDuration else { return }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: resolvedDuration)
            // Cancellation check: a replacement `show` cancels this task, and
            // the replacement will animate its own item in. If we didn't guard,
            // the stale timer would fire mid-way and hide the new toast early.
            guard let self, !Task.isCancelled else { return }
            withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.25)) {
                self.current = nil
            }
        }
    }

    /// Dismiss immediately (e.g. user tapped the toast).
    func dismiss() {
        dismissTask?.cancel()
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.2)) {
            current = nil
        }
    }
}
