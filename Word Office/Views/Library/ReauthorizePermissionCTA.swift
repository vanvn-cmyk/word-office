import SwiftUI

/// Shown when the granted folder bookmark is stale or revoked
/// (Library-Architecture.md §7 trap #4). The library must never go silently empty —
/// this CTA always offers a re-grant path.
struct ReauthorizePermissionCTA: View {
    @Bindable var viewModel: FolderPermissionViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            heroIcon
                .padding(.bottom, DSSpacing.lg)

            headline
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.md)

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsStatusError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
                    .transition(.opacity)
            }

            actions
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
            Circle()
                .fill(Color.dsStatusWarning.opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 30)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.71, blue: 0.29),
                            Color.dsStatusWarning
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Color.dsStatusWarning.opacity(0.35), radius: 24, y: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: DSSpacing.sm) {
            Text("Folder access lost")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)

            Text("iOS revoked access, or the folder was moved. Grant access again to pick up where you left off — your status data is still safe.")
                .font(.system(size: 15))
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.sm)
        }
    }

    private var actions: some View {
        VStack(spacing: DSSpacing.xs + 2) {
            Button {
                Task { await viewModel.requestPermission() }
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    if viewModel.isRequesting {
                        ProgressView()
                            .tint(Color.dsTextOnBrand)
                    } else {
                        Text("Re-grant access")
                            .font(.system(size: 17, weight: .semibold))
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

            Button {
                Task {
                    await viewModel.resetPermission()
                    await viewModel.requestPermission()
                }
            } label: {
                Text("Pick a different folder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsBrandText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.dsBrandPrimarySubtle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.isRequesting)
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.dsBackgroundPrimary,
                Color.dsStatusWarningBackground.opacity(0.35)
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
    func requestFolderAccess() async throws -> FolderBookmark? {
        FolderBookmark(bookmarkData: Data(), displayPath: "/tmp")
    }
}

private struct FakeFolderBookmarkStore: FolderBookmarkResolving {
    func loadSaved() -> FolderBookmark? { nil }
    func resolve(_ bookmark: FolderBookmark) throws -> URL { URL(fileURLWithPath: "/tmp") }
    func save(_ bookmark: FolderBookmark) throws {}
    func delete() throws {}
}

private struct ReauthCTAPreview: View {
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
        ReauthorizePermissionCTA(viewModel: viewModel)
    }
}

#Preview("Default") {
    ReauthCTAPreview()
}

#Preview("With error") {
    ReauthCTAPreview(errorMessage: "Could not open the folder picker.")
}
