import SwiftUI

/// Two-card stacked glassmorphism holder used for every onboarding hero.
/// A dim back card sits behind and offset up-left; the front card carries a
/// Liquid Glass surface and hosts arbitrary content via `@ViewBuilder`.
///
/// The stack sells depth without pulling the hero out of the pager: swipes
/// slide the whole stack, keeping the reveal cohesive.
///
/// Structure inside `frontCard` is a `ZStack` (glass → sheen → content →
/// border), never `.overlay(content)` on top of a glass-modified view —
/// that pattern caused the hero to render blurred on iOS 26.
struct OnboardingCardStack<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            backCard
            frontCard
        }
    }

    // MARK: - Back card (decorative)

    private var backCard: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(backCardBorder)
            .padding(.horizontal, 18)
            .offset(x: -6, y: -14)
            .scaleEffect(0.94, anchor: .center)
    }

    private var backCardBorder: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
    }

    // MARK: - Front card (glass background + content on top)

    private var frontCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.clear, in: .rect(cornerRadius: 28))

            content()
                .padding(DSSpacing.md)

            frontCardBorder
        }
        .shadow(color: Color.black.opacity(0.25), radius: 30, y: 20)
        .shadow(color: Color.white.opacity(0.08), radius: 1, y: -1)
    }

    private var frontCardBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(borderGradient, lineWidth: 1)
            .allowsHitTesting(false)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.white.opacity(0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview("Stack") {
    ZStack {
        OnboardingAuroraBackground(page: .tools)
        OnboardingCardStack {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 260)
        }
        .padding(.horizontal, DSSpacing.xl)
    }
}
