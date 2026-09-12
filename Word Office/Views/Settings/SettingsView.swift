import SwiftUI

struct SettingsView: View {
    @Environment(ThemeStore.self) private var themeStore

    /// Resets the granted-folder bookmark and sends `RootView` back to onboarding.
    /// Wired to `FolderPermissionViewModel.resetPermission()` by the caller — this
    /// view owns no permission state itself.
    let onChangeFolder: () async -> Void

    @State private var isRatingDialogPresented = false
    @State private var isPaywallPresented = false
    @AppStorage("root.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    /// Not live yet — app hasn't shipped, so there's nothing real to link to.
    /// Rows render like any other enabled row either way (see
    /// `SettingsLegalRow`) — they just won't open anything until these are
    /// filled in with the real URLs before submission.
    private let privacyPolicyURL: URL? = nil
    private let termsOfServiceURL: URL? = nil

    /// No App Store listing yet either, so there's nothing to deep-link to —
    /// share plain text only until a real store URL exists.
    private let shareAppMessage = "Check out Word Office!"

    var body: some View {
        @Bindable var theme = themeStore

        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Inline large title on the leading edge — same shape as
                // `LibraryView.titleRow` / `ToolsTabView.titleRow`, so all
                // three home tabs read as the same visual family. Replaced
                // `.prominentInlineTitle` (which sits centered in the nav
                // bar at ~22pt) with the 34pt leading-aligned pattern the
                // other two tabs already use.
                titleRow
                    .padding(.horizontal, DSSpacing.lg)
                    // Small breathing gap between the large title and the
                    // banner below. Same pattern as `LibraryView.titleRow`
                    // giving its search row an 8pt gap.
                    .padding(.bottom, DSSpacing.xs)

                Form {
                    Section {
                        SettingsPremiumBanner {
                            isPaywallPresented = true
                        }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                Section("Library") {
                    Button {
                        Task { await onChangeFolder() }
                    } label: {
                        Label {
                            // `Color.dsTextPrimary` + `DSFont.body` explicit —
                            // without them, `Button`'s label text picks up the
                            // accent-blue tint (the row shows "Change folder…"
                            // in blue while every other row is black), and the
                            // font falls back to SwiftUI's raw `.body` default
                            // instead of referencing the app's DS token. Same
                            // recipe every other row in this Form uses.
                            Text("Change folder…")
                                .font(DSFont.body)
                                .foregroundStyle(Color.dsTextPrimary)
                        } icon: {
                            SettingsRowIcon(systemName: "folder.fill", tint: Color.dsBrandPrimary)
                        }
                    }
                }

                Section("General") {
                    ShareLink(item: shareAppMessage) {
                        Label {
                            Text("Share app")
                                .font(DSFont.body)
                                .foregroundStyle(Color.dsTextPrimary)
                        } icon: {
                            SettingsRowIcon(systemName: "square.and.arrow.up", tint: Color.dsBrandPrimary)
                        }
                    }
                    Button {
                        isRatingDialogPresented = true
                    } label: {
                        Label {
                            Text("Rate app")
                                .font(DSFont.body)
                                .foregroundStyle(Color.dsTextPrimary)
                        } icon: {
                            // `dsPremiumGoldEnd` (the darker, more muted side
                            // of the gold pair), not `dsPremiumGoldStart` —
                            // the bright-yellow start color is too
                            // high-luminance for this tint recipe: a
                            // 12%-opacity tint of it sits almost as light as
                            // the full-strength icon on top, so the two blur
                            // together into a solid blob instead of reading
                            // as "icon on badge." The darker gold has enough
                            // contrast to render like every other row's flat,
                            // single-color icon here.
                            SettingsRowIcon(systemName: "star.fill", tint: Color.dsPremiumGoldEnd)
                        }
                    }
                    // `lock.shield.fill` — consistent with the privacy
                    // iconography used in onboarding S4.
                    SettingsLegalRow(title: "Privacy Policy", systemName: "lock.shield.fill", url: privacyPolicyURL)
                    SettingsLegalRow(title: "Terms of Service", systemName: "doc.text.fill", url: termsOfServiceURL)
                }

                Section("Developer") {
                    Button {
                        UserDefaults.standard.removeObject(forKey: SampleFileSeeder.didSeedDefaultsKey)
                        hasCompletedOnboarding = false
                    } label: {
                        Label {
                            Text("Reset Onboarding")
                                .font(DSFont.body)
                                .foregroundStyle(Color.dsTextPrimary)
                        } icon: {
                            SettingsRowIcon(systemName: "arrow.counterclockwise", tint: Color.dsTextSecondary)
                        }
                    }
                }

                // Fake trailing spacer — same pattern as LibraryView.
                Section {
                    Color.clear
                        .frame(height: DSTabBarMetrics.listContentTrailingSpacer)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
                .listSectionSpacing(.compact)
                // Kill Form's default scroll-content top inset (~35pt from
                // `insetGrouped` UITableViewStyle plumbing) — with an
                // external `titleRow` above providing the whole page's top
                // spacing, Form's built-in cushion just adds an 80pt dead
                // strip between the title and the first section.
                // `.scrollContent` scope means it targets the padding
                // Form applies to its inner scroll content, NOT the
                // safe-area inset above it (iOS 17+ API split).
                .contentMargins(.top, 0, for: .scrollContent)
                // Hide Form's own opaque `systemGroupedBackground` — the
                // culprit behind the white strip visible above the first
                // section. `Form` is a `List` with `insetGrouped` style;
                // without this modifier its default OPAQUE list background
                // paints the whole scroll area (including the top cushion +
                // any gap outside the section row surfaces), and any
                // `.background(...)` applied to a container above the List
                // is invisible under it. See `references/list-patterns.md`
                // "Custom List Backgrounds" — this is THE iOS 16+ API for
                // custom List backgrounds and stays current on iOS 26.
                .scrollContentBackground(.hidden)
                .autoHidesTabBarOnScroll()
            }
            // Same background as `ToolsTabView` (line ~110) so the title
            // strip and the Form's `insetGrouped` gray surface read as one
            // continuous page — without this, `NavigationStack`'s default
            // white background shows through above the Form, producing a
            // visible white band under the status bar.
            .background(Color.dsBackgroundSecondary)
            // `.navigationTitle` kept for VoiceOver + parent back-button
            // semantics; the visible title lives in `titleRow` above.
            // `.toolbarVisibility(.hidden)` collapses the empty navbar
            // strip so `titleRow` sits flush under the status bar, same
            // pattern as `ToolsTabView`.
            .navigationTitle("Settings")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $isRatingDialogPresented) {
                RatingDialogView()
            }
            // `.fullScreenCover` — see the matching call site in
            // `LibraryView` for the rationale (paywall is a full-page
            // product-selling surface, not a modal decision).
            .fullScreenCover(isPresented: $isPaywallPresented) {
                PaywallView()
            }
        }
    }

    /// Big page title on the leading edge — same shape as
    /// `LibraryView.titleRow` / `ToolsTabView.titleRow`, so all three home
    /// tabs read as one visual family. No trailing crown here: the paywall
    /// entry lives in the `SettingsPremiumBanner` row inside the list, not
    /// in the title bar.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            Text("Settings")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DSSpacing.sm)
        }
        .padding(.top, DSSpacing.sm)
    }
}

/// Premium upsell banner above the settings list — the illustration
/// (gradient background + folder/document art) is a single designed raster
/// asset (`Assets.xcassets/SettingsPremiumBanner`), not something recreated
/// in SwiftUI, so headline/subhead/CTA are laid out as an overlay on top of
/// it rather than drawn from DS color tokens for the background itself.
///
/// Headline, subhead, and the "Explore Premium" CTA are now baked directly
/// into the designed asset itself (a full replacement banner the user
/// supplied) rather than laid out as a separate SwiftUI overlay — so this
/// view is just the image, tapped as one button, with a shadow.
///
/// Current asset (v3) has a real alpha channel (`sips -g hasAlpha` → `yes`)
/// — cropped only to trim the near-fully-transparent fringe outside its
/// glow (alpha ≤ 5), keeping the glow itself intact. An earlier version of
/// this asset had NO alpha channel at all — a checkerboard pattern baked
/// into opaque RGB pixels to simulate transparency in the export tool's
/// preview — which rendered as a literal gray-checker square in the app
/// until caught; `clipShape` below is kept as a cheap safety net against
/// that recurring in a future replacement image, not because this one needs
/// it.
private struct SettingsPremiumBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    private let imageAspectRatio: CGFloat = 1961.0 / 726.0

    var body: some View {
        Button(action: action) {
            Image("SettingsPremiumBanner")
                .resizable()
                .aspectRatio(imageAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
                // Same layered-shadow recipe as `ToolsTabView`'s card
                // surface (tight ambient + soft spread, black, opacity
                // bumped in dark mode) rather than a one-off tinted glow —
                // keeps every card in the app "lifting off the page" the
                // same way.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.06), radius: 2, y: 1)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        // Without this, the button in a `Form` row hugs its label's ideal
        // size instead of the `frame(maxWidth: .infinity)` inside that
        // label actually expanding the row — the button rendered tiny,
        // centered in its own cramped bounds, until forced to fill here too.
        .frame(maxWidth: .infinity)
        // Edge-to-edge instead of the usual `DSSpacing.md` row margin — with
        // `contentMode: .fit` (no cropping, so the only way to make the
        // banner bigger without cutting into the art is to give it more
        // width to fit into), this is the full available size increase
        // before the image itself would need to be re-exported larger.
        .accessibilityLabel("Your Office, Upgraded. Professional tools, made for you.")
        .accessibilityHint("Explore Premium")
    }
}

/// Leading icon tile for a Settings row. Matches this app's OWN established
/// badge recipe — `DSDocumentTypeBadge` (file-type badges) and
/// `ToolsTabView.IconBadge` (tool cards) both use a translucent tint
/// background with the icon in that same color at full strength, never a
/// solid fill with a white glyph. A solid-fill + white-icon tile (the first
/// version of this component) was Apple-Settings-app styling grafted onto a
/// codebase that already has its own badge language — fixed to reuse it
/// instead of inventing a third one.
private struct SettingsRowIcon: View {
    let systemName: String
    let tint: Color
    private let size: CGFloat = 29

    var body: some View {
        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// Privacy Policy / Terms of Service row. Renders identically to every other
/// settings row (no dimmed/disabled treatment, no "Coming soon" caption) —
/// it just isn't wrapped in a `Link` until `url` is filled in with a real
/// address on `SettingsView`, since `Link` has no valid destination without
/// one.
private struct SettingsLegalRow: View {
    let title: LocalizedStringKey
    let systemName: String
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                HStack {
                    rowLabel
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        Label {
            // Explicit black even though `Link` would otherwise tint this
            // accent-blue once a real `url` lands — matches the rest of
            // "General" being black text with color carried by the icon
            // alone, not by the label.
            Text(title)
                .font(DSFont.body)
                .foregroundStyle(Color.dsTextPrimary)
        } icon: {
            // `dsBrandPrimary` — not held back to gray just because there's
            // no URL yet; both Privacy Policy and Terms of Service use brand blue
            // instead of introducing a separate "disabled-looking" gray.
            SettingsRowIcon(systemName: systemName, tint: Color.dsBrandPrimary)
        }
    }
}
