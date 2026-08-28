import SwiftUI

/// First-run flow (Library-Architecture.md §4 scenario 1) — the one-tap folder
/// grant that unlocks the whole library. The "aha" framed in `product-strategy-master`.
struct FolderPermissionOnboarding: View {
    @Bindable var viewModel: FolderPermissionViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            heroIcon
                .padding(.bottom, DSSpacing.lg)

            headline
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)

            featureList
                .padding(.horizontal, DSSpacing.lg)

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsStatusError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            primaryCTA
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient)
        .animation(.default, value: viewModel.errorMessage)
        .animation(.default, value: viewModel.isRequesting)
    }

    // MARK: - Sub-views

    private var heroIcon: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(Color.dsBrandPrimary.opacity(0.15))
                .frame(width: 180, height: 180)
                .blur(radius: 30)

            // Gradient tile
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.dsBrandPrimary, Color.dsBrandText],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 24, y: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: DSSpacing.sm) {
            Text("Your library")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)

            Text("Pick a folder that holds your documents. Word Office scans it and tracks status — files stay in place, nothing is copied or uploaded.")
                .font(.system(size: 15))
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(spacing: DSSpacing.xs) {
            featureRow(icon: "checkmark.seal.fill",
                       title: "Files stay in your folder",
                       subtitle: "No copies, no uploads")
            featureRow(icon: "lock.shield.fill",
                       title: "Status stays in the app",
                       subtitle: "Local metadata only")
            featureRow(icon: "arrow.triangle.2.circlepath",
                       title: "Change folder any time",
                       subtitle: "Reset from the toolbar menu")
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: DSSpacing.sm + 2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dsBrandPrimarySubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.dsTextTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DSSpacing.xs + 2)
        .padding(.horizontal, DSSpacing.sm + 2)
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.dsBorderSubtle, lineWidth: 0.5)
        }
    }

    private var primaryCTA: some View {
        Button {
            Task { await viewModel.requestPermission() }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                if viewModel.isRequesting {
                    ProgressView()
                        .tint(Color.dsTextOnBrand)
                } else {
                    Text("Choose folder")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color.dsTextOnBrand)
            .background(
                LinearGradient(
                    colors: [Color.dsBrandPrimary, Color.dsBrandPrimaryPressed],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 16, y: 8)
        }
        .disabled(viewModel.isRequesting)
        .buttonStyle(PressableButtonStyle())
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.dsBackgroundPrimary,
                Color.dsBrandPrimarySubtle.opacity(0.35)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Button style

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

private struct FakeFolderPermissionPicker: FolderPermissionGranting {
    var shouldGrant: Bool = true
    var delayNs: UInt64 = 500_000_000

    func requestFolderAccess() async throws -> FolderBookmark? {
        try? await Task.sleep(nanoseconds: delayNs)
        return shouldGrant
            ? FolderBookmark(bookmarkData: Data(), displayPath: "iCloud Drive/Word Office")
            : nil
    }
}

private struct FakeFolderBookmarkStore: FolderBookmarkResolving {
    var stored: FolderBookmark?

    func loadSaved() -> FolderBookmark? { stored }
    func resolve(_ bookmark: FolderBookmark) throws -> URL { URL(fileURLWithPath: "/tmp") }
    func save(_ bookmark: FolderBookmark) throws {}
    func delete() throws {}
}

private struct OnboardingPreview: View {
    @State private var viewModel: FolderPermissionViewModel

    init(errorMessage: String? = nil) {
        let vm = FolderPermissionViewModel(
            store: LibraryStore(),
            picker: FakeFolderPermissionPicker(),
            bookmarkStore: FakeFolderBookmarkStore()
        )
        vm.errorMessage = errorMessage
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        FolderPermissionOnboarding(viewModel: viewModel)
    }
}

#Preview("Default") {
    OnboardingPreview()
}

#Preview("With error") {
    OnboardingPreview(errorMessage: "System denied folder access. Please try again.")
}
