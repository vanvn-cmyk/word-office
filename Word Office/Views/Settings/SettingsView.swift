import SwiftUI

struct SettingsView: View {
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        @Bindable var theme = themeStore

        NavigationStack {
            Form {
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
