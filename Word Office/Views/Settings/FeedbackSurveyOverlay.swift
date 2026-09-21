import SwiftUI

/// Full-screen overlay that appears before the feedback sheet.
/// Shows a spinner + message for 1 second, then calls `onComplete`.
struct FeedbackSurveyOverlay: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: DSSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)

                Text("Just a moment — a minute of your feedback helps us build a better app")
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpacing.xl)
            .background(
                Color.dsBackgroundElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            )
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            .padding(.horizontal, DSSpacing.xl)
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            onComplete()
        }
    }
}
