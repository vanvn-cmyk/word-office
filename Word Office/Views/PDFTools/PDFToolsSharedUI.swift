import SwiftUI

/// Shared across Merge/Split/Convert/Scan flows — a blocking "running in the
/// background" overlay. Uses an indeterminate spinner, not a percentage: none of
/// `PDFMerging`/`PDFSplitting`/the Convert exporters report real progress, and a
/// fake percentage would be worse than none (rule.md #6 — don't guess data that
/// doesn't exist). `OCRViewModel` is the one flow with real per-page progress —
/// see `ScanFlowView`'s own progress view instead of this one.
struct ProcessingOverlay: View {
    let title: String
    var subtitle: String?

    var body: some View {
        ZStack {
            Color.dsOverlayScrim.ignoresSafeArea()
            VStack(spacing: DSSpacing.sm) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.dsBrandPrimary)
                Text(title).font(DSFont.headline).foregroundStyle(Color.dsTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(DSSpacing.xl)
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
            .padding(DSSpacing.xxl)
        }
    }
}

/// Shared success-state header — checkmark + title + subtitle.
struct SuccessBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle().fill(Color.dsStatusSuccessBackground)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.dsStatusSuccess)
            }
            .frame(width: 64, height: 64)

            Text(title).font(DSFont.title3).foregroundStyle(Color.dsTextPrimary)
            Text(subtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DSSpacing.lg)
    }
}

extension View {
    /// Binds a `String?` error message to a standard dismissible alert — the same
    /// pattern `LibraryView` already uses, factored out since Merge/Split/Convert/
    /// Scan all need the identical wiring.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { Text($0) }
    }
}
