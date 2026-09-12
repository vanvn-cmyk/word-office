import SwiftUI

/// Native sheet for adding a comment — replaces ONLYOFFICE's web dialog.
struct NativeCommentView: View {

    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var commentText = ""
    @FocusState private var textFocused: Bool

    private var canAdd: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                Text("Add Comment")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Text editor with placeholder
            ZStack(alignment: .topLeading) {
                TextEditor(text: $commentText)
                    .focused($textFocused)
                    .frame(minHeight: 120, maxHeight: 200)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)

                if commentText.isEmpty {
                    Text("Enter your comment…")
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }

            Spacer()

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .onAppear { textFocused = true }
    }

    // MARK: - Subviews

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button { onCancel() } label: {
                Text("Cancel")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                onCommit(commentText.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Add Comment")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canAdd ? .white : Color(.systemGray3))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        canAdd ? Color.accentColor : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
