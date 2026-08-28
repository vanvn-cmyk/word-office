import SwiftUI

/// Design doc §10.1 — one primary action per surface.
struct DSPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DSSize.buttonHeight)
        }
        .foregroundStyle(isDisabled ? Color.dsButtonDisabledText : Color.dsTextOnBrand)
        .background(isDisabled ? Color.dsButtonDisabledBackground : Color.dsBrandPrimary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        DSPrimaryButton(title: "Create Document", action: {})
        DSPrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}
