import SwiftUI

/// Premium paywall — presented from `LibraryView.premiumButton` (previously
/// a `TODO(paywall)` placeholder with no destination). Per user's explicit
/// note, plan selection stays a local, unwired placeholder for now — price
/// is a loading skeleton (`PriceSkeleton`) rather than invented text, since
/// no real StoreKit products exist yet, and Continue/Restore have no
/// destination, same TODO pattern as the Settings "Rate app"/"Explore
/// Premium" entries elsewhere in this app.
///
/// Layout: full-screen blue-gradient background with the hero content
/// (illustration + title + subtitle + benefit list) painted directly on
/// it in white, then a white rounded-top decision card overlapping the
/// bottom (plan picker + Continue + trust + footer). Apple Music Family
/// / Duolingo Super pattern — the entire screen reads as a single premium
/// surface instead of a hero+body split. Fits one screen without
/// scrolling by design; the ZStack + VStack skeleton distributes hero
/// content in the top half and pins the decision card to the bottom.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// When non-nil (onboarding context), a "Start for free →" link is shown
    /// immediately inside the bottom card so the user can skip without waiting
    /// for the 3-second close button.
    var onContinueForFree: (() -> Void)? = nil

    @State private var vm = PaywallViewModel()
    // Yearly selected by default — higher value, most apps highlight the annual plan.
    @State private var selectedPlan: Plan = .yearly

    /// Close X visibility. Starts `false` on every fresh present so the
    /// user reads the hero for a beat before an exit affordance appears
    /// (~3s engagement window — same shape Duolingo Super / Headspace /
    /// YouTube Premium use). Conditional `if showCloseButton` removes the
    /// button from the hierarchy entirely while hidden — VoiceOver never
    /// announces a control that isn't there.
    @State private var showCloseButton = false
    private let showCloseDelay: Duration = .seconds(3)

    /// Container height — measured via onGeometryChange so heroContent can
    /// reduce the illustration height on short screens and prevent the 4th
    /// benefit from being clipped by the bottom card.
    @State private var containerHeight: CGFloat = 812

    /// True for non-iPad screens shorter than 740pt (iPhone SE & mini family).
    /// Drives tighter spacing and a shorter illustration so all 4 benefits fit.
    private var isCompact: Bool { hSizeClass != .regular && containerHeight < 740 }

    /// True for standard iPhones (740–809pt safe-area height — iPhone 16, 15, 14 family).
    /// Uses 145pt illustration instead of 195pt; the safe-area content on a 393×852pt
    /// iPhone 16 is ~764pt, leaving barely 1pt of Spacer at 195pt → subtitle clips.
    private var isMedium: Bool { hSizeClass != .regular && !isCompact && containerHeight < 810 }

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

        var productID: String {
            switch self {
            case .weekly: "com.docx.officeeditor.pdfeditor.week"
            case .yearly: "com.docx.officeeditor.pdfeditor.year"
            }
        }

        var trialBadgeText: String? {
            self == .weekly ? "3-DAY FREE" : nil
        }

        var periodCaption: String {
            switch self {
            case .weekly: "Then billed weekly"
            case .yearly: "Billed once a year"
            }
        }
    }

    var body: some View {
        // `bottomCard` back as a real sibling in the same `VStack` as
        // `heroContent` (not `.safeAreaInset`) — `.safeAreaInset` doesn't
        // actually propose a REDUCED height to non-scrolling content
        // above it; a plain `VStack` isn't safe-area-aware the way
        // `ScrollView` is, so `heroContent` kept sizing itself as if the
        // full screen were available and `bottomCard` just got drawn on
        // top, overlapping "All Tools in One Place". Putting both in one
        // `VStack` restores the mechanism proven earlier in this session
        // (the ~155pt measurement that started this whole thread): with
        // a fixed total height, VStack layout shrinks the one highly
        // flexible child (the `scaledToFit` image) to whatever's left
        // after every less-flexible sibling — title, benefit text
        // (subtitles included again below), and the card itself — takes
        // its natural size. No overlap is possible by construction,
        // whatever the illustration's resulting size turns out to be.
        ZStack(alignment: .top) {
            heroBackground

            VStack(spacing: 0) {
                heroContent
                Spacer(minLength: 0)
                bottomCard
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
        }
        .overlay(alignment: .topTrailing) {
            if showCloseButton { closeButton }
        }
        .task {
            try? await Task.sleep(for: showCloseDelay)
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) {
                showCloseButton = true
            }
        }
        .task { await vm.loadProducts() }
        .onChange(of: vm.status) { _, newStatus in
            if case .succeeded = newStatus {
                if let onContinueForFree { onContinueForFree() } else { dismiss() }
            }
        }
    }

    // MARK: - Hero background (gradient + glow, full-screen)

    /// Full-screen blue gradient + soft white glow. Extends under the
    /// status bar via `.ignoresSafeArea` so the paywall reads as one
    /// continuous premium surface top-to-bottom — the white bottom card
    /// (`bottomCard`) covers the lower portion visually, but the
    /// gradient still paints behind it in case the card's shadow
    /// reveals any pixel between.
    private var heroBackground: some View {
        ZStack {
            // 3-stop instead of the previous flat 2-color interpolation —
            // a deeper start (#0047CC) before easing into the original
            // start/end colors gives the gradient a non-linear falloff
            // (richer near the top-left, same overall hue family) instead
            // of reading as one flat, evenly-interpolated fill.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0 / 255, green: 71 / 255, blue: 204 / 255), location: 0),
                    .init(color: Color(red: 0 / 255, green: 85 / 255, blue: 230 / 255), location: 0.55),
                    .init(color: Color(red: 90 / 255, green: 155 / 255, blue: 250 / 255), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft glow highlight, top-left — same "light source" idea as
            // `LibraryView.premiumButton`'s ring / `ToolsTabView.IconBadge`,
            // scaled up. Normal blending at modest opacity keeps it a
            // localized highlight rather than washing the whole hero.
            // Nudged slightly larger/brighter than before so it still
            // reads against the now-taller hero content (subhead + 2×2
            // benefit grid pushed everything down).
            RadialGradient(
                colors: [Color.white.opacity(0.32), Color.white.opacity(0)],
                center: UnitPoint(x: 0.22, y: 0.1),
                startRadius: 10,
                endRadius: 300
            )
            .allowsHitTesting(false)

            // Subtle vignette — very light darkening toward the corners
            // so the white illustration/headline/benefit text has more
            // contrast to sit on, without the background itself calling
            // attention to the effect.
            RadialGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.14)],
                center: .center,
                startRadius: 260,
                endRadius: 520
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero content (illustration + title + benefits, white on blue)

    /// Everything above the decision card — illustration on top, title
    /// + subhead centered, then a 2×2 benefit icon grid. All rendered
    /// in white on the gradient so the hero is one unbroken
    /// visual moment instead of the earlier hero-strip + white-body
    /// split (which the user flagged as "xấu" through three iterations).
    private var heroContent: some View {
        let isPad = hSizeClass == .regular
        let compact = isCompact
        return VStack(spacing: compact ? DSSpacing.xs : DSSpacing.md) {
            Image("PaywallHeroIllustration")
                .resizable()
                .scaledToFit()
                // compact: 110pt — iPhone SE / mini (containerHeight < 740).
                // medium:  145pt — standard iPhones 14/15/16 (containerHeight 740–809).
                // default: 195pt — tall iPhones (Pro Max) and iPads.
                .frame(maxHeight: isPad ? 290 : compact ? 110 : isMedium ? 145 : 195)
                .padding(.horizontal, DSSpacing.xs)

            VStack(spacing: DSSpacing.xxs) {
                Text("Your Office, Upgraded")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    // Subtle lift off the gradient — white-on-mid-blue has
                    // enough contrast to pass a11y but reads a little flat
                    // without it; kept soft (low opacity, small radius) so
                    // it's felt, not seen as a distinct drop shadow.
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)

                Text("Professional tools, made for you")
                    .font(DSFont.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DSSpacing.lg)

            // 4 benefits as a full-width single-column list — picked
            // (option "A" of 6 mockup directions) over the 2×2 icon
            // grid, which packed every title into roughly half the
            // width and forced 2-line wraps on all four, reading dense
            // and "blocky". Full width means no title ever wraps.
            // Left-aligned, not centered — a centered icon+title+subtitle
            // block loses the scan line every real paywall list relies
            // on (Things, Fantastical, Todoist all left-align this
            // pattern). A Free-vs-Pro compare table was another option
            // raised, but that asserts specific feature-gating claims
            // (what's actually locked in Free) — skipped rather than
            // guessed; happy to build it once there's a confirmed
            // gating list. Subtitles kept in this time (removed, then
            // restored per the user's explicit request) — the
            // illustration is what absorbs the resulting space pressure,
            // per `body`'s comment.
            VStack(alignment: .leading, spacing: compact ? DSSpacing.xs : DSSpacing.md) {
                HeroBenefitRow(
                    icon: "square.and.pencil",
                    title: "Edit Office Files",
                    subtitle: "Open, edit, and convert your documents",
                    isLarge: isPad
                )
                HeroBenefitRow(
                    icon: "doc.text.viewfinder",
                    title: "Unlimited Scans",
                    subtitle: "Turn any document into a clean PDF",
                    isLarge: isPad
                )
                HeroBenefitRow(
                    icon: "checkmark.seal.fill",
                    title: "Never Lose Track",
                    subtitle: "Keep every file organized in one place",
                    isLarge: isPad
                )
                HeroBenefitRow(
                    icon: "square.grid.2x2.fill",
                    title: "All Tools in One Place",
                    subtitle: "Edit, scan, sign, and convert — no extra apps",
                    isLarge: isPad
                )
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.top, compact ? 0 : DSSpacing.xxs)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom decision card (plans + CTA + trust + footer)

    /// White rounded-top card pinned to the bottom of the paywall. Owns
    /// every actionable element — plan picker, Continue, trust row,
    /// legal footer — so the user's committed reading path is
    /// hero (learn) → card (decide). The rounded top edge + upward
    /// shadow visually lifts the card off the blue gradient so it
    /// reads as a discrete decision surface rather than the bottom
    /// half of one long screen.
    private var bottomCard: some View {
        VStack(spacing: DSSpacing.sm) {
            planPicker

            // CTA copy names the actual next action — Weekly has a
            // trial to start, Monthly doesn't, so "Continue" (generic)
            // only fits the no-trial path.
            DSPrimaryButton(title: vm.isBusy ? LocalizedStringKey(vm.ctaLabel) : (selectedPlan == .weekly ? "Start Trial Now" : "Get Yearly Access")) {
                vm.selectedOfferID = selectedPlan.productID
                Task { await vm.purchase() }
            }
            .disabled(vm.isBusy)
            // Brand-tinted glow — the button reads as the "hero
            // action" surface below the plan picker. Radius intentionally
            // wide (18pt) so the glow feels like presence, not a
            // sharp drop shadow. Reduce-motion doesn't apply
            // (visual glow, not motion).
            .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 18, y: 8)

            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "lock.fill")
                    .font(DSFont.caption)
                // Weekly carries a trial, so the trust line leads with
                // that promise; Monthly has no trial to mention.
                Text(selectedPlan == .weekly ? "3-day free trial, cancel anytime" : "Cancel anytime · Renews annually")
                    .font(DSFont.caption)
            }
            .foregroundStyle(Color.dsTextTertiary)
            .accessibilityElement(children: .combine)

            footerLinks
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.lg)
        // No explicit bottom padding — the content (unlike the
        // `.background` shape below) doesn't ignore the safe area, so
        // it already clears the home indicator automatically. The old
        // `DSSpacing.md` here was ON TOP of that automatic inset,
        // doubling up as empty space below the footer links ("ở dưới
        // vẫn thừa"). `xxs` is just a hair of intentional breathing
        // room, not a second safe-area buffer.
        .padding(.bottom, DSSpacing.xxs)
        .frame(maxWidth: .infinity)
        .background {
            // `UnevenRoundedRectangle` (iOS 16.4+) — only the top two
            // corners are rounded; the bottom hugs the physical screen
            // bottom. Radius 28 matches the shape of the app's FAB
            // menu bottom sheet (S18) so bottom-anchored surfaces
            // share one silhouette.
            //
            // `.ignoresSafeArea(edges: .bottom)` applied INSIDE the
            // background closure — the shape extends under the home
            // indicator so no blue gradient pixel leaks below the
            // footer, but the CONTENT above (footerLinks, trust row,
            // Continue, plans) still respects the safe area and stays
            // above the home indicator. Putting `ignoresSafeArea` on
            // the outer card view instead (previous pass) pushed the
            // footer text down into the home-indicator zone AND left
            // a gap at the very bottom where the blue was visible.
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 28,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 28
                ),
                style: .continuous
            )
            .fill(Color.dsBackgroundPrimary)
            // Upward shadow — negative y-offset lifts the shadow ABOVE
            // the card, so it reads as the card lifting off the blue
            // gradient. Wide radius keeps it a soft ambient shadow,
            // not a hard drop.
            .shadow(color: .black.opacity(0.18), radius: 24, y: -8)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var planPicker: some View {
        VStack(spacing: DSSpacing.xs) {
            ForEach(Plan.allCases) { plan in
                PaywallPlanRow(
                    title: plan.rawValue,
                    caption: plan.periodCaption,
                    price: vm.displayPrice(for: plan.productID),
                    badgeText: plan.trialBadgeText,
                    isSelected: selectedPlan == plan
                ) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selectedPlan = plan
                    }
                }
            }
        }
    }

    // MARK: - Close button (delayed 3s)

    private var closeButton: some View {
        Button {
            if let onContinueForFree { onContinueForFree() } else { dismiss() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.25), in: Circle())
        }
        .accessibilityLabel("Close")
        .padding(.trailing, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
    }

    // MARK: - Footer (Terms · Privacy · Restore)

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
        Task { await vm.restore() }
    }
}

// MARK: - Hero benefit row (white on gradient, full-width list item)

/// One row in the full-width benefit list — filled white circle with a
/// benefit-specific brand-blue SF Symbol, bold white title, and a
/// muted one-line subtitle underneath, sitting directly on the
/// gradient. Chosen (mockup option "A" of 6 compared directions, see
/// `Paywall-Benefit-Options.html`) over the earlier 2×2 icon grid: at
/// half-width each, all four titles wrapped to 2 lines and the
/// chip/material treatment read as dense and "blocky" — full width
/// guarantees a single line per title. The subtitle was tried, dropped
/// for space, then restored per explicit request — the illustration
/// (`heroContent`'s `maxHeight` cap) is what flexes to absorb the
/// resulting space pressure instead.
private struct HeroBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isLarge: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            ZStack {
                Circle().fill(.white)
                Image(systemName: icon)
                    .font(.system(size: isLarge ? 20 : 16, weight: .bold))
                    .foregroundStyle(Color.dsBrandPrimary)
            }
            .frame(width: isLarge ? 44 : 36, height: isLarge ? 44 : 36)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1.5)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(isLarge ? DSFont.title3 : DSFont.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(isLarge ? DSFont.callout : DSFont.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

// MARK: - Plan row (Weekly / Monthly)

/// One selectable plan row — real `Button`, not a tap gesture, so it
/// picks up standard focus/press/press-highlight for free (accessibility
/// guidance from `/swiftui-expert-skill`). Title reads on the leading
/// edge, price runs large on the trailing edge (no "/week"/"/month"
/// suffix crowding it — the title already states the period).
/// `badgeText` is generic (not a hardcoded "BEST VALUE") because only
/// Weekly carries one now — its 3-day-trial pill, rendered as a corner
/// ribbon straddling the row's top-trailing border, the way premium
/// paywalls (Streaks, Fabric) badge a highlighted plan without eating
/// into the row's own content width.
private struct PaywallPlanRow: View {
    let title: String
    let caption: String
    let price: String
    let badgeText: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(caption)
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }

                Spacer(minLength: DSSpacing.sm)

                if price == "—" {
                    PriceSkeleton()
                } else {
                    Text(price)
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                }
            }
            .padding(DSSpacing.md)
            .background(isSelected ? Color.dsBrandPrimarySubtle : Color.dsSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        // Badge sits outside the button's own clipShape (which only
        // covers the row's fill/border) so it isn't cut off where it
        // pokes past the top edge.
        .overlay(alignment: .topTrailing) {
            if let badgeText {
                Text(badgeText)
                    .font(DSFont.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.dsBrandPrimary, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .offset(x: -DSSpacing.sm, y: -DSSpacing.sm)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let priceLabel = price == "—" ? "price loading" : price
        var parts = [title, caption, priceLabel]
        if let badgeText { parts.append(badgeText) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Price skeleton (no real StoreKit product yet)

/// Stands in for a plan's price until a real `Product.displayPrice`
/// exists — a shimmering bar reads as "loading", where the earlier
/// literal `"$X.XX"` string read as an actual (if strangely formatted)
/// price. Static opacity pulse, not a shimmer sweep — simpler, and the
/// row is small enough that a moving gradient wouldn't read as
/// obviously different from a pulse anyway. Respects reduce motion by
/// just not animating (still clearly a placeholder shape either way).
private struct PriceSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
            .fill(Color.dsBorderDefault)
            .frame(width: 52, height: 22)
            .opacity(isPulsing ? 0.4 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    PaywallView()
}
