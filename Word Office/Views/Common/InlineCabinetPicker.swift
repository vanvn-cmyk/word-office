import SwiftUI

/// Full-body inline cabinet file picker — replaces the calling tool view's
/// content area when the user taps "From Cabinet" in `FileSourcePickerSheet`.
///
/// Not a sheet. The parent tool view swaps its body content for this view
/// so the file list appears directly on-screen with no second modal.
/// The parent adjusts its `prominentInlineTitle` to "Cabinet" while this is
/// shown; this view owns the navigation bar's Cancel (and optional Add) button.
struct InlineCabinetPicker: View {
    let entries: [LibraryEntry]
    let filter: ((LibraryEntry) -> Bool)?
    let allowsMultipleSelection: Bool
    var emptyTitle: String = "No files in Cabinet"
    var emptyMessage: String = "Import files first — they'll appear here."
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void
    /// Optional: if provided, shows a "From Device" row pinned to the bottom.
    var onBrowse: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var libraryStore
    @State private var selectedURLs: Set<URL> = []

    private var filtered: [LibraryEntry] {
        guard let filter else { return entries }
        return entries.filter(filter)
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 0) {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "cabinet.fill",
                        description: Text(emptyMessage)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let onBrowse {
                        browseSection(onBrowse: onBrowse)
                    }
                }
                .background(Color.dsBackgroundSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(filtered) { entry in
                            if allowsMultipleSelection {
                                multiCard(entry)
                            } else {
                                singleCard(entry)
                            }
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.sm)
                    .padding(.bottom, DSSpacing.sm)
                }
                .background(Color.dsBackgroundSecondary)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let onBrowse {
                        browseSection(onBrowse: onBrowse)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onCancel() } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
            if allowsMultipleSelection {
                ToolbarItem(placement: .confirmationAction) {
                    let count = selectedURLs.count
                    Button(count == 0 ? "Add" : "Add \(count)") {
                        onPick(Array(selectedURLs))
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedURLs.isEmpty)
                }
            }
        }
    }

    // MARK: - Card rows

    @ViewBuilder
    private func singleCard(_ entry: LibraryEntry) -> some View {
        let url = entry.document.url
        let isNew = libraryStore.recentlyAddedURLs.contains(url)
        Button {
            libraryStore.clearNew(url)
            onPick([url])
        } label: {
            DSFileRow(ref: entry.document)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
                .overlay(alignment: .topTrailing) {
                    if isNew { NewBadge().padding(.top, 8).padding(.trailing, 4) }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func multiCard(_ entry: LibraryEntry) -> some View {
        let url = entry.document.url
        let isSelected = selectedURLs.contains(url)
        let isNew = libraryStore.recentlyAddedURLs.contains(url)
        Button {
            if isSelected { selectedURLs.remove(url) } else {
                libraryStore.clearNew(url)
                selectedURLs.insert(url)
            }
        } label: {
            HStack {
                DSFileRow(ref: entry.document)
                Spacer(minLength: DSSpacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected ? Color.dsBrandPrimary.opacity(0.08) : Color(uiColor: .systemBackground)),
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
            .overlay(alignment: .topTrailing) {
                if isNew { NewBadge().padding(.top, 8).padding(.trailing, 4) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Multi-select confirm bar

    private var multiSelectBar: some View {
        let count = selectedURLs.count
        return VStack(spacing: 0) {
            Divider()
            Button {
                onPick(Array(selectedURLs))
            } label: {
                Text(count == 0 ? "Add" : "Add \(count) File\(count == 1 ? "" : "s")")
                    .font(DSFont.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .disabled(selectedURLs.isEmpty)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Browse footer

    @ViewBuilder
    private func browseSection(onBrowse: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("File not in Cabinet?")
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextSecondary)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
            Button {
                onBrowse()
            } label: {
                Label("Browse from Device", systemImage: "iphone")
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsBrandPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
            }
            .buttonStyle(.plain)
            .padding(.bottom, DSSpacing.sm)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

/// Small "New" pill badge shown on file rows when a tool operation just
/// committed a file to the Library — clears when the user taps the file.
struct NewBadge: View {
    var body: some View {
        Text("New")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.dsBrandPrimary, in: Capsule())
    }
}
