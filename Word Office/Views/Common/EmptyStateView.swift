import SwiftUI

/// Design doc §10.8 — short, functional, action-oriented. No illustration-heavy hero.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: (label: LocalizedStringKey, handler: () -> Void)?
    /// Secondary action shown below the primary as a `.bordered` button.
    /// When nil, only the primary button is shown (existing behaviour).
    var secondaryAction: (label: LocalizedStringKey, handler: () -> Void)? = nil
    /// Optional footnote hint shown below the buttons — e.g. "Have a Word file?"
    /// with a link to a related tool. Use for cross-tool discovery, not errors.
    /// Small pill badge shown between the icon and title — e.g. "PDF only".
    var badge: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dsStatusError)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Color.dsStatusErrorBackground, in: Capsule())
            }

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
                VStack(spacing: DSSpacing.sm) {
                    Button(action.label, action: action.handler)
                        .buttonStyle(.borderedProminent)
                    if let secondaryAction {
                        Button(secondaryAction.label, action: secondaryAction.handler)
                            .buttonStyle(.bordered)
                    }
                }
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
