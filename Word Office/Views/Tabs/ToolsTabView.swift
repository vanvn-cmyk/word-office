import SwiftUI

/// PDF utilities landing tab (Sprint 0.3 populates it).
struct ToolsTabView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "wrench.and.screwdriver",
                title: "PDF Tools",
                message: "Merge, split, compress, OCR, and scan — arriving in Sprint 0.3."
            )
            .navigationTitle("Tools")
        }
    }
}

#Preview { ToolsTabView() }
