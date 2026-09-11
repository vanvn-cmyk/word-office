import SwiftUI

/// Fixed color literals for the onboarding pager — not DS tokens, because
/// this feature's background (`OnboardingAuroraBackground`) is deliberately
/// NOT theme-aware (same fixed-hero reasoning as `PaywallView`'s gradient),
/// so a theme-adaptive DS token would flip to a dark-surface variant under
/// system Dark Mode and mismatch or disappear. Shared here so
/// `OnboardingPageView` and `OnboardingContainerView` can't drift apart on
/// the same nominal color (a real code-review finding on this feature —
/// each file used to define its own copy of `textSecondary`).
enum OnboardingColors {
    static let textPrimary = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1F / 255)
    static let textSecondary = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x72 / 255)
    static let success = Color(red: 0x1F / 255, green: 0x7A / 255, blue: 0x3E / 255)
    static let error = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
}
