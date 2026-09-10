import SwiftUI

/// Reusable in-app Library file picker sheet, shared across PDF tool views.
///
/// - Single-select: tap a row → `onPick([url])` + dismiss.
/// - Multi-select: toggle rows, confirm with "Add N files" button.
///
/// Pass a `filter` predicate to show only the relevant entry kinds
/// (e.g. `.pdf` only, or non-PDF office documents).
struct LibraryFilePicker: View {
    let entries: [LibraryEntry]
    let filter: (LibraryEntry) -> Bool
    let allowsMultipleSelection: Bool
    var emptyTitle: String = "No files in Library"
    var emptySystemImage: String = "doc.fill"
    var emptyMessage: String = "Import files first, then come back."
    let onPick: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedURLs: Set<URL> = []

    private var filteredEntries: [LibraryEntry] {
        entries.filter(filter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptyMessage)
                    )
                } else {
                    List(filteredEntries) { entry in
                        if allowsMultipleSelection {
                            let isSelected = selectedURLs.contains(entry.document.url)
                            Button {
                                let url = entry.document.url
                                if selectedURLs.contains(url) { selectedURLs.remove(url) }
                                else { selectedURLs.insert(url) }
                            } label: {
                                DSFileRow(ref: entry.document)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                isSelected
                                    ? Color.dsBrandPrimary.opacity(0.08)
                                    : Color(uiColor: .secondarySystemGroupedBackground)
                            )
                        } else {
                            Button {
                                onPick([entry.document.url])
                                dismiss()
                            } label: {
                                DSFileRow(ref: entry.document)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(allowsMultipleSelection ? "Add from Library" : "Pick from Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if allowsMultipleSelection {
                    ToolbarItem(placement: .confirmationAction) {
                        let count = selectedURLs.count
                        Button(count == 0 ? "Add" : "Add \(count)") {
                            onPick(Array(selectedURLs))
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedURLs.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
