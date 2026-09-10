import SwiftUI

/// A single onboarding page — glass card stack containing the hero art, with
/// the headline + subtitle underneath. The CTA footer (indicator + primary
/// + secondary buttons) lives on the container so it stays anchored across
/// page swipes.
struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer(minLength: DSSpacing.md)

            heroCard
                .padding(.horizontal, DSSpacing.xl)
                .modifier(HeroBobModifier(enabled: !reduceMotion, phaseSeed: page.id))

            textBlock
                .padding(.horizontal, DSSpacing.lg)

            if page.showsPrivacyChip {
                privacyChip
                    .padding(.horizontal, DSSpacing.lg)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.subtitle)")
    }

    // MARK: - Hero card

    /// Wraps the page's hero art in the shared glass card stack. For the
    /// `.trackDocuments` page the "hero" is a SwiftUI composition
    /// (`OnboardingTrackDocumentsHero`); the rest use the 3D PNG assets
    /// straight from `Archive/`.
    private var heroCard: some View {
        OnboardingCardStack {
            heroContent
                .frame(maxWidth: .infinity)
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var heroContent: some View {
        switch page.id {
        case .trackDocuments:
            OnboardingTrackDocumentsHero()
        default:
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .padding(DSSpacing.sm)
        }
    }

    // MARK: - Text block (title + subtitle)

    /// White text on the deep gradient background. Subtitle uses a slight
    /// opacity dip so the hierarchy stays crisp without pulling in a second
    /// color.
    private var textBlock: some View {
        VStack(spacing: DSSpacing.sm) {
            Text(page.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy chip (S4 only)

    /// Translucent white chip — the dark gradient reads it as a soft glow,
    /// matching the rest of the on-dark UI.
    private var privacyChip: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs + 2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsStatusSuccess)

            Text("On-device only  •  Encrypted at rest  •  Revoke anytime in Settings")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.6)
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
        OnboardingPageView(page: OnboardingPage.all[0])
    }
}

#Preview("Choose Folder (S4 with chip)") {
    ZStack {
        OnboardingAuroraBackground(page: .chooseFolder)
        OnboardingPageView(page: OnboardingPage.all[3])
    }
}
