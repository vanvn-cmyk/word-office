import SwiftUI

/// First-run onboarding pager (4 screens). Presented by `RootView` when
/// `hasCompletedOnboarding` is false — replaces the standalone
/// `FolderPermissionOnboarding` on the fresh-install path. That view remains
/// as the re-grant fallback after a user resets folder access from Settings.
///
/// Layout (top→bottom):
/// - Top bar: right-aligned "Skip" button (hidden on S4)
/// - Pager: swipeable `TabView(.page)` with per-page hero card + text
/// - Footer: pill dots + white primary CTA + (S4 only) "Maybe Later"
///
/// The background gradient switches per page (`OnboardingAuroraBackground`)
/// and text/indicator/CTA are all rendered white so they read against the
/// deep gradient. S4's "Choose Folder" delegates to `FolderPermissionViewModel`
/// so the permission logic stays in one place.
struct OnboardingContainerView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Bindable var permissionVM: FolderPermissionViewModel

    /// Read post-`requestPermission()` to decide whether to finish onboarding.
    /// `FolderPermissionViewModel.requestPermission()` writes the granted state
    /// synchronously to this store before returning; a cancel leaves it as-is.
    @Environment(LibraryStore.self) private var libraryStore

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
        // Plug the gap: on iOS 26 the window background bleeds into the
        // Dynamic Island / status bar zone if no explicit color is set.
        // This dark navy matches the top of every page's gradient palette
        // so there's no visible seam even before the gradient renders.
        .background(Color(red: 0.04, green: 0.09, blue: 0.28).ignoresSafeArea())
        .animation(.default, value: permissionVM.errorMessage)
        .animation(.default, value: permissionVM.isRequesting)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLastPage)
    }

    // MARK: - Top bar (Skip only, right-aligned)

    /// Fixed 44pt height so the pager's top edge stays stable when Skip
    /// disappears on S4 — otherwise the hero would jump up.
    private var topBar: some View {
        HStack {
            Spacer()
            if !viewModel.isLastPage {
                Button("Skip") {
                    viewModel.jump(to: viewModel.pages.count - 1)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
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
                OnboardingPageView(page: page)
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

    // MARK: - Footer (indicator + CTA + secondary)

    private var footer: some View {
        VStack(spacing: DSSpacing.md) {
            OnboardingPageIndicator(
                pageCount: viewModel.pages.count,
                currentIndex: viewModel.currentIndex,
                activeColor: .white,
                inactiveColor: .white.opacity(0.35)
            )

            if viewModel.currentPage.showsPrivacyChip, let errorMessage = permissionVM.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            primaryCTA

            secondaryButton
                .padding(.top, DSSpacing.xxs)
        }
    }

    // MARK: - Primary CTA (white pill with brand-colored text)

    private var primaryCTA: some View {
        Button {
            handlePrimaryTap()
        } label: {
            HStack(spacing: DSSpacing.xs) {
                if isRequestingFolder {
                    ProgressView().tint(Color.dsBrandPrimary)
                } else {
                    Text(viewModel.currentPage.primaryCTA)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color.dsBrandPrimary)
            .background(Color.white, in: Capsule())
            .shadow(color: Color.black.opacity(0.20), radius: 16, y: 8)
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
            .foregroundStyle(.white.opacity(0.8))
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
