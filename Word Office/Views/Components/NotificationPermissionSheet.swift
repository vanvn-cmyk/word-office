import SwiftUI

/// Custom pre-permission dialog shown before the iOS system authorization prompt.
/// Explains value in plain terms so users understand WHY they'd want notifications.
///
/// Shown once, after the user completes their first action in the app.
/// Tapping "Allow Notifications" calls `onAllow` which then triggers the iOS
/// system prompt. Tapping "Not Now" records the dismissal and never shows again.
struct NotificationPermissionSheet: View {
    var onAllow: () -> Void
    var onSkip:  () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Icon — gradient-filled circle with bell
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.dsBrandPrimary.opacity(0.18), Color.dsBrandPrimary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.top, 28)

                Text("Stay on top of your work")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                Text("Get a nudge when files need attention — so nothing slips through the cracks")
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)

                // Feature rows
                VStack(alignment: .leading, spacing: 14) {
                    featureRow(
                        icon: "doc.text.fill",
                        text: "Remind you when drafts have been waiting too long"
                    )
                    featureRow(
                        icon: "checkmark.seal.fill",
                        text: "Alert you when a file is ready to sign or review"
                    )
                    featureRow(
                        icon: "clock.fill",
                        text: "Fire your manual reminders exactly on time"
                    )
                }
                .padding(.top, 22)
                .padding(.horizontal, 28)

                // Fixed gap — keeps buttons close to content on all screen sizes
                Color.clear.frame(height: 32)

                Button(action: onAllow) {
                    Text("Allow Notifications")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.dsBrandPrimary)
                .padding(.horizontal, 24)

                Button("Not Now", action: onSkip)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextSecondary)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(UIColor.systemBackground))
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.dsBrandPrimary.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsBrandPrimary)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(text)
                .font(DSFont.callout)
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 7)
        }
    }
}
