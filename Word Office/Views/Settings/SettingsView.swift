import SwiftUI

struct SettingsView: View {
    @Environment(ThemeStore.self) private var themeStore

    /// Resets the granted-folder bookmark and sends `RootView` back to onboarding.
    /// Wired to `FolderPermissionViewModel.resetPermission()` by the caller — this
    /// view owns no permission state itself.
    let onChangeFolder: () async -> Void

    var body: some View {
        @Bindable var theme = themeStore

        NavigationStack {
            Form {
                Section("Library") {
                    Button("Change folder…") {
                        Task { await onChangeFolder() }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme.appearance) {
                        ForEach(AppTheme.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: appBuild)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}
