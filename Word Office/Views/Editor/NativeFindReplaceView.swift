import SwiftUI

/// Native Find & Replace sheet — replaces ONLYOFFICE's web dialog on mobile.
struct NativeFindReplaceView: View {

    let onCommit: (_ find: String, _ replace: String, _ replaceAll: Bool) -> Void
    let onCancel: () -> Void

    @State private var findText    = ""
    @State private var replaceText = ""
    @State private var replaceAll  = false
    @FocusState private var findFocused: Bool

    private var canAction: Bool {
        !findText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                Text("Find & Replace")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            fieldSection(label: "Find") {
                TextField("Search text…", text: $findText)
                    .autocorrectionDisabled()
                    .focused($findFocused)
            }
            .padding(.bottom, 12)

            fieldSection(label: "Replace With") {
                TextField("Replacement text…", text: $replaceText)
                    .autocorrectionDisabled()
            }
            .padding(.bottom, 12)

            Toggle(isOn: $replaceAll) {
                Text("Replace All Occurrences")
                    .font(.subheadline)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .onAppear { findFocused = true }
    }

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
                let f = findText.trimmingCharacters(in: .whitespaces)
                let r = replaceText.trimmingCharacters(in: .whitespaces)
                onCommit(f, r, replaceAll)
            } label: {
                Text(replaceAll ? "Replace All" : (replaceText.isEmpty ? "Find" : "Replace"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canAction ? .white : Color(.systemGray3))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        canAction ? Color.accentColor : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
