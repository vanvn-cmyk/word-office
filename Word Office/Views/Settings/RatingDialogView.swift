import SwiftUI
import StoreKit

/// Presented from Settings → "Rate app". Owns its own dismiss + submit flow
/// (per `/swiftui-expert-skill` sheet guidance — sheets shouldn't take
/// onSave/onCancel closures from the caller).
///
/// Only 4–5 star ratings trigger `requestReview()` (SwiftUI's StoreKit
/// environment action). 1–3 star ratings show a thank-you toast but skip
/// the system prompt so unsatisfied users aren't sent to the App Store.
struct RatingDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(DSToastPresenter.self) private var toastPresenter

    @State private var rating = 5

    @ScaledMetric private var starHeaderSize: CGFloat = 36

    var body: some View {
        // Fixed top/bottom padding, not two `Spacer`s — with a fixed
        // `.presentationDetents` height, two flexible `Spacer`s split the
        // same leftover space roughly evenly regardless of their
        // `minLength`, which is why top and bottom ended up visually equal
        // even after giving them different minimums. Explicit values stay
        // asymmetric: more room below the drag indicator, less below
        // "Not now".
        VStack(spacing: 0) {
            VStack(spacing: DSSpacing.sm) {
                // Matches the star used for "Rate app" in Settings — a heart
                // read as an unrelated "like this app" flourish rather than
                // tying visually to what the dialog actually does.
                Image(systemName: "star.fill")
                    .font(.system(size: starHeaderSize))
                    .foregroundStyle(Color.dsPremiumGoldEnd)
                    .accessibilityHidden(true)
                Text("Enjoying Word Office?")
                    .font(DSFont.title3)
                    .foregroundStyle(Color.dsTextPrimary)
                Text("Let us know what you think")
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
            }

            StarRatingSelector(rating: $rating)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)

            VStack(spacing: DSSpacing.sm) {
                DSPrimaryButton(title: "Submit", action: submit, isDisabled: rating == 0)
                DSSecondaryButton(title: "Not now") { dismiss() }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.top, DSSpacing.xl)
        .padding(.bottom, DSSpacing.xs)
        // A plain constant again, not a self-measured one — feeding
        // `presentationDetents` a height read back from this same view's own
        // `GeometryReader` created a feedback loop (the detent drives the
        // offered size, which drives the measurement, which drives the
        // detent) that collapsed the sheet to almost nothing instead of
        // converging. `340` is a tighter fit than the earlier `380` guess.
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func submit() {
        let finalRating = rating
        dismiss()
        // Only request an in-app review for satisfied users (4–5 stars).
        // For 1–3 stars, the toast is shown but the system prompt is skipped
        // so unimpressed users aren't asked to rate on the App Store.
        if finalRating >= 4 {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                requestReview()
            }
        }
        toastPresenter.show(.success, title: finalRating >= 4 ? "Thanks for the love!" : "Thanks for your feedback!")
    }
}

/// Exposed to accessibility as one adjustable control (like a `Stepper`)
/// rather than 5 separate star buttons — matches the skill's
/// `accessibilityAdjustableAction` pattern for custom rating/paging controls.
private struct StarRatingSelector: View {
    @Binding var rating: Int
    private let maxRating = 5

    @ScaledMetric private var starSize: CGFloat = 32

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach(1...maxRating, id: \.self) { star in
                Button {
                    select(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(star <= rating ? Color.dsPremiumGoldStart : Color.dsBorderDefault)
                        .scaleEffect(star == rating ? 1.15 : 1.0)
                        .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "No rating selected" : "\(rating) of \(maxRating) stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard rating < maxRating else { return }
                select(rating + 1)
            case .decrement:
                guard rating > 0 else { return }
                select(rating - 1)
            @unknown default:
                break
            }
        }
    }

    private func select(_ star: Int) {
        // `.easeOut` — not `.spring(...)`. Rule "no spring physics"
        // (`~/CLAUDE.md`) is enforced app-wide; every other tap-to-select
        // animation in this project uses a plain ease curve.
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.15)) {
            rating = star
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            RatingDialogView()
                .environment(DSToastPresenter())
        }
}
