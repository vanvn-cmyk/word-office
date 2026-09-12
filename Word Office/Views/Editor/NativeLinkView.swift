import SwiftUI

/// Native sheet for inserting a hyperlink — replaces ONLYOFFICE's web dialog.
struct NativeLinkView: View {

    /// Called when user taps Insert. `url` is the raw URL; `text` is the display text.
    let onCommit: (String, String) -> Void
    let onCancel: () -> Void

    @State private var urlText = ""
    @State private var displayText = ""
    @FocusState private var urlFocused: Bool

    private var canInsert: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Title
            HStack {
                Text("Insert Link")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // URL field
            fieldSection(label: "URL") {
                TextField("https://", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($urlFocused)
            }
            .padding(.bottom, 14)

            // Display text field
            fieldSection(label: "Display Text (optional)") {
                TextField("Link text", text: $displayText)
                    .autocorrectionDisabled()
            }

            Spacer()

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .onAppear { urlFocused = true }
    }

    // MARK: - Subviews

    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
                .padding(.horizontal, 20)

            content()
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
        }
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
                let url = urlText.trimmingCharacters(in: .whitespaces)
                let text = displayText.trimmingCharacters(in: .whitespaces)
                onCommit(url, text.isEmpty ? url : text)
            } label: {
                Text("Insert")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canInsert ? .white : Color(.systemGray3))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        canInsert ? Color.accentColor : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canInsert)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
