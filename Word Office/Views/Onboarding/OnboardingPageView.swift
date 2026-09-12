import SwiftUI

/// A single onboarding page — hero art floating directly on the shared dark
/// background, with the headline + subtitle underneath. The CTA footer
/// (indicator + primary + secondary buttons) lives on the container so it
/// stays anchored across page swipes.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // S2 badge animations
    @State private var badgesRevealed = false
    @State private var splitFloat = false
    @State private var mergeFloat = false

    // S4 has a taller text block (title + subtitle + privacy chip) so give
    // it a shorter hero slot so the total page height stays balanced.
    private var heroMaxHeight: CGFloat {
        page.id == .chooseFolder ? 310 : 370
    }

    var body: some View {
        VStack(spacing: 0) {
            heroCard
                .frame(maxWidth: .infinity, maxHeight: heroMaxHeight, alignment: .top)
                .modifier(HeroBobModifier(enabled: !reduceMotion, phaseSeed: page.id))
                .scaleEffect(revealScale)
                .opacity(revealOpacity)
                .offset(y: revealOffset)
                .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.78), value: isActive)

            VStack(spacing: DSSpacing.sm) {
                textBlock

                if page.showsPrivacyChip {
                    privacyChip
                        .padding(.top, DSSpacing.xs)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, (page.id == .editOffice || page.id == .tools) ? DSSpacing.xxl : DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        page.showsPrivacyChip
            ? "\(page.title). \(page.subtitle). On-device only. Encrypted at rest. Revoke anytime in Settings."
            : "\(page.title). \(page.subtitle)"
    }

    private var revealScale: CGFloat { reduceMotion ? 1.0 : (isActive ? 1.0 : 0.92) }
    private var revealOpacity: Double { reduceMotion ? 1.0 : (isActive ? 1.0 : 0.4) }
    private var revealOffset: CGFloat { reduceMotion ? 0 : (isActive ? 0 : 24) }

    // MARK: - Hero

    private var heroCard: some View { heroContent }

    @ViewBuilder
    private var heroContent: some View {
        switch page.id {
        case .editOffice:
            ZStack {
                Image(page.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: heroMaxHeight, alignment: .top)
                    .clipped()
                if !reduceMotion {
                    S1SparkleOverlay(isActive: isActive)
                }
            }

        case .tools:
            ZStack {
                Image(page.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: heroMaxHeight, alignment: .top)
                    .clipped()

                ZStack {
                    // Split — pushed toward top, clears the image icons
                    toolBadge(icon: "square.split.2x1", label: "Split")
                        .offset(y: splitFloat ? -14 : 8)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                            value: splitFloat
                        )
                        .offset(x: 110, y: -175)
                        .scaleEffect(badgesRevealed ? 1.0 : 0.15)
                        .opacity(badgesRevealed ? 1.0 : 0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.58).delay(0.12),
                            value: badgesRevealed
                        )

                    // Merge — pushed toward bottom
                    toolBadge(icon: "doc.on.doc.fill", label: "Merge")
                        .offset(y: mergeFloat ? 10 : -8)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                            value: mergeFloat
                        )
                        .offset(x: -110, y: 155)
                        .scaleEffect(badgesRevealed ? 1.0 : 0.15)
                        .opacity(badgesRevealed ? 1.0 : 0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.58).delay(0.28),
                            value: badgesRevealed
                        )
                }
            }
            .onAppear {
                if isActive { badgesRevealed = true }
                splitFloat = true
                mergeFloat = true
            }
            .onChange(of: isActive) { _, active in
                badgesRevealed = active
            }

        case .trackDocuments:
            ZStack {
                Image(page.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: heroMaxHeight, alignment: .top)
                    .clipped()
                S3StatusOverlay(isActive: isActive)
            }

        case .chooseFolder:
            Image(page.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: heroMaxHeight, alignment: .top)
                .clipped()
        }
    }

    private func toolBadge(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.dsDocumentPDF.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.dsDocumentPDF.opacity(0.40), radius: 12, y: 6)

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingColors.textSecondary)
        }
    }

    // MARK: - Text block

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

    private var privacyChip: some View {
        VStack(alignment: .leading, spacing: 6) {
            privacyRow(text: "Stored only on your device")
            privacyRow(text: "Encrypted at rest")
            privacyRow(text: "Revoke folder access anytime in Settings")
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OnboardingColors.success.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingColors.success.opacity(0.22), lineWidth: 0.6)
        }
    }

    private func privacyRow(text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OnboardingColors.success)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingColors.success)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - S1 sparkle particles

private struct S1SparkleOverlay: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false
    @State private var floatA   = false
    @State private var floatB   = false
    @State private var floatC   = false

    // (x, y, size, amplitude, floatDuration)
    private let configs: [(x: CGFloat, y: CGFloat, size: CGFloat, amp: CGFloat, dur: Double)] = [
        ( 126, -132, 18, 12.0, 2.60),
        (-148,  -14, 13,  9.0, 3.10),
        ( 142,  108, 15, 11.0, 2.85),
    ]

    var body: some View {
        ZStack {
            // Sparkle A
            Image(systemName: "sparkle")
                .font(.system(size: configs[0].size, weight: .semibold))
                .foregroundStyle(Color(hue: 0.11, saturation: 0.85, brightness: 1.0))
                .shadow(color: .orange.opacity(0.45), radius: 6)
                .offset(y: floatA ? -configs[0].amp : configs[0].amp * 0.4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: configs[0].dur).repeatForever(autoreverses: true),
                    value: floatA
                )
                .offset(x: configs[0].x, y: configs[0].y)

            // Sparkle B
            Image(systemName: "sparkle")
                .font(.system(size: configs[1].size, weight: .semibold))
                .foregroundStyle(Color(hue: 0.11, saturation: 0.85, brightness: 1.0))
                .shadow(color: .orange.opacity(0.45), radius: 6)
                .offset(y: floatB ? -configs[1].amp : configs[1].amp * 0.4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: configs[1].dur).repeatForever(autoreverses: true),
                    value: floatB
                )
                .offset(x: configs[1].x, y: configs[1].y)

            // Sparkle C
            Image(systemName: "sparkle")
                .font(.system(size: configs[2].size, weight: .semibold))
                .foregroundStyle(Color(hue: 0.11, saturation: 0.85, brightness: 1.0))
                .shadow(color: .orange.opacity(0.45), radius: 6)
                .offset(y: floatC ? -configs[2].amp : configs[2].amp * 0.4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: configs[2].dur).repeatForever(autoreverses: true),
                    value: floatC
                )
                .offset(x: configs[2].x, y: configs[2].y)
        }
        .scaleEffect(revealed ? 1.0 : 0.08)
        .opacity(revealed ? 1.0 : 0.0)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: revealed)
        .onAppear {
            guard isActive else { return }
            revealed = true
            // Stagger float start so they don't all move in sync
            floatA = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { floatB = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { floatC = true }
        }
        .onChange(of: isActive) { _, active in
            if active {
                revealed = true
                floatA = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { floatB = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { floatC = true }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { revealed = false }
            }
        }
    }
}

// MARK: - S3 status pill overlay

/// Three animated status pills (DRAFT → REVIEWED → SIGNED) placed along the
/// right margin of the S3 image — outside the white card but alongside the
/// existing timeline column in the PNG. The highlighted pill cycles top→bottom,
/// creating a "running down to signed" flow.
private struct S3StatusOverlay: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false
    @State private var currentPhase = 0

    var body: some View {
        ZStack {
            statusPill(label: "DRAFT",    icon: "doc",                tint: Color(white: 0.42), bg: Color(white: 0.88), x: 148, y: -100, active: currentPhase == 0)
            statusPill(label: "REVIEWED", icon: "checkmark",           tint: .blue,             bg: .blue.opacity(0.12), x: 148, y:    0, active: currentPhase == 1)
            statusPill(label: "SIGNED",   icon: "checkmark.seal.fill", tint: .green,            bg: .green.opacity(0.12),x: 148, y:  100, active: currentPhase == 2)
        }
        .scaleEffect(revealed ? 1.0 : 0.1)
        .opacity(revealed ? 1.0 : 0.0)
        .onAppear {
            if isActive { withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.1)) { revealed = true } }
        }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.1)) { revealed = true }
            } else {
                withAnimation(.easeOut(duration: 0.18)) { revealed = false }
                currentPhase = 0
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            guard !reduceMotion else { currentPhase = 2; return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) { currentPhase = 0 }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) { currentPhase = 1 }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) { currentPhase = 2 }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
            }
        }
    }

    private func statusPill(label: String, icon: String, tint: Color, bg: Color,
                             x: CGFloat, y: CGFloat, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.3)
        }
        .foregroundStyle(active ? tint : tint.opacity(0.35))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? bg : bg.opacity(0.45), in: Capsule())
        .overlay { Capsule().strokeBorder(active ? tint.opacity(0.28) : tint.opacity(0.08), lineWidth: 0.5) }
        .shadow(color: active ? tint.opacity(0.38) : .clear, radius: 10)
        .scaleEffect(active ? 1.06 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: active)
        .offset(x: x, y: y)
    }
}

// MARK: - Hero bob animation

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

#Preview("Choose Folder") {
    ZStack {
        OnboardingAuroraBackground(page: .chooseFolder)
        OnboardingPageView(page: OnboardingPage.all[3], isActive: true)
    }
}
