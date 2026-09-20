import SwiftUI

/// SwiftUI-native hero for S1 ("Edit Office files anywhere"). Replaces the
/// static `OnboardingEditOffice` PNG — that asset's actual content (a
/// convert-arrows + signature cluster) matched S2's "every tool" pitch, not
/// S1's "editing" one; swapping in a real composition here also unlocks the
/// animation the user asked for, same reasoning `OnboardingTrackDocumentsHero`
/// already established for S3.
///
/// Composition: a document card with lines that "type in" (staggered width
/// reveal + a persistent blinking cursor), orbited by 3 small badges in the
/// app's own real document-type colors (`dsDocumentWord`/`Spreadsheet`/
/// `Presentation`) — "every format, one editor," and the literal
/// "animation running around it" the user asked for.
struct OnboardingEditHero: View {
    /// Re-triggers the typing reveal every time this page becomes current
    /// again (matches `OnboardingPageView`'s reveal timing) — passed down
    /// rather than observed independently so both animations stay in sync.
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var typedLineCount = 0
    @State private var cursorVisible = true
    @State private var orbitAngle = Angle.degrees(0)

    private let lineWidths: [CGFloat] = [64, 58, 60, 46]

    var body: some View {
        ZStack {
            orbitingBadges
            documentCard
        }
        .frame(height: 260)
        .accessibilityHidden(true)
        .task(id: isActive) {
            guard isActive else { return }
            await runTypingReveal()
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                orbitAngle = .degrees(360)
            }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - Typing reveal

    /// Reveals `lineWidths` one at a time, then holds — a full-width final
    /// line ends with a blinking cursor for as long as the page is visible.
    /// Reduce Motion skips straight to "fully typed" (no lines popping in).
    private func runTypingReveal() async {
        guard !reduceMotion else {
            typedLineCount = lineWidths.count
            return
        }
        typedLineCount = 0
        for index in lineWidths.indices {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                typedLineCount = index + 1
            }
        }
    }

    // MARK: - Document card

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            cardHeader

            VStack(alignment: .leading, spacing: 7) {
                ForEach(lineWidths.indices, id: \.self, content: lineRow)
            }

            Spacer(minLength: 0)

            toolbarRow
        }
        .padding(DSSpacing.md)
        .frame(width: 148, height: 190)
        .background(cardSurface)
        .overlay(topHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Text("W")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.dsDocumentWord, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Capsule().fill(Color.dsTextTertiary.opacity(0.5))
                .frame(width: 46, height: 5)

            Spacer(minLength: 0)
        }
    }

    /// Extracted from `documentCard`'s `ForEach` body — the inline version
    /// (conditional cursor + 3 chained `.frame`/`.clipped` modifiers inside a
    /// closure) hit this project's known "unable to type-check this
    /// expression in reasonable time" ceiling (same class of error as
    /// Session 7's `ScanFlowView`/`Group{if/switch}` cases — see
    /// `project_word_office_implementation` memory). A `@ViewBuilder`
    /// function isolates the type-checker's scope per call, same fix
    /// pattern used there.
    @ViewBuilder
    private func lineRow(_ index: Int) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(Color.dsTextPrimary.opacity(index == 0 ? 0.75 : 0.35))
                .frame(width: lineWidths[index], height: index == 0 ? 7 : 5)
                .frame(maxWidth: typedLineCount > index ? lineWidths[index] : 0, alignment: .leading)
                .clipped()

            if typedLineCount == index + 1 {
                Capsule()
                    .fill(Color.dsBrandPrimary)
                    .frame(width: 2, height: index == 0 ? 9 : 7)
                    .opacity(cursorVisible ? 1 : 0)
            }
        }
    }

    private static let toolbarIcons = ["bold.italic.underline", "textformat", "list.bullet"]

    private var toolbarRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.toolbarIcons, id: \.self) { symbolName in
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(width: 20, height: 20)
                    .background(Color.dsSurfaceSecondary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }

    /// Same two-tone + top-sheen + lit-from-above border recipe as
    /// `OnboardingTrackDocumentsHero.cardSurface` — reused verbatim so every
    /// onboarding "document card" in this feature reads as one material.
    private var cardSurface: some View {
        LinearGradient(
            colors: [Color.dsSurfacePrimary, Color.dsBackgroundElevated],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var topHighlight: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42)
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.9), Color.dsBorderSubtle.opacity(0.5)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Orbiting badges

    /// 3 badges (Word/Excel/PowerPoint) spaced 120° apart, all offset by the
    /// same continuously-increasing `orbitAngle` — "every format, one
    /// editor" and the animation running around the card the user asked for.
    private var orbitingBadges: some View {
        ZStack {
            orbitBadge(letter: "W", color: .dsDocumentWord, baseAngle: 0)
            orbitBadge(letter: "X", color: .dsDocumentSpreadsheet, baseAngle: 120)
            orbitBadge(letter: "P", color: .dsDocumentPresentation, baseAngle: 240)
        }
    }

    private func orbitBadge(letter: String, color: Color, baseAngle: Double) -> some View {
        let angle = Angle.degrees(baseAngle) + orbitAngle
        let radius: CGFloat = 108
        return Text(letter)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
            .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius * 0.55)
    }
}

#Preview("Edit Hero") {
    ZStack {
        Color.dsBackgroundPrimary
        OnboardingEditHero(isActive: true)
    }
    .ignoresSafeArea()
}
