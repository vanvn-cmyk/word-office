import SwiftUI

/// Gold-plated crown badge — the app-wide "Premium" entry point. Extracted
/// from `LibraryView` so `ToolsTabView` (and any future screen with a
/// title row) can use the exact same badge without duplicating the
/// gradient / shine / shadow recipe.
///
/// Deliberately NOT wrapped in `Button` — iOS 26 auto-wraps every toolbar
/// `Button` in a Liquid Glass capsule that rendered as ovoid around this
/// circular badge (see the anguished comment in `LibraryView` for the
/// full backstory). Bare `View` + `.onTapGesture` skips the auto-wrap
/// path so the badge renders exactly as drawn. `.isButton` trait restores
/// button semantics for VoiceOver.
///
/// Colour tokens (`dsPremiumGoldStart/End`) mirror Apple's own
/// systemYellow → systemOrange pair, the palette App Store / News+ /
/// Podcasts use for subscription-entry badges — a plain nav-bar icon
/// reads as a filter/settings toggle, a gold coin reads as a purchase.
struct PremiumButton: View {
    var onTap: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.dsPremiumGoldStart, Color.dsPremiumGoldEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // Off-center radial highlight — reads as a key light from
                // above-left catching a curved metallic surface.
                .overlay(
                    Circle().fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.38), .clear],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                )
                // Top-half rim highlight — the crisp edge where light
                // physically hits, fading to clear at the vertical center.
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                )
                // Outer gold rim — a plated ring, thin enough (0.75pt @
                // 0.7 opacity) to read as real metal instead of a faded
                // outline.
                .overlay(
                    Circle().strokeBorder(Color.dsPremiumGoldEnd.opacity(0.7), lineWidth: 0.75)
                )
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
                .shadow(color: Color.dsPremiumGoldEnd.opacity(0.42), radius: 9, y: 3)

            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Go Premium")
        .accessibilityAddTraits(.isButton)
    }
}
