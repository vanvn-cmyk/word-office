import SwiftUI

/// A single onboarding page — hero art floating directly on the shared dark
/// background, with the headline + subtitle underneath. Previously wrapped
/// the hero in `OnboardingCardStack` (a glassmorphism card); removed per user
/// feedback matching the approved mockup, where the hero art (or, for S3,
/// `OnboardingTrackDocumentsHero`'s own opaque card) sits straight on the
/// background with no glass wrapper — S3's hero already draws its own real
/// DS-token card, so the old glass card was doubling up on it. The CTA
/// footer (indicator + primary + secondary buttons) lives on the container
/// so it stays anchored across page swipes.
struct OnboardingPageView: View {
    let page: OnboardingPage
    /// Whether this page is the pager's current selection. Drives the hero's
    /// reveal animation (scale + fade in). Fires once `TabView(selection:)`
    /// commits to this page (a swipe crossing its threshold, or a
    /// CTA-driven `advance()`) — not a continuous, drag-tracked animation; a
    /// slow manual drag shows the hero pinned at its dimmed/shrunk resting
    /// state until the swipe commits, then it animates in over
    /// `revealScale`/`revealOpacity`'s 0.4s duration.
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer(minLength: DSSpacing.md)

            heroCard
                .padding(.horizontal, DSSpacing.xl)
                .modifier(HeroBobModifier(enabled: !reduceMotion, phaseSeed: page.id))
                .scaleEffect(revealScale)
                .opacity(revealOpacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: isActive)

            textBlock
                .padding(.horizontal, DSSpacing.lg)

            if page.showsPrivacyChip {
                privacyChip
                    .padding(.horizontal, DSSpacing.lg)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Explicit label for the combined element — `.combine` alone would have
    /// worked, but an explicit `.accessibilityLabel` on the same element
    /// replaces rather than supplements it, so the privacy chip's copy (S4
    /// only) has to be folded in by hand or VoiceOver silently drops it.
    private var accessibilityLabel: String {
        page.showsPrivacyChip
            ? "\(page.title). \(page.subtitle). On-device only. Encrypted at rest. Revoke anytime in Settings."
            : "\(page.title). \(page.subtitle)"
    }

    private var revealScale: CGFloat {
        reduceMotion ? 1.0 : (isActive ? 1.0 : 0.92)
    }

    private var revealOpacity: Double {
        reduceMotion ? 1.0 : (isActive ? 1.0 : 0.4)
    }

    // MARK: - Hero

    /// The page's hero art, floating directly on the shared dark background
    /// (no card wrapper — see the type-level doc comment). `.editOffice`,
    /// `.tools`, and `.trackDocuments` are SwiftUI compositions
    /// (`OnboardingEditHero`, `OnboardingToolsHero`, `OnboardingTrackDocumentsHero`)
    /// for real animation; only `.chooseFolder` still uses a static 3D PNG
    /// asset from `Assets.xcassets` (its "files flowing into a folder"
    /// content already matches its copy, unlike the other 3's original
    /// assets).
    private var heroCard: some View {
        heroContent
            .frame(maxWidth: .infinity)
            .frame(height: 260)
    }

    @ViewBuilder
    private var heroContent: some View {
        switch page.id {
        case .editOffice:
            OnboardingEditHero(isActive: isActive)
        case .tools:
            OnboardingToolsHero(isActive: isActive)
        case .trackDocuments:
            OnboardingTrackDocumentsHero(isActive: isActive)
        default:
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .padding(DSSpacing.sm)
        }
    }

    // MARK: - Text block (title + subtitle)

    /// Fixed near-black/gray text (not `dsTextPrimary`/`dsTextSecondary`) —
    /// this background is deliberately NOT theme-aware (see
    /// `OnboardingAuroraBackground`'s doc comment), so a theme-adaptive text
    /// token would flip to near-white under system Dark Mode and disappear
    /// against this fixed off-white surface. Hex values match the approved
    /// mockup's light-mode `--text`/`--text-secondary`.
    private var textBlock: some View {
        VStack(spacing: DSSpacing.sm) {
            Text(page.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(OnboardingColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(OnboardingColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    // MARK: - Privacy chip (S4 only)

    /// Green "trust" tint, fixed literal values (same not-theme-aware reason
    /// as `textBlock` above — `dsStatusSuccess`/`dsStatusSuccessBackground`
    /// both have dark-mode variants meant for a dark surface, which would
    /// mismatch this fixed-light background under system Dark Mode). Hex
    /// values match the approved mockup's light-mode `--success`/`--success-bg`.
    private var privacyChip: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs + 2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnboardingColors.success)

            Text("On-device only  •  Encrypted at rest  •  Revoke anytime in Settings")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(OnboardingColors.success)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OnboardingColors.success.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingColors.success.opacity(0.25), lineWidth: 0.6)
        }
    }

}

// MARK: - Hero bob animation

/// Gentle continuous ±4pt vertical bob. Uses `phaseAnimator` with a fresh
/// `trigger` per page so a swipe restarts the cycle cleanly (no half-cycle
/// discontinuity when the hero swaps).
private struct HeroBobModifier: ViewModifier {
    let enabled: Bool
    let phaseSeed: OnboardingPage.Kind

    func body(content: Content) -> some View {
        if enabled {
            content.phaseAnimator([false, true], trigger: phaseSeed) { view, phase in
                view.offset(y: phase ? -4 : 3)
            } animation: { _ in
                .easeInOut(duration: 2.6)
            }
        } else {
            content
        }
    }
}

#Preview("Edit Office") {
    ZStack {
        OnboardingAuroraBackground(page: .editOffice)
        OnboardingPageView(page: OnboardingPage.all[0], isActive: true)
    }
}

#Preview("Choose Folder (S4 with chip)") {
    ZStack {
        OnboardingAuroraBackground(page: .chooseFolder)
        OnboardingPageView(page: OnboardingPage.all[3], isActive: true)
    }
}
