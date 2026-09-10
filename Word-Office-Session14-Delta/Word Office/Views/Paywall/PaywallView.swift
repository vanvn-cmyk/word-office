import SwiftUI

/// Premium paywall — presented from `LibraryView.premiumButton` (previously
/// a `TODO(paywall)` placeholder with no destination). Layout/copy match the
/// mockup the user supplied; per their explicit note, plan selection stays a
/// local, unwired placeholder for now ("gói thì cứ để thế đã") — no real
/// StoreKit products, no prices shown (the mockup itself doesn't show any),
/// and Continue/Restore have no destination yet, same TODO pattern as the
/// Settings "Rate app"/"Explore Premium" entries elsewhere in this app.
///
/// No `NavigationStack` — this is presented as a sheet with its own custom
/// close button (top-right X), not a pushed screen with a system back
/// button.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: Plan = .yearly

    /// Not real Terms/Privacy pages yet — same situation as
    /// `SettingsView.privacyPolicyURL`/`termsOfServiceURL` (app hasn't
    /// shipped). Kept as a separate, local optional here rather than shared
    /// state with `SettingsView`, since neither is wired to a real value yet
    /// — wire both from one shared source once a real URL exists.
    private let termsURL: URL? = nil
    private let privacyURL: URL? = nil

    private enum Plan: String, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case yearly = "Yearly"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PaywallHeroHeader(onRestore: restorePurchases, onClose: { dismiss() })

                VStack(spacing: DSSpacing.xl) {
                    VStack(spacing: DSSpacing.xs) {
                        Text("Your Office, Upgraded")
                            .font(DSFont.largeTitle)
                            .foregroundStyle(Color.dsTextPrimary)
                            .multilineTextAlignment(.center)
                        Text("Professional tools, made for you")
                            .font(DSFont.body)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    .padding(.top, DSSpacing.xl)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                        PaywallFeatureRow(title: "Edit Office Files")
                        PaywallFeatureRow(title: "PDF Tools")
                        PaywallFeatureRow(title: "Scan & OCR")
                        PaywallFeatureRow(title: "Sign Documents")
                    }

                    VStack(spacing: DSSpacing.sm) {
                        ForEach(Plan.allCases) { plan in
                            PaywallPlanRow(
                                title: plan.rawValue,
                                isSelected: selectedPlan == plan,
                                showsBestValue: plan == .yearly
                            ) {
                                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.2)) {
                                    selectedPlan = plan
                                }
                            }
                        }
                    }

                    DSPrimaryButton(title: "Continue") {
                        // TODO(paywall): no destination yet — wire once real
                        // StoreKit products exist for `selectedPlan`.
                    }

                    footerLinks
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.lg)
            }
        }
        .background(Color.dsBackgroundPrimary)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var footerLinks: some View {
        HStack(spacing: DSSpacing.sm) {
            footerLink("Terms", url: termsURL)
            Text("·").foregroundStyle(Color.dsTextTertiary)
            footerLink("Privacy", url: privacyURL)
            Text("·").foregroundStyle(Color.dsTextTertiary)
            Button("Restore Purchases", action: restorePurchases)
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
        }
        .font(DSFont.caption)
    }

    @ViewBuilder
    private func footerLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
        } else {
            Text(title)
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
        }
    }

    private func restorePurchases() {
        // TODO(paywall): no destination yet — wire to `AppStore.sync()`
        // (StoreKit 2) once real products exist.
    }
}

/// Gradient hero header — the illustration is a designed raster asset
/// (`Assets.xcassets/PaywallHeroIllustration`, cropped from the source the
/// user supplied to trim a residual checkerboard-transparency artifact, same
/// class of issue as `SettingsPremiumBanner`'s first export). The gradient
/// itself, unlike that banner, IS drawn natively here rather than baked into
/// a raster — its two colors are sampled directly from
/// `SettingsPremiumBanner`'s own gradient (not invented) so the "upgrade to
/// premium" visual language matches between Settings and this paywall.
private struct PaywallHeroHeader: View {
    let onRestore: () -> Void
    let onClose: () -> Void

    private let heroAspectRatio: CGFloat = 1668.0 / 943.0
    private let gradientStart = Color(red: 0 / 255, green: 90 / 255, blue: 235 / 255)
    private let gradientEnd = Color(red: 176 / 255, green: 109 / 255, blue: 252 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [gradientStart, gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft glow highlight — same "light source" idea as
            // `LibraryView.premiumButton`'s ring / `ToolsTabView.IconBadge`,
            // scaled up. The previous attempt (`.screen` blend at 0.9
            // opacity) lightened almost the whole hero toward pale lavender
            // instead of staying a localized highlight — `.screen` on white
            // pushes very aggressively toward white even at partial opacity.
            // Plain normal blending at a modest opacity keeps it subtle.
            RadialGradient(
                colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                center: UnitPoint(x: 0.28, y: 0.16),
                startRadius: 10,
                endRadius: 220
            )

            Image("PaywallHeroIllustration")
                .resizable()
                .aspectRatio(heroAspectRatio, contentMode: .fit)
                .padding(.horizontal, DSSpacing.xxl)
                .padding(.top, DSSpacing.huge)
                .padding(.bottom, DSSpacing.lg)

            // Soft fade into the page background instead of a hard-edged
            // rectangle cutoff. Starting the fade at 0.6 (60% down) ate up
            // too much of the hero in pale color — the reference keeps the
            // blue/purple vivid for most of the height and only fades in a
            // short strip right at the bottom.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.8),
                    .init(color: Color.dsBackgroundPrimary, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Button("Restore", action: onRestore)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.25), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.sm)
        }
        .frame(height: 340)
        .ignoresSafeArea(edges: .top)
    }
}

/// One 2×2 feature-grid cell — a filled checkmark bullet + label. The
/// mockup uses the same generic checkmark for all four (not a distinct icon
/// per feature), so this takes only a title, no icon parameter.
private struct PaywallFeatureRow: View {
    let title: String

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle().fill(Color.dsBrandPrimary)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            Text(title)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One selectable plan row (Weekly / Yearly). A real `Button`, not a tap
/// gesture on the row `HStack`, so it gets standard focus/press handling for
/// free — see `/swiftui-expert-skill` accessibility guidance applied
/// throughout Settings this session.
private struct PaywallPlanRow: View {
    let title: String
    let isSelected: Bool
    let showsBestValue: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault)

                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)

                Spacer(minLength: DSSpacing.sm)

                if showsBestValue {
                    Text("BEST VALUE")
                        .font(DSFont.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(Color.dsBrandPrimary, in: Capsule())
                }
            }
            .padding(DSSpacing.md)
            .background(isSelected ? Color.dsBrandPrimarySubtle : Color.dsSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                    .strokeBorder(isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    PaywallView()
}
