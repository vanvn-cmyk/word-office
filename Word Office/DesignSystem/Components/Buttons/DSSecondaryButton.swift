import SwiftUI

struct DSSecondaryButton: View {
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
        .foregroundStyle(isDisabled ? Color.dsTextDisabled : Color.dsBrandText)
        .background(isDisabled ? Color.dsSurfaceDisabled : Color.dsSurfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                .stroke(isDisabled ? Color.dsBorderSubtle : Color.dsBorderDefault, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        DSSecondaryButton(title: "Cancel", action: {})
        DSSecondaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}
