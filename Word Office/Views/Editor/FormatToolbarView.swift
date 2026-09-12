import SwiftUI

/// Compact toolbar pinned above the software keyboard while editing.
/// Shows Undo/Redo on the left and a keyboard-dismiss button on the right.
/// (Format button removed — the tabbed EditorTopToolbar above covers all formatting.)
struct FormatToolbarView: View {
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onFormat: () -> Void          // kept for API compatibility, not shown
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton("arrow.uturn.backward", action: onUndo,            label: "Undo")
            toolbarButton("arrow.uturn.forward",  action: onRedo,            label: "Redo")
            Spacer()
            toolbarButton("keyboard.chevron.compact.down",
                          action: onDismissKeyboard, label: "Dismiss keyboard")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func toolbarButton(_ icon: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}
