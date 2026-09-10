import SwiftUI

/// Pill dots for the onboarding pager. Active dot is a wider pill, inactive
/// dots are small circles. Colors are injected so the same component works
/// on both light (brand blue on white) and dark (white on gradient) surfaces.
///
/// Purely presentational — parent owns the current index; tap-to-jump is
/// intentionally NOT supported (a page pager of this shape is swipe/CTA-
/// driven; two competing navigation affordances would confuse discovery).
struct OnboardingPageIndicator: View {
    let pageCount: Int
    let currentIndex: Int
    let activeColor: Color
    let inactiveColor: Color

    /// Backwards-compatible init defaulting to brand colors for surfaces that
    /// don't pass colors explicitly.
    init(pageCount: Int,
         currentIndex: Int,
         activeColor: Color = .dsBrandPrimary,
         inactiveColor: Color = .dsBrandPrimarySubtle) {
        self.pageCount = pageCount
        self.currentIndex = currentIndex
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                let isActive = index == currentIndex
                Capsule()
                    .fill(isActive ? activeColor : inactiveColor)
                    .frame(width: isActive ? 24 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(pageCount)")
    }
}

#Preview("Brand colors") {
    VStack(spacing: DSSpacing.xl) {
        OnboardingPageIndicator(pageCount: 4, currentIndex: 0)
        OnboardingPageIndicator(pageCount: 4, currentIndex: 1)
        OnboardingPageIndicator(pageCount: 4, currentIndex: 2)
        OnboardingPageIndicator(pageCount: 4, currentIndex: 3)
    }
    .padding()
    .background(Color.dsBackgroundPrimary)
}

#Preview("White on dark") {
    VStack(spacing: DSSpacing.xl) {
        OnboardingPageIndicator(pageCount: 4, currentIndex: 0,
                                activeColor: .white, inactiveColor: .white.opacity(0.35))
        OnboardingPageIndicator(pageCount: 4, currentIndex: 2,
                                activeColor: .white, inactiveColor: .white.opacity(0.35))
    }
    .padding()
    .background(Color.black)
}
