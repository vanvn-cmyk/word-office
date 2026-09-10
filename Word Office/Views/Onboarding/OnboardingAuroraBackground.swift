import SwiftUI

/// Full-bleed per-page gradient behind the onboarding pager. Each page has
/// its own palette so swiping produces a smooth cross-fade of hues.
///
/// Deep top / lighter bottom on every screen keeps the white text at the top
/// safe while the CTA area at the bottom sits on the brightest wash.
///
/// Animated via `.animation(_:value: page)` — SwiftUI interpolates between
/// palettes as the pager slides so the background flows with the swipe.
struct OnboardingAuroraBackground: View {
    let page: OnboardingPage.Kind

    var body: some View {
        LinearGradient(
            colors: palette(for: page),
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.5), value: page)
        .ignoresSafeArea()
        .overlay(starOverlay)
    }

    /// Faint white speckle overlay — the tiny "stars" scattered on the deep
    /// gradient. Purely decorative, always on top so it survives palette
    /// interpolation cleanly.
    private var starOverlay: some View {
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<40 {
                let x = Double.random(in: 0..<size.width, using: &rng)
                let y = Double.random(in: 0..<size.height, using: &rng)
                let radius = Double.random(in: 0.5...1.6, using: &rng)
                let alpha = Double.random(in: 0.25...0.6, using: &rng)
                let rect = CGRect(x: x, y: y, width: radius, height: radius)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func palette(for kind: OnboardingPage.Kind) -> [Color] {
        switch kind {
        case .editOffice:
            // Deep navy → royal blue → sky
            return [
                Color(red: 0.04, green: 0.09, blue: 0.28),
                Color(red: 0.09, green: 0.20, blue: 0.55),
                Color(red: 0.18, green: 0.38, blue: 0.82)
            ]
        case .tools:
            // Deep indigo → violet → soft purple
            return [
                Color(red: 0.06, green: 0.06, blue: 0.24),
                Color(red: 0.20, green: 0.14, blue: 0.55),
                Color(red: 0.36, green: 0.28, blue: 0.72)
            ]
        case .trackDocuments:
            // Deep purple → magenta → coral
            return [
                Color(red: 0.11, green: 0.07, blue: 0.28),
                Color(red: 0.36, green: 0.17, blue: 0.52),
                Color(red: 0.89, green: 0.46, blue: 0.48)
            ]
        case .chooseFolder:
            // Deep navy → mid blue → electric sky
            return [
                Color(red: 0.04, green: 0.10, blue: 0.32),
                Color(red: 0.10, green: 0.28, blue: 0.72),
                Color(red: 0.22, green: 0.52, blue: 0.94)
            ]
        }
    }
}

#Preview("S1") { OnboardingAuroraBackground(page: .editOffice) }
#Preview("S2") { OnboardingAuroraBackground(page: .tools) }
#Preview("S3") { OnboardingAuroraBackground(page: .trackDocuments) }
#Preview("S4") { OnboardingAuroraBackground(page: .chooseFolder) }
