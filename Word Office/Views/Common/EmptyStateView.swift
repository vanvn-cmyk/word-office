import SwiftUI

/// Design doc §10.8 — short, functional, action-oriented. No illustration-heavy hero.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: (label: LocalizedStringKey, handler: () -> Void)?

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)

            VStack(spacing: DSSpacing.xs) {
                Text(title)
                    .font(DSFont.title3)
                    .foregroundStyle(Color.dsTextPrimary)
                Text(message)
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackgroundPrimary)
    }
}

#Preview {
    EmptyStateView(
        icon: "doc.badge.plus",
        title: "No documents yet",
        message: "Create your first document to get started",
        action: (label: "Create document", handler: {})
    )
}
