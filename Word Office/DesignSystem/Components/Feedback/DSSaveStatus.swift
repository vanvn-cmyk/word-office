import SwiftUI

/// Design doc §10.8 — subtle but visible save state indicator.
struct DSSaveStatus: View {
    let status: SessionStore.AutosaveStatus

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            indicator
            Text(label)
                .font(DSFont.footnote)
                .foregroundStyle(labelColor)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .saving:
            ProgressView().controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.dsStatusSuccess)
                .font(.system(size: 12))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.dsStatusError)
                .font(.system(size: 12))
        case .idle, .pending:
            EmptyView()
        }
    }

    private var label: LocalizedStringKey {
        switch status {
        case .idle:      "\u{200B}" // zero-width space keeps layout stable
        case .pending:   "Editing…"
        case .saving:    "Saving…"
        case .saved:     "Saved"
        case .failed:    "Save failed"
        }
    }

    private var labelColor: Color {
        switch status {
        case .failed: .dsStatusError
        default:      .dsTextTertiary
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DSSpacing.sm) {
        DSSaveStatus(status: .idle)
        DSSaveStatus(status: .saving)
        DSSaveStatus(status: .saved(at: Date()))
        DSSaveStatus(status: .failed(message: "Disk full"))
    }
    .padding()
}
