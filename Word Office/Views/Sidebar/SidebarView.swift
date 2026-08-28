import SwiftUI

/// iPad/Mac Catalyst navigation sidebar (design doc §10.5).
/// Sprint 0.1: minimal Documents section. Locations (iCloud/Drive/Dropbox) → Sprint 0.3/Phase 2.
struct SidebarView: View {
    var body: some View {
        List {
            Section("Documents") {
                Label("Recent", systemImage: "clock")
                Label("Favorites", systemImage: "star")
            }

            Section("Locations") {
                Label("On My iPad", systemImage: "ipad")
                Label("iCloud Drive", systemImage: "icloud")
                    .foregroundStyle(Color.dsTextTertiary)
            }

            Section {
                Label("Tools", systemImage: "wrench.and.screwdriver")
                Label("Trash", systemImage: "trash")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Word Office")
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
}
