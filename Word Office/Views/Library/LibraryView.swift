import SwiftUI

/// Library — the core-loop landing screen (Library-Architecture.md §4,
/// TuHoSo-Flow-Review.md §5 UC16). Renders the library once permission is
/// granted; empty/loading/error states live here so the parent shell doesn't
/// need to know them.
///
/// Content order matches UC16: an optional "Needs Attention" section
/// (`dueReminderEntries()`) always floats to the top, then non-due entries
/// grouped into date buckets (`groupedEntries()`) — both computed in
/// `LibraryViewModel+Grouping.swift`. The type-tab strip + favourite/view-mode/
/// filter row narrow the entry set before either of those run
/// (`LibraryViewModel+Filtering.swift`). Search bypasses both and shows a flat
/// match list (Library-Home-v10 mockup, Frame 3).
///
/// No `.navigationSubtitle` — not a confirmed-available API for this target,
/// so the adaptive subtitle is rendered as ordinary list content instead of
/// relying on an unverified system modifier (rule.md #6).
///
/// Layout note (v10 feedback round): the mockup put the Premium icon on the
/// same visual line as the title text itself. `.navigationTitle` renders the
/// real system Large Title, which can't host an inline custom view — so the
/// icon lives in `.toolbar(.topBarTrailing)` instead, the same native
/// mechanism the old standalone Filter button used. In practice this sits in
/// the compact bar just above the Large Title (standard Mail/Files/Reminders
/// pattern), not literally beside the title text. Verify against a real
/// Simulator screenshot before treating this as final — flat HTML mockups
/// can't preview real `UINavigationBar` behavior (rule.md, project convention).
///
/// No FAB here — `LibraryAddButton` (Create/Import/Scan) is drawn by
/// `RootView`'s custom bottom bar, alongside the tab pill, not layered into
/// this view's own content. See `RootView.customTabBar`.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(LibraryStore.self) private var store

    /// Invoked from the no-folder-yet empty state's CTA — only reachable when the
    /// user skipped folder onboarding earlier (Root/FolderPermissionOnboarding).
    let onRequestPermission: () async -> Void

    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .list

    var body: some View {
        NavigationStack {
            Group {
                if store.folderPermissionState == .checking {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.folderPermissionState == .notGranted {
                    EmptyStateView(
                        icon: "folder.badge.plus",
                        title: "No folder yet",
                        message: "Choose a folder to start tracking your documents",
                        action: (label: "Choose folder", handler: { Task { await onRequestPermission() } })
                    )
                } else if store.entries.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        icon: "tray",
                        title: "No documents yet",
                        message: "The granted folder has no supported files yet. Tap the + button to import your first document, or add files to the folder and pull down to rescan"
                    )
                } else {
                    libraryList
                }
            }
            .navigationTitle("Your Cabinet")
            // Explicit `.navigationBarDrawer(displayMode: .always)` — the default
            // `.automatic` placement let iOS 26 minimize search into a small
            // toolbar button, and with no real `TabView` in this shell (custom
            // bottom bar, see `RootView`) it had nowhere sane to dock that button
            // and rendered it inside the custom tab bar row instead, squeezing
            // that row and pushing search away from its expected spot under the
            // title. Pinning the placement forces the classic under-title field,
            // which has no minimize/toolbar-docking behavior to misfire.
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    premiumButton
                }
            }
            .task(id: store.folderPermissionState) { await viewModel.loadLibrary() }
            .refreshable { await viewModel.loadLibrary() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - List

    private var dueEntries: [LibraryEntry] { viewModel.dueReminderEntries() }
    private var groupedSections: [(bucket: DateBucket, entries: [LibraryEntry])] { viewModel.groupedEntries() }

    @ViewBuilder
    private var libraryList: some View {
        if !viewModel.searchText.isEmpty {
            searchResultsList
        } else if viewModel.isFiltering && dueEntries.isEmpty && groupedSections.isEmpty {
            filteredEmptyState
        } else {
            List {
                Section {
                } header: {
                    listHeader
                }

                if !dueEntries.isEmpty {
                    Section {
                        sectionRows(dueEntries)
                    } header: {
                        Label("Needs Attention", systemImage: "bell.badge.fill")
                            .foregroundStyle(Color.dsStatusWarning)
                    }
                }

                ForEach(groupedSections, id: \.bucket) { group in
                    Section(group.bucket.displayName) {
                        sectionRows(group.entries)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// One section's items, rendered as native `List` rows in `.list` mode or as
    /// a single grid "row" in `.grid` mode (Library-Home-v10 Frame 4 — same
    /// section structure, different item renderer).
    @ViewBuilder
    private func sectionRows(_ entries: [LibraryEntry]) -> some View {
        if viewMode == .grid {
            DocumentGrid(entries: entries) { entry in
                Task { await viewModel.recordOpen(entry.id) }
            } onToggleFavourite: { entry in
                Task { await viewModel.setFavourite(!entry.metadata.isFavourite, for: entry.id) }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(entries) { entry in
                row(for: entry)
            }
        }
    }

    private func row(for entry: LibraryEntry) -> some View {
        DocumentCard(entry: entry) {
            Task { await viewModel.recordOpen(entry.id) }
        } onToggleFavourite: {
            Task { await viewModel.setFavourite(!entry.metadata.isFavourite, for: entry.id) }
        }
        .contextMenu { contextMenu(for: entry) }
    }

    private var searchResultsList: some View {
        Group {
            if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                List {
                    ForEach(viewModel.searchResults) { entry in
                        row(for: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No results", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No documents match the current filter. Try a different tab or clear the status filter")
        } actions: {
            if viewModel.statusFilter != nil {
                Button("Clear status filter") { viewModel.statusFilter = nil }
            }
            if viewModel.favouritesOnly {
                Button("Clear favourites filter") { viewModel.favouritesOnly = false }
            }
        }
    }

    // MARK: - Header content (subtitle + stat hero + type tabs + view controls)

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(viewModel.heroCopy.subtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .textCase(nil)

            if !viewModel.isFiltering {
                LibraryHeroCard(copy: viewModel.heroCopy)
            }

            typeTabs
            viewControlsRow
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private var typeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(DocumentTypeFilter.allCases) { filter in
                    TypeTabButton(
                        filter: filter,
                        count: viewModel.count(for: filter),
                        isSelected: viewModel.typeFilter == filter
                    ) {
                        viewModel.typeFilter = filter
                    }
                }
            }
        }
        .textCase(nil)
    }

    /// Favourite toggle + Grid/List toggle + status Filter menu — moved here
    /// (below the type tabs, above the list) per v10 feedback: these affect how
    /// the list below is filtered/displayed, so they belong with the list, not
    /// in the navigation bar (which is for screen-level actions like Premium).
    /// Deliberately its own row rather than crammed onto the type-tabs row
    /// itself — an earlier round put them there and it starved the tab strip
    /// down to ~2 visible tabs before scrolling.
    private var viewControlsRow: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)

            Button {
                viewModel.favouritesOnly.toggle()
            } label: {
                Image(systemName: viewModel.favouritesOnly ? "star.fill" : "star")
                    .foregroundStyle(viewModel.favouritesOnly ? Color.dsStatusWarning : Color.dsBrandPrimary)
            }
            .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
            .accessibilityLabel(viewModel.favouritesOnly ? "Showing favourites only" : "Show favourites only")

            Button {
                viewMode = viewMode == .list ? .grid : .list
            } label: {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                    .foregroundStyle(Color.dsBrandPrimary)
            }
            .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
            .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")

            filterMenu
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    // MARK: - Toolbar

    private var premiumButton: some View {
        // TODO(paywall): no destination yet — the 7 iap_v1-iap_v7 variants in
        // product-strategy-master.md aren't built as real UI. This is the agreed
        // entry point placement; wire the tap once the paywall screen exists.
        Button {
        } label: {
            Image(systemName: "sparkles")
        }
        .foregroundStyle(Color.dsStatusWarning)
        .accessibilityLabel("Go Premium")
    }

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                Button {
                    viewModel.statusFilter = nil
                } label: {
                    Label("All", systemImage: "checkmark")
                }
                .disabled(viewModel.statusFilter == nil)

                ForEach(DocumentStatus.allCases) { status in
                    Button {
                        viewModel.statusFilter = status
                    } label: {
                        Label(status.displayName, systemImage: status.systemImage)
                    }
                    .disabled(viewModel.statusFilter == status)
                }
            }

            if viewModel.statusFilter != nil {
                Button(role: .destructive) {
                    viewModel.statusFilter = nil
                } label: {
                    Label("Clear filter", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: viewModel.statusFilter == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.dsBrandPrimary)
        }
        .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
        .accessibilityLabel("Filter by status")
    }

    // MARK: - Context menu (unchanged — long-press to change status)

    @ViewBuilder
    private func contextMenu(for entry: LibraryEntry) -> some View {
        Section("Change status") {
            ForEach(DocumentStatus.allCases) { status in
                Button {
                    Task { await viewModel.setStatus(status, for: entry.id) }
                } label: {
                    Label(status.displayName, systemImage: status.systemImage)
                }
                .disabled(status == entry.metadata.status)
            }
        }
    }
}

// MARK: - View mode

enum LibraryViewMode: String {
    case list
    case grid
}

// MARK: - Sub-views

private struct LibraryHeroCard: View {
    let copy: LibraryHeroCopy

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Text("\(copy.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.dsBrandPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title)
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                Text(copy.subtitle)
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .background(Color.dsBrandPrimarySubtle, in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct TypeTabButton: View {
    let filter: DocumentTypeFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(filter.displayName)
                    .font(DSFont.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .foregroundStyle(isSelected ? Color.dsBrandText : Color.dsTextSecondary)
            .background(
                Capsule().fill(isSelected ? Color.dsBrandPrimarySubtle : Color.dsBackgroundElevated)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.displayName), \(count) documents")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var dotColor: Color {
        switch filter {
        case .all:        Color.dsBrandPrimary
        case .word:       Color.dsDocumentWord
        case .excel:      Color.dsDocumentSpreadsheet
        case .powerPoint: Color.dsDocumentPresentation
        case .pdf:        Color.dsDocumentPDF
        }
    }
}
