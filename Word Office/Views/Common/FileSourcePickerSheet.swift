import SwiftUI

/// Bottom sheet for choosing a file source — Library vs Files browser.
/// Visual pattern matches `ImageConvertPickerSheet` (row-based, explicit
/// `dsBackgroundSecondary` ground, no Liquid Glass bleed).
///
/// Presented on the Tools tab BEFORE navigation (so the picker appears on
/// the grid screen, not inside the tool view). Also available inside tool
/// views via `.fileSourcePicker(...)` as a "Choose a file" fallback.
struct FileSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onLibrary: () -> Void
    let onBrowse: () -> Void
    /// Optional context line shown above the two source rows.
    /// When non-nil the sheet grows to 190 pt to accommodate it.
    var message: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.md)

            if let message {
                Text(message)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
            }

            VStack(spacing: 0) {
                sourceRow(
                    icon: "tray.fill",
                    tint: Color.dsBrandPrimary,
                    title: "Pick from Library",
                    subtitle: "Files saved to this app",
                    action: onLibrary
                )
                Divider()
                    .padding(.leading, 36 + DSSpacing.md * 2)
                sourceRow(
                    icon: "folder.fill",
                    tint: Color.dsTextSecondary,
                    title: "Browse Files",
                    subtitle: "iCloud Drive and other locations",
                    action: onBrowse
                )
            }
            .background(Color.dsBackgroundElevated,
                        in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .padding(.horizontal, DSSpacing.md)
        }
        .presentationDetents([.height(message != nil ? 190 : 155)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.dsBackgroundSecondary)
    }

    private func sourceRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(subtitle)
                        .font(DSFont.subheadline)
                        .foregroundStyle(Color.dsTextSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Attaches the source-picker sheet as a fallback "Choose a file" action
    /// inside tool views (for when the user cancels the initial picker).
    func fileSourcePicker(
        isPresented: Binding<Bool>,
        message: LocalizedStringKey? = nil,
        onLibrary: @escaping () -> Void,
        onBrowse: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            FileSourcePickerSheet(onLibrary: onLibrary, onBrowse: onBrowse, message: message)
        }
    }
}
