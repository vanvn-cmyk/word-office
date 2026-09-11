import SwiftUI

/// SwiftUI-native hero for S2 ("Every tool, one tap away"). Replaces the
/// static `OnboardingTools` PNG (Convert + Sign + a Compress/zip icon) with
/// real tool badges pulled straight from `ToolsTabView`'s actual icons/tints
/// — Convert, Merge, Split, Sign — so the pitch matches what's actually
/// shipped. Deliberately does NOT include Compress: that feature is cut
/// from MVP scope (`Phase0-Implementation-Logic-v2.md`, confirmed absent
/// from `ToolsTabView`'s real card list), so depicting it here would be the
/// same "not fabricated" problem as marketing copy promising a feature that
/// isn't in the product.
///
/// Animation: each badge fans in with a staggered scale + fade on
/// `isActive`, then settles into its own gentle continuous bob — a wave
/// running left→right across the row rather than one bob applied uniformly.
struct OnboardingToolsHero: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasEntered = false

    private struct Tool: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let rotation: Double
        let yOffset: CGFloat
    }

    /// Icon/tint pairs copied from `ToolsTabView`'s real cards (`organizeGrid`,
    /// `fillAndSignGrid`) — not invented. Fan positions (`rotation`/`yOffset`)
    /// echo the approved mockup's 3-card fan, extended to 4.
    private var tools: [Tool] {
        [
            Tool(id: "Convert", icon: "arrow.left.arrow.right", tint: .dsBrandPrimary, rotation: -10, yOffset: 10),
            Tool(id: "Merge", icon: "doc.on.doc.fill", tint: .dsDocumentPDF, rotation: -3, yOffset: -6),
            Tool(id: "Split", icon: "square.split.2x1", tint: .dsDocumentPDF, rotation: 4, yOffset: -6),
            Tool(id: "Sign", icon: "signature", tint: .dsDocumentImage, rotation: 11, yOffset: 10),
        ]
    }

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: -10) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        badge(tool, index: index, wavePhase: 0)
                    }
                }
            } else {
                // `TimelineView(.animation)` drives a real per-badge phase
                // offset (`index * .55` radians) from one shared clock —
                // genuine staggered wave motion, not 4 independent timers
                // pretending to be one (an earlier draft here used a single
                // shared toggle for every badge, which is NOT a wave, just
                // a uniform bob with an inaccurate comment claiming
                // otherwise — caught before shipping).
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: -10) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                            let phase = sin(t * 1.6 + Double(index) * 0.55)
                            badge(tool, index: index, wavePhase: phase)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .task(id: isActive) {
            guard isActive else { return }
            await runEntrance()
        }
    }

    private func badge(_ tool: Tool, index: Int, wavePhase: Double) -> some View {
        VStack(spacing: 6) {
            Image(systemName: tool.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tool.tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: tool.tint.opacity(0.35), radius: 10, y: 6)

            Text(tool.id)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OnboardingColors.textSecondary)
        }
        .rotationEffect(.degrees(tool.rotation))
        .offset(y: tool.yOffset + CGFloat(wavePhase) * 6)
        .scaleEffect(hasEntered || reduceMotion ? 1.0 : 0.4)
        .opacity(hasEntered || reduceMotion ? 1.0 : 0.0)
        // Per-badge delay is what actually makes the fan-in staggered — a
        // single `withAnimation` around one shared `hasEntered` flip (the
        // earlier draft) animates every badge in lockstep despite reading
        // as "staggered" in code; the delay has to live on each badge's own
        // `.animation` modifier instead.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.08), value: hasEntered)
    }

    // MARK: - Entrance (staggered fan-in on isActive)

    private func runEntrance() async {
        guard !reduceMotion else {
            hasEntered = true
            return
        }
        hasEntered = false
        try? await Task.sleep(nanoseconds: 120_000_000)
        hasEntered = true
    }
}

#Preview("Tools Hero") {
    ZStack {
        Color.dsBackgroundPrimary
        OnboardingToolsHero(isActive: true)
    }
    .ignoresSafeArea()
}
