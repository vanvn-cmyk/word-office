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
    private static let accentBlue = Color(red: 0x5B / 255, green: 0x8C / 255, blue: 0xFF / 255)

    /// Per-page accent blob — gives each screen a distinct personality while
    /// the two brand-blue blobs stay as a constant "foundation" layer.
    private func pageAccentColor(for kind: OnboardingPage.Kind) -> Color {
        switch kind {
        case .editOffice:     Color(red: 0.55, green: 0.35, blue: 0.95) // violet — creative editing
        case .tools:          Color(red: 0.95, green: 0.52, blue: 0.18) // amber — productive tools
        case .trackDocuments: Color(red: 0.10, green: 0.75, blue: 0.65) // teal  — organized tracking
        case .paywall:        Color(red: 0.20, green: 0.35, blue: 0.95) // blue  — premium offer
        case .chooseFolder:   Color(red: 0.35, green: 0.45, blue: 0.98) // indigo — systematic storage
        }
    }

    private func pageAccentAnchor(for kind: OnboardingPage.Kind) -> UnitPoint {
        switch kind {
        case .editOffice:     UnitPoint(x: 0.75, y: 0.30)
        case .tools:          UnitPoint(x: 0.20, y: 0.25)
        case .trackDocuments: UnitPoint(x: 0.80, y: 0.40)
        case .paywall:        UnitPoint(x: 0.75, y: 0.25)
        case .chooseFolder:   UnitPoint(x: 0.25, y: 0.35)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.baseColor

                // Primary brand-blue blob — drifts horizontally
                blob(color: .dsBrandPrimary, size: proxy.size.width * 1.1,
                     anchor: primaryAnchor(for: page), in: proxy.size)
                    .offset(x: isDrifting ? 18 : -18, y: isDrifting ? -12 : 12)
                    .opacity(breathingOpacity(base: 0.38))
                    .scaleEffect(breathingScale)

                // Secondary blue blob — counter-drifts
                blob(color: Self.accentBlue, size: proxy.size.width * 0.80,
                     anchor: secondaryAnchor(for: page), in: proxy.size)
                    .offset(x: isDrifting ? -14 : 14, y: isDrifting ? 10 : -10)
                    .opacity(breathingOpacity(base: 0.28))
                    .scaleEffect(breathingScale, anchor: .center)

                // Per-page accent blob — changes color & position per page,
                // adding a distinct hue identity to each onboarding screen.
                blob(color: pageAccentColor(for: page), size: proxy.size.width * 0.65,
                     anchor: pageAccentAnchor(for: page), in: proxy.size)
                    .offset(x: isDrifting ? 10 : -10, y: isDrifting ? -8 : 8)
                    .opacity(breathingOpacity(base: 0.22))
                    .scaleEffect(breathingScale, anchor: .center)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: page)
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
        case .paywall:         UnitPoint(x: 0.15, y: 0.10)
        case .chooseFolder:    UnitPoint(x: 0.8, y: 0.12)
        }
    }

    private func secondaryAnchor(for kind: OnboardingPage.Kind) -> UnitPoint {
        switch kind {
        case .editOffice:      UnitPoint(x: 0.9, y: 0.55)
        case .tools:            UnitPoint(x: 0.1, y: 0.6)
        case .trackDocuments:  UnitPoint(x: 0.85, y: 0.5)
        case .paywall:         UnitPoint(x: 0.85, y: 0.55)
        case .chooseFolder:    UnitPoint(x: 0.15, y: 0.58)
        }
    }
}

#Preview("S1") { OnboardingAuroraBackground(page: .editOffice) }
#Preview("S4") { OnboardingAuroraBackground(page: .chooseFolder) }
