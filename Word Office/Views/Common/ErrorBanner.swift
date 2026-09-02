import SwiftUI

/// Persistent top banner for save/load errors (Phase0-Implementation-Logic.md §7.3
/// "never silent data loss") — stays visible until dismissed or the underlying
/// error clears (e.g. the next successful autosave sets `errorMessage = nil`).
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsStatusError)

            Text(message)
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(DSSpacing.sm)
        .background(Color.dsStatusErrorBackground, in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .strokeBorder(Color.dsStatusErrorBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ErrorBanner(
        message: "This document has images or tables that can't be preserved yet — editing here would remove them",
        onDismiss: {}
    )
    .padding()
    .background(Color.dsBackgroundSecondary)
}
