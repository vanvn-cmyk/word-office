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
        // Plain VStack — no ScrollView. The sheet proposes exactly 520pt to this
        // VStack (via presentationDetents). Spacer(minLength:0) absorbs whatever
        // space is left after the fixed content and buttons, so buttons always
        // sit at the bottom with zero blank gap below them regardless of screen
        // width. Calculated headroom on the narrowest supported device (375pt /
        // iPhone SE): content ~384pt + buttons ~114pt = 498pt < 520pt, so
        // Spacer gets ≥22pt on every device — no overflow, no clipping.
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

            // Flexible gap: absorbs leftover space so buttons stay at bottom.
            // Expands on wide/tall screens (iPad, Pro Max), compresses on narrow
            // ones (SE) — minLength:0 lets it go to zero if needed (safe because
            // total fixed content never exceeds 520pt on any supported device).
            Spacer(minLength: 0)

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
