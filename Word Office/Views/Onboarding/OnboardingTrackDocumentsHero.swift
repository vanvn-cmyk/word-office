import SwiftUI

/// SwiftUI-native hero for S3 ("Stay on top of every document"). Replaces the
/// pre-baked PNG so it renders sharp on every scale, adapts to Dark Mode via
/// DS tokens, and reuses the app's own 3D document icon assets
/// (`DocumentIconWord` / `Spreadsheet` / `PDF`) so the onboarding preview
/// matches what users will see inside Library.
///
/// Composition:
/// - Left card (list of 3 rows: header + Word/Excel/PDF, each with a status pill).
/// - Right timeline column (3 state badges connected by a gradient rail).
///
/// The card and timeline overlap by ~18pt (negative HStack spacing) so the
/// timeline sits half-on, half-off the card — same depth trick as the mockup.
struct OnboardingTrackDocumentsHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: -8) {
            listCard
                .zIndex(0)
            timelineColumn
                .padding(.top, 40)
                .zIndex(1)
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .accessibilityHidden(true)
    }

    // MARK: - List card

    private var listCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            cardHeader
                .padding(.bottom, 2)

            documentRow(
                assetName: "DocumentIconWord",
                status: .draft
            )
            documentRow(
                assetName: "DocumentIconSpreadsheet",
                status: .reviewed
            )
            documentRow(
                assetName: "DocumentIconPDF",
                status: .signed
            )
        }
        .padding(DSSpacing.md)
        .background(cardSurface)
        .overlay(topHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 26, y: 14)
        .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
    }

    /// Two-tone panel — top slightly whiter than bottom so the card reads as
    /// lit-from-above rather than a flat rectangle. Kept subtle enough that
    /// Dark Mode still resolves cleanly through the DS tokens.
    private var cardSurface: some View {
        LinearGradient(
            colors: [
                Color.dsSurfacePrimary,
                Color.dsBackgroundElevated
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// A soft glossy sheen along the top ~35% of the card. Matches the way
    /// real glass surfaces catch overhead light — pairs with the
    /// `cardSurface` two-tone to sell material depth without a full glass
    /// effect (which we save for Liquid Glass surfaces elsewhere).
    private var topHighlight: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.white.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.42)
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Border that's brighter at the top, fading down — reinforces the
    /// lit-from-above sheen so the whole card reads as one cohesive material.
    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.9),
                Color.dsBorderSubtle.opacity(0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Header placeholder — a small brand-tinted document icon plus two
    /// tone bars. Reads as "a document list" without needing real text so
    /// the eye focuses on the status column.
    private var cardHeader: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "list.bullet.rectangle.portrait.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 22, height: 22)
                .background(Color.dsBrandPrimarySubtle, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.dsTextPrimary.opacity(0.72))
                    .frame(width: 110, height: 7)
                Capsule().fill(Color.dsTextTertiary.opacity(0.5))
                    .frame(width: 66, height: 5)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Document row

    private func documentRow(assetName: String, status: DocumentStatus) -> some View {
        HStack(spacing: DSSpacing.xs) {
            // The app's actual 3D document icon (Word/Excel/PDF). Rendering
            // mode `.original` preserves full color; interpolation stays
            // sharp at this small size because the asset is high-res.
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.dsTextPrimary.opacity(0.6))
                    .frame(width: 60, height: 5)
                Capsule().fill(Color.dsTextTertiary.opacity(0.45))
                    .frame(width: 40, height: 4)
            }

            Spacer(minLength: 2)

            statusPill(status)
        }
    }

    // MARK: - Status pill

    private enum DocumentStatus {
        case draft, reviewed, signed
    }

    private func statusPill(_ status: DocumentStatus) -> some View {
        let (label, tint, bg, icon) = pillContents(for: status)
        return HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.35)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bg, in: Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.14), lineWidth: 0.5)
        }
    }

    /// Tuple: label, foreground tint, background fill, leading SF-Symbol.
    /// Draft has no leading icon (the neutral state); reviewed and signed
    /// each carry a check for stronger positive affordance.
    private func pillContents(for status: DocumentStatus) -> (String, Color, Color, String?) {
        switch status {
        case .draft:
            return ("DRAFT",
                    Color.dsTextSecondary,
                    Color.dsSurfaceSecondary,
                    nil)
        case .reviewed:
            return ("REVIEWED",
                    Color.dsBrandPrimary,
                    Color.dsBrandPrimarySubtle,
                    "checkmark")
        case .signed:
            return ("SIGNED",
                    Color.dsStatusSuccess,
                    Color.dsStatusSuccessBackground,
                    "checkmark.seal.fill")
        }
    }

    // MARK: - Timeline column (right side)

    /// Vertical timeline of the three states. Connectors use a top-to-bottom
    /// gradient (grey → blue → green) so the eye follows the sequence
    /// naturally. The final "signed" badge carries a soft green ambient
    /// glow — the aha state, echoing the app's success semantics.
    private var timelineColumn: some View {
        VStack(spacing: 4) {
            timelineBadge(kind: .empty)
            connector(from: .dsBorderSubtle, to: .dsBrandPrimarySubtle)
            timelineBadge(kind: .reviewed)
            connector(from: .dsBrandPrimarySubtle, to: .dsStatusSuccessBackground)
            timelineBadge(kind: .signed)
        }
    }

    private func connector(from top: Color, to bottom: Color) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [top, bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.5, height: 22)
    }

    private enum TimelineBadgeKind {
        case empty, reviewed, signed
    }

    private func timelineBadge(kind: TimelineBadgeKind) -> some View {
        ZStack {
            Circle()
                .fill(badgeFill(kind))

            Circle()
                .strokeBorder(badgeBorder(kind), lineWidth: 1)

            badgeIcon(kind)
        }
        .frame(width: 44, height: 44)
        .shadow(color: badgeGlow(kind), radius: 10, y: 0)
        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 3)
    }

    @ViewBuilder
    private func badgeIcon(_ kind: TimelineBadgeKind) -> some View {
        switch kind {
        case .empty:
            Image(systemName: "doc")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsTextSecondary)
        case .reviewed:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.dsBrandPrimary)
        case .signed:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.dsStatusSuccess)
        }
    }

    private func badgeFill(_ kind: TimelineBadgeKind) -> Color {
        switch kind {
        case .empty:    return Color.dsSurfacePrimary
        case .reviewed: return Color.dsBrandPrimarySubtle
        case .signed:   return Color.dsStatusSuccessBackground
        }
    }

    private func badgeBorder(_ kind: TimelineBadgeKind) -> Color {
        switch kind {
        case .empty:    return Color.dsBorderSubtle
        case .reviewed: return Color.dsBrandPrimary.opacity(0.35)
        case .signed:   return Color.dsStatusSuccess.opacity(0.35)
        }
    }

    /// Ambient glow behind each badge. Signed gets the strongest glow —
    /// it's the "aha" endpoint of the flow, and the extra green wash sells
    /// completion. Empty stays neutral.
    private func badgeGlow(_ kind: TimelineBadgeKind) -> Color {
        switch kind {
        case .empty:    return Color.black.opacity(0)
        case .reviewed: return Color.dsBrandPrimary.opacity(0.15)
        case .signed:   return Color.dsStatusSuccess.opacity(0.30)
        }
    }
}

#Preview("Track Documents Hero") {
    ZStack {
        Color.dsBackgroundPrimary
        OnboardingTrackDocumentsHero()
    }
    .ignoresSafeArea()
}
