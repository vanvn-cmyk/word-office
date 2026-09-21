import Foundation

/// Decides when to show the in-app feedback survey.
///
/// Trigger condition (all must be true):
/// - User navigates to Home or Tools tab
/// - Foreground usage ≥ `RemoteConfigService.shared.surveyThresholdMinutes`
/// - Survey has never been shown before (`feedback.hasShown` UserDefaults flag)
///
/// Call `check(usageTracker:)` on every qualifying tab navigation.
/// State machine: idle → overlay → sheet → done (flag persists).
@Observable
@MainActor
final class FeedbackTriggerService {

    private(set) var shouldShowOverlay: Bool = false
    private(set) var shouldShowSheet: Bool = false

    private var hasShown: Bool {
        get { UserDefaults.standard.bool(forKey: "feedback.hasShown") }
        set { UserDefaults.standard.set(newValue, forKey: "feedback.hasShown") }
    }

    func check(usageTracker: AppUsageTracker) {
        guard !hasShown, !shouldShowOverlay, !shouldShowSheet else { return }
        let threshold = Double(RemoteConfigService.shared.surveyThresholdMinutes)
        guard usageTracker.elapsedMinutes >= threshold else { return }
        shouldShowOverlay = true
    }

    func overlayDidComplete() {
        hasShown = true
        shouldShowOverlay = false
        shouldShowSheet = true
    }

    func sheetDidDismiss() {
        shouldShowSheet = false
    }

    /// Call when the user opens the feedback sheet manually (e.g. via Settings).
    /// Prevents the auto-trigger from firing again after a manual session.
    func markShown() {
        hasShown = true
        shouldShowOverlay = false
        shouldShowSheet = false
    }
}
