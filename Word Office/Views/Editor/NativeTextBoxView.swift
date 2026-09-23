import SwiftUI

/// Native sheet for inserting a text box on a PPT slide.
/// User types content here; the box is placed at the centre of the slide with the text pre-filled.
struct NativeTextBoxView: View {

    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var content = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                Text("Insert Text Box")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))

                if content.isEmpty {
                    Text("Type text (optional)")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .focused($textFocused)
            }
            .frame(height: 110)
            .padding(.horizontal, 16)

            Text("Placed at centre of slide")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .onAppear { textFocused = true }
    }

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
                onCommit(content.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Insert")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
