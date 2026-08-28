import SwiftUI

/// Menu-based picker for manually changing document status.
/// Status is never inferred from behaviour (Library-Architecture.md §7 trap #2) —
/// the user must pick it explicitly. Current value is disabled in the menu as
/// a visual "you're here" signal.
struct DocumentStatusPicker: View {
    let current: DocumentStatus
    let onChange: (DocumentStatus) -> Void

    var body: some View {
        Menu {
            ForEach(DocumentStatus.allCases) { status in
                Button {
                    onChange(status)
                } label: {
                    Label(status.displayName, systemImage: status.systemImage)
                }
                .disabled(status == current)
            }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: current.systemImage)
                Text(current.displayName)
                    .font(DSFont.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(Color.dsSurfaceSecondary, in: Capsule())
        }
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityLabel("Change status")
        .accessibilityValue(current.displayName)
    }
}

// MARK: - Preview

private struct DocumentStatusPickerPreview: View {
    @State private var status: DocumentStatus = .draft

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            DocumentStatusPicker(current: status) { status = $0 }
            Text("Current: \(status.displayName)")
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding()
    }
}

#Preview {
    DocumentStatusPickerPreview()
}
