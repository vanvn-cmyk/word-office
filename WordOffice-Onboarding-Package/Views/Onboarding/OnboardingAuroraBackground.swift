import SwiftUI

/// Full-bleed background behind the onboarding pager — an off-white base
/// (`#FAFAFB`) with two soft, blurred brand-blue blobs drifting slowly and
/// breathing in scale/opacity. Third visual pass on this background (see
/// git history / prior session notes for the first two): a flat near-black
/// surface read as too plain on-device, then a barely-there radial wash read
/// as too subtle — this pass intentionally turns both dials up (real
/// `.blur()`, not just a soft-edged gradient; two blobs, not one; visible
/// motion) while staying inside the brand's own blue family so it doesn't
/// regress into the multi-hue "aurora" look reverted earlier in this same
/// feature.
///
/// Deliberately NOT theme-aware — same fixed-hero reasoning as `PaywallView`'s
/// gradient. Text/CTA colors elsewhere in this feature are fixed literals
/// tuned for this exact background, not for system light/dark.
struct OnboardingAuroraBackground: View {
    let page: OnboardingPage.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    /// Continuous idle drift, independent of `isBreathing`'s cycle length so
    /// the two don't lock into one visible pulse. Genuinely-looping motion —
    /// review flagged the doc/behavior gap when this only existed on paper.
    @State private var isDrifting = false

    private static let baseColor = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFB / 255)
    /// The dark-mode value of `BrandPrimary` (a lighter, more saturated
    /// blue) — used only as the second blob's tint so the two blobs read as
    /// "one family, two depths" instead of one flat repeated color.
    private static let accentBlue = Color(red: 0x5B / 255, green: 0x8C / 255, blue: 0xFF / 255)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.baseColor

                blob(color: .dsBrandPrimary, size: proxy.size.width * 1.1,
                     anchor: primaryAnchor(for: page), in: proxy.size)
                    .offset(x: isDrifting ? 16 : -16, y: isDrifting ? -10 : 10)
                    .opacity(breathingOpacity(base: 0.32))
                    .scaleEffect(breathingScale)

                blob(color: Self.accentBlue, size: proxy.size.width * 0.75,
                     anchor: secondaryAnchor(for: page), in: proxy.size)
                    .offset(x: isDrifting ? -12 : 12, y: isDrifting ? 8 : -8)
                    .opacity(breathingOpacity(base: 0.24))
                    .scaleEffect(breathingScale, anchor: .center)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: page)
        }
        .ignoresSafeArea()
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
    }

    /// `anchor` is a `UnitPoint` fraction (0...1); `in size` is the enclosing
    /// `GeometryReader`'s concrete size — `Circle.position(x:y:)` needs real
    /// points, so the fraction is scaled here rather than passed straight
    /// through (a `UnitPoint`'s `.x`/`.y` are NOT points on their own).
    private func blob(color: Color, size: CGFloat, anchor: UnitPoint, in containerSize: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.35)
            .position(x: anchor.x * containerSize.width, y: anchor.y * containerSize.height)
    }

    private func breathingOpacity(base: Double) -> Double {
        reduceMotion ? base : (isBreathing ? base * 1.25 : base * 0.75)
    }

    private var breathingScale: CGFloat {
        reduceMotion ? 1.0 : (isBreathing ? 1.08 : 0.94)
    }

    /// Primary blob hugs the top, drifting left→right across S1→S4 (mirrors
    /// the approved mockup's two corner radial washes, applied one per page
    /// instead of both at once).
    private func primaryAnchor(for kind: OnboardingPage.Kind) -> UnitPoint {
        switch kind {
        case .editOffice:      UnitPoint(x: 0.15, y: 0.05)
        case .tools:            UnitPoint(x: 0.85, y: 0.08)
        case .trackDocuments:  UnitPoint(x: 0.2, y: 0.15)
        case .chooseFolder:    UnitPoint(x: 0.8, y: 0.12)
        }
    }

    /// Secondary blob sits lower and opposite-side from the primary, for
    /// depth rather than symmetry.
    private func secondaryAnchor(for kind: OnboardingPage.Kind) -> UnitPoint {
        switch kind {
        case .editOffice:      UnitPoint(x: 0.9, y: 0.55)
        case .tools:            UnitPoint(x: 0.1, y: 0.6)
        case .trackDocuments:  UnitPoint(x: 0.85, y: 0.5)
        case .chooseFolder:    UnitPoint(x: 0.15, y: 0.58)
        }
    }
}

#Preview("S1") { OnboardingAuroraBackground(page: .editOffice) }
#Preview("S4") { OnboardingAuroraBackground(page: .chooseFolder) }
