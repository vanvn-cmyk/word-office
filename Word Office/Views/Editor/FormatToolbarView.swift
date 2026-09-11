import SwiftUI

/// Compact toolbar pinned above the software keyboard while editing.
/// Shows Undo/Redo on the left, a Format button in the center, and a
/// keyboard-dismiss button on the right.
struct FormatToolbarView: View {
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onFormat: () -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolbarButton("arrow.uturn.backward", action: onUndo, label: "Undo")
            toolbarButton("arrow.uturn.forward", action: onRedo, label: "Redo")

            Spacer()

            Button(action: onFormat) {
                Label("Format", systemImage: "textformat")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            .foregroundStyle(.primary)

            Spacer()

            toolbarButton("keyboard.chevron.compact.down", action: onDismissKeyboard, label: "Dismiss keyboard")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func toolbarButton(_ systemImage: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}
