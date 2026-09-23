import SwiftUI

/// Bottom sheet for choosing a file source — Cabinet (in-app) vs Device (Files/iCloud).
/// Visual pattern matches `ImageConvertPickerSheet` (row-based, explicit
/// `dsBackgroundSecondary` ground, no Liquid Glass bleed).
///
/// Presented on the Tools tab BEFORE navigation (so the picker appears on
/// the grid screen, not inside the tool view). Also available inside tool
/// views via `.fileSourcePicker(...)` as a "Choose a file" fallback.
struct FileSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let onLibrary: () -> Void
    let onBrowse: () -> Void
    /// Headline shown at the top of the sheet — tells the user what they're picking.
    var title: LocalizedStringKey = "Choose a source"
    /// Optional secondary context line shown below the title.
    /// When non-nil the sheet grows to 215 pt to accommodate it.
    var message: LocalizedStringKey? = nil

    /// On iPad (regular width), `.height(N)` detent renders as a narrow ~540pt
    /// form sheet floating in the center — not a full-width bottom sheet.
    /// `.medium` detent is full-width on iPad and looks correct; Spacer below
    /// the rows absorbs the extra height so content stays anchored at the top.
    private var isPad: Bool { hSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.sm)

            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, message != nil ? DSSpacing.xs : DSSpacing.md)

            if let message {
                Text(message)
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
            }

            VStack(spacing: 0) {
                sourceRow(
                    icon: "cabinet.fill",
                    tint: Color.dsBrandPrimary,
                    title: "From Cabinet",
                    subtitle: "Files you've saved in this app",
                    action: onLibrary
                )
                Divider()
                    .padding(.leading, 36 + DSSpacing.md * 2)
                sourceRow(
                    icon: "iphone",
                    tint: Color.dsBrandPrimary,
                    title: "From Device",
                    subtitle: "Files app, iCloud Drive and more",
                    action: onBrowse
                )
            }
            .background(Color.dsBackgroundElevated,
                        in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .padding(.horizontal, DSSpacing.md)

            // iPad uses .medium detent (full-width); Spacer fills the extra
            // height so the rows stay anchored at the top of the sheet.
            if isPad { Spacer(minLength: 0) }
        }
        // iPad: .medium = full-width bottom sheet.
        // iPhone: custom height = compact bottom sheet matching content.
        .presentationDetents(isPad ? [.medium] : [.height(message != nil ? 215 : 185)])
        .presentationDragIndicator(isPad ? .visible : .hidden)
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
        title: LocalizedStringKey = "Choose a source",
        message: LocalizedStringKey? = nil,
        onLibrary: @escaping () -> Void,
        onBrowse: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            FileSourcePickerSheet(onLibrary: onLibrary, onBrowse: onBrowse, title: title, message: message)
        }
    }
}
