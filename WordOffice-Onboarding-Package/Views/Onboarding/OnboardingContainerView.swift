import SwiftUI

/// First-run onboarding pager (4 screens). Presented by `RootView` when
/// `hasCompletedOnboarding` is false — replaces the standalone
/// `FolderPermissionOnboarding` on the fresh-install path. That view remains
/// as the re-grant fallback after a user resets folder access from Settings.
///
/// Layout (top→bottom), matching the approved mockup
/// (`onboarding-exports/S1-S4`):
/// - Top bar: pill-dot progress indicator, leading, + "Skip" trailing (hidden on S4)
/// - Pager: swipeable `TabView(.page)` with per-page hero art + text
/// - Footer: primary CTA + (S4 only) "Maybe Later"
///
/// The background is a fixed light "soft brand wash" (`OnboardingAuroraBackground`
/// — see its doc comment for the visual history) and text/CTA are rendered
/// dark/near-black to read against it, as fixed literals rather than DS
/// tokens (see `OnboardingColors`). S4's "Choose Folder" delegates to
/// `FolderPermissionViewModel` so the permission logic stays in one place.
struct OnboardingContainerView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Bindable var permissionVM: FolderPermissionViewModel

    /// Read post-`requestPermission()` to decide whether to finish onboarding.
    /// `FolderPermissionViewModel.requestPermission()` writes the granted state
    /// synchronously to this store before returning; a cancel leaves it as-is.
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingAuroraBackground(page: viewModel.currentPage.id)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.xs)

                pager

                footer
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.lg)
            }
        }
        .animation(reduceMotion ? nil : .default, value: permissionVM.errorMessage)
        .animation(reduceMotion ? nil : .default, value: permissionVM.isRequesting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.currentIndex)
    }

    // MARK: - Top bar (progress indicator, leading + Skip, trailing)

    /// Fixed 44pt height so the pager's top edge stays stable when Skip
    /// disappears on S4 — otherwise the hero would jump up. Indicator moved
    /// up here from the footer (mockup places progress at the very top,
    /// right under the status bar, not stacked above the CTA).
    private var topBar: some View {
        HStack {
            OnboardingPageIndicator(
                pageCount: viewModel.pages.count,
                currentIndex: viewModel.currentIndex,
                activeColor: .dsBrandPrimary,
                inactiveColor: .black.opacity(0.12)
            )

            Spacer()

            if viewModel.isFirstPage {
                // Backing pill, not bare text — the background blob's anchor
                // sits directly under this corner on `.tools`, and at its
                // brightest breathing phase a plain gray label here drops
                // below the 4.5:1 contrast floor. A fixed white backing
                // guarantees contrast regardless of what's behind it,
                // instead of just relocating the blob (which review pointed
                // out is easy to get wrong again on a future page).
                Button("Skip") {
                    viewModel.jump(to: viewModel.pages.count - 1)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnboardingColors.textSecondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.white.opacity(0.7), in: Capsule())
                .accessibilityHint("Jump to the folder-permission step")
                .transition(.opacity)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Pager

    private var pager: some View {
        TabView(selection: pagerBinding) {
            ForEach(viewModel.pages) { page in
                OnboardingPageView(page: page, isActive: page.id == viewModel.currentPage.id)
                    .tag(indexOf(page))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bridges the view-model's `private(set)` index to a two-way binding for
    /// `TabView` — writes go through `jump(to:)` so the mutation stays inside
    /// the view-model API.
    private var pagerBinding: Binding<Int> {
        Binding(
            get: { viewModel.currentIndex },
            set: { viewModel.jump(to: $0) }
        )
    }

    private func indexOf(_ page: OnboardingPage) -> Int {
        viewModel.pages.firstIndex(of: page) ?? 0
    }

    // MARK: - Footer (CTA + secondary)

    private var footer: some View {
        VStack(spacing: DSSpacing.md) {
            if viewModel.currentPage.showsPrivacyChip, let errorMessage = permissionVM.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardingColors.error)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            primaryCTA

            secondaryButton
                .padding(.top, DSSpacing.xxs)
        }
    }

    // MARK: - Primary CTA
    //
    // Brand-blue pill on every page (per user request — previously S1-S3
    // used a neutral near-black pill, reserving blue for S4's "decision
    // point" only; simpler and more consistent to keep every page on-brand).

    private var primaryCTA: some View {
        Button {
            handlePrimaryTap()
        } label: {
            HStack(spacing: DSSpacing.xs) {
                if isRequestingFolder {
                    ProgressView().tint(.white)
                } else {
                    Text(viewModel.currentPage.primaryCTA)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white)
            .background(Color.dsBrandPrimary, in: Capsule())
            .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(OnboardingPressableStyle())
        .disabled(isRequestingFolder)
        .accessibilityLabel(viewModel.currentPage.primaryCTA)
    }

    private var isRequestingFolder: Bool {
        viewModel.currentPage.id == .chooseFolder && permissionVM.isRequesting
    }

    // MARK: - Secondary (Skip on S1-S3 has moved up to topBar; slot reserved for Maybe Later on S4)

    /// Only S4 renders a secondary — the top-bar Skip covers S1-S3.
    /// The slot always occupies vertical space (empty `Color.clear`) so the
    /// primary CTA doesn't jump when we cross to S4.
    @ViewBuilder
    private var secondaryButton: some View {
        if viewModel.isLastPage {
            Button("Maybe Later") {
                permissionVM.skipOnboarding()
                viewModel.finish()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OnboardingColors.textSecondary)
            .disabled(permissionVM.isRequesting)
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Actions

    private func handlePrimaryTap() {
        switch viewModel.currentPage.id {
        case .editOffice, .tools, .trackDocuments:
            viewModel.advance()
        case .chooseFolder:
            Task {
                await permissionVM.requestPermission()
                if libraryStore.folderPermissionState == .granted {
                    viewModel.finish()
                }
            }
        }
    }
}

// MARK: - Button style

private struct OnboardingPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

private struct FakePicker: FolderPermissionGranting {
    func requestFolderAccess() async throws -> FolderBookmark? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return FolderBookmark(bookmarkData: Data(), displayPath: "iCloud Drive/Word Office")
    }
}

private struct FakeBookmarkStore: FolderBookmarkResolving {
    func loadSaved() -> FolderBookmark? { nil }
    func resolve(_ bookmark: FolderBookmark) throws -> URL { URL(fileURLWithPath: "/tmp") }
    func save(_ bookmark: FolderBookmark) throws {}
    func delete() throws {}
}

#Preview("Onboarding") {
    let store = LibraryStore()
    let permissionVM = FolderPermissionViewModel(
        store: store,
        picker: FakePicker(),
        bookmarkStore: FakeBookmarkStore()
    )
    let viewModel = OnboardingViewModel(onFinish: {})
    return OnboardingContainerView(viewModel: viewModel, permissionVM: permissionVM)
        .environment(store)
}
