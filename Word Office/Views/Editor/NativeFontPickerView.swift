import SwiftUI

/// Native font picker sheet for Word documents.
struct NativeFontPickerView: View {

    let onCommit: (_ fontName: String) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private static let fonts: [String] = [
        // Common document fonts
        "Arial", "Arial Black", "Arial Narrow",
        "Calibri", "Calibri Light",
        "Cambria", "Cambria Math",
        "Comic Sans MS",
        "Courier New",
        "Georgia",
        "Helvetica", "Helvetica Neue",
        "Impact",
        "Palatino Linotype",
        "Tahoma",
        "Times New Roman",
        "Trebuchet MS",
        "Verdana",
        // System fonts
        "-apple-system",
        "SF Pro", "SF Pro Display", "SF Pro Text",
        "New York",
        // Mono
        "Courier", "Menlo", "Monaco",
    ]

    private var filtered: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Self.fonts }
        return Self.fonts.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { font in
                Button {
                    onCommit(font)
                } label: {
                    Text(font)
                        .font(.custom(font, size: 16))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search fonts")
            .navigationTitle("Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
