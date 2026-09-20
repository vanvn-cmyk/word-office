import SwiftUI

/// Word Office Premium paywall — MVP variant (a hardcoded stand-in for
/// `iap_v1` in `product-strategy-master.md`). Presented as a sheet from
/// the crown `PremiumButton` on both `LibraryView` and `ToolsTabView`;
/// StoreKit wiring is stubbed inside `PaywallViewModel`. Layout is one
/// scrollable pane so Dynamic Type and small devices don't clip.
///
/// Sections top to bottom:
///   • Dismiss chevron top-trailing (avoids Liquid Glass capsule wrap
///     the way `PremiumButton` already does app-wide).
///   • Hero — gold gradient panel with a crown badge + product title.
///   • Value props — five short, action-oriented bullets that pull from
///     the strategy doc's Pillar list.
///   • Offer picker — two tappable pricing cards, yearly preselected.
///   • CTA — full-width Liquid Glass button whose label switches on VM
///     state (idle / purchasing / restoring / succeeded / failed).
///   • Footer — Restore + Terms / Privacy legal line.
///
/// Success and failure states dismiss on next runloop hop so the view
/// stays unaware of the presenting screen's cleanup work.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PaywallViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    hero
                    valueProps
                    offerPicker
                    ctaColumn
                    footer
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxl)
            }
            .background(Color.dsBackgroundPrimary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.dsTextSecondary)
                            .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                    }
                    .accessibilityLabel("Close paywall")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.status) { _, new in
            if new == .succeeded {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    dismiss()
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: DSSpacing.sm) {
            crownGlyph
                .padding(.top, DSSpacing.sm)
            Text("Word Office Premium")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)
            Text("Every tool unlocked. No ads. On-device by default.")
                .font(DSFont.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.lg)
        .background(
            LinearGradient(
                colors: [
                    Color.dsPremiumGoldStart.opacity(0.16),
                    Color.dsPremiumGoldEnd.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                .strokeBorder(Color.dsPremiumGoldEnd.opacity(0.35), lineWidth: 0.75)
        )
    }

    /// Larger cousin of `PremiumButton`'s badge — same gradient recipe so
    /// the crown reads as the same "purchase" glyph the crown button
    /// promises. Rendered inline (no touch target) since the hero panel
    /// isn't itself a button.
    private var crownGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.dsPremiumGoldStart, Color.dsPremiumGoldEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .shadow(color: Color.dsPremiumGoldEnd.opacity(0.35), radius: 14, y: 6)
            Image(systemName: "crown.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Value props

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ForEach(Self.valueBullets, id: \.self) { line in
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.dsPremiumGoldEnd)
                    Text(line)
                        .font(DSFont.body)
                        .foregroundStyle(Color.dsTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .strokeBorder(Color.dsBorderSubtle.opacity(0.6), lineWidth: 0.5)
        )
    }

    private static let valueBullets: [String] = [
        "Unlimited documents across Word, Excel, PowerPoint, PDF",
        "Merge, Split, Convert, Compress — every PDF tool unlocked",
        "Scan & OCR to editable text, on-device",
        "Fill forms and sign PDFs without watermarks",
        "iCloud sync, Files provider, and no ads ever"
    ]

    // MARK: - Offer picker

    private var offerPicker: some View {
        VStack(spacing: DSSpacing.sm) {
            ForEach(viewModel.offers) { offer in
                OfferCard(
                    offer: offer,
                    isSelected: viewModel.selectedOfferID == offer.id
                ) {
                    viewModel.selectedOfferID = offer.id
                }
            }
        }
    }

    // MARK: - CTA + status

    private var ctaColumn: some View {
        VStack(spacing: DSSpacing.sm) {
            Button {
                Task { await viewModel.purchase() }
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.dsTextOnBrand)
                    }
                    Text(viewModel.ctaLabel)
                        .font(DSFont.headline.weight(.semibold))
                        .foregroundStyle(Color.dsTextOnBrand)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.dsBrandPrimary, Color.dsBrandPrimaryPressed],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                )
                .shadow(color: Color.dsBrandPrimary.opacity(0.28), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.dsBrandPrimary).interactive(), in: .rect(cornerRadius: DSRadius.large))
            .disabled(viewModel.isBusy || viewModel.selectedOffer == nil)
            .accessibilityLabel(viewModel.ctaLabel)

            if case .failed(let message) = viewModel.status {
                Text(message)
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsStatusError)
                    .multilineTextAlignment(.center)
                    .onTapGesture { viewModel.clearError() }
                    .accessibilityHint("Tap to dismiss")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DSSpacing.xs) {
            Button {
                Task { await viewModel.restore() }
            } label: {
                Text("Restore Purchases")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.dsBrandPrimary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy)

            Text("Subscriptions auto-renew until cancelled. See Terms and Privacy Policy in Settings.")
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.md)
        }
    }
}

// MARK: - Offer card

/// One row in the offer picker — tappable, selection-styled. Kept
/// private since it only makes sense next to the paywall VM.
private struct OfferCard: View {
    let offer: PaywallViewModel.Offer
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: DSSpacing.sm) {
                selectionCircle
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack(spacing: DSSpacing.xs) {
                        Text(offer.title)
                            .font(DSFont.headline.weight(.semibold))
                            .foregroundStyle(Color.dsTextPrimary)
                        if let highlight = offer.highlight {
                            Text(highlight)
                                .font(DSFont.caption.weight(.bold))
                                .foregroundStyle(Color.dsTextOnBrand)
                                .padding(.horizontal, DSSpacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: [Color.dsPremiumGoldStart, Color.dsPremiumGoldEnd],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: Capsule()
                                )
                        }
                    }
                    if let line = offer.secondaryLine {
                        Text(line)
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: DSSpacing.sm)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(offer.price)
                        .font(DSFont.headline.weight(.bold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(offer.period)
                        .font(DSFont.caption)
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .padding(DSSpacing.md)
            .background(
                Color.dsBackgroundElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.dsBrandPrimary : Color.dsBorderSubtle.opacity(0.7),
                        lineWidth: isSelected ? 2 : 0.75
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.04), radius: isSelected ? 10 : 4, y: isSelected ? 4 : 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var selectionCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault, lineWidth: 2)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(Color.dsBrandPrimary)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}
