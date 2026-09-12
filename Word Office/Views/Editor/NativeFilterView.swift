import SwiftUI

/// Native iOS filter + sort sheet replacing ONLYOFFICE's web dropdown.
/// Two sections: Sort (A→Z / Z→A) and Value Filter (searchable checklist).
struct NativeFilterView: View {

    // MARK: - Init

    /// `items`    — rows from the OO filter panel.
    /// `onSort`   — called when the user picks a sort direction; sheet dismisses after.
    /// `onCommit` — called with selected ids (cancel=true → Cancel was tapped).
    init(
        items: [NativeFilterItem],
        onSort: @escaping (Bool) -> Void,
        onCommit: @escaping ([Int], Bool) -> Void
    ) {
        self.allItems = items
        self.onSort   = onSort
        self.onCommit = onCommit
        _selected = State(initialValue: Set(items.filter { $0.checked }.map { $0.id }))
    }

    // MARK: - State

    private let allItems: [NativeFilterItem]
    private let onSort:   (Bool) -> Void
    private let onCommit: ([Int], Bool) -> Void

    @State private var selected: Set<Int>
    @State private var search = ""

    // MARK: - Derived

    private var filtered: [NativeFilterItem] {
        guard !search.isEmpty else { return allItems }
        return allItems.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    private var allFilteredSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Title row
            HStack(alignment: .firstTextBaseline) {
                Text("Filter & Sort")
                    .font(.headline)
                Spacer()
                Text("\(selected.count) of \(allItems.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // ── Sort section ──────────────────────────────────────────────────
            sectionHeader("Sort")

            HStack(spacing: 10) {
                sortButton(
                    icon:  "arrow.up",
                    label: "A → Z",
                    ascending: true
                )
                sortButton(
                    icon:  "arrow.down",
                    label: "Z → A",
                    ascending: false
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // ── Filter values section ─────────────────────────────────────────
            sectionHeader("Filter Values")

            // Search
            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Select All
            selectAllRow

            Divider()
                .padding(.leading, 52)

            // Value list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { item in
                        itemRow(item)
                        if item.id != filtered.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }

            // Action bar
            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func sortButton(icon: String, label: String, ascending: Bool) -> some View {
        Button {
            onSort(ascending)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            TextField("Search values", text: $search)
                .font(.body)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.systemGray3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var selectAllRow: some View {
        Button {
            if allFilteredSelected {
                filtered.forEach { selected.remove($0.id) }
            } else {
                filtered.forEach { selected.insert($0.id) }
            }
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(allFilteredSelected ? Color.accentColor : Color(.systemGray5))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(allFilteredSelected ? .white : Color(.systemGray2))
                    }
                Text(allFilteredSelected ? "Deselect All" : "Select All")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: NativeFilterItem) -> some View {
        let isOn = selected.contains(item.id)
        return Button {
            if isOn { selected.remove(item.id) } else { selected.insert(item.id) }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.accentColor : Color(.systemGray5))
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                onCommit([], true)
            } label: {
                Text("Cancel")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                onCommit(Array(selected), false)
            } label: {
                Text("Apply Filter")
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
