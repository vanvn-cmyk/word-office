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
/// Layout note (Session 14): search + view-mode toggle + filter menu live
/// inline in `searchAndActionsRow` at the top of the list content, rather
/// than split between `.searchable` (drawer) and a row below the type tabs.
/// The confusion of `.searchable`'s duplicate X icons (in-field clear +
/// toolbar Cancel) is what triggered the move. The premium crown stays in
/// `.toolbar(.topBarTrailing)` because it's a screen-level action (paywall
/// entry point), not a list-management control — same placement pattern
/// News+/Podcasts+ use for their subscription marks.
///
/// No FAB here — `LibraryAddButton` (Create/Import/Scan) is drawn by
/// `RootView`'s custom bottom bar, alongside the tab pill, not layered into
/// this view's own content. See `RootView.customTabBar`.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DSToastPresenter.self) private var toaster

    // Search focus state moved into `LibrarySearchAndActionsBar` — see
    // that view's docstring for the perf rationale. Keeping `@FocusState`
    // here caused every tap on the search field to re-run
    // `LibraryView.body`, which re-diffed the entire `listHeader` (title
    // row with the PremiumButton gradient, the horizontal type-tabs
    // strip of Liquid Glass chips, and the hero card), producing the
    // click-lag the user flagged.

    /// Invoked from the no-folder-yet empty state's CTA — only reachable when the
    /// user tapped "Maybe Later" on onboarding S4.
    let onRequestPermission: () async -> Void

    /// Invoked from a row's kebab menu "Edit" — the parent (`RootView`)
    /// owns the editor sheet state because it has access to `container` for
    /// `EditorPlaceholderView(container:ref:)`. Threading a callback keeps
    /// `LibraryView` unaware of the container.
    let onOpenEditor: (DocumentRef) -> Void

    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .list

    /// Local sheet state for "Save to Files" — the `UIDocumentPickerViewController`
    /// wrapper needs only a URL (no container dependency), so it stays here
    /// instead of routing through `RootView`.
    @State private var exportingRef: DocumentRef?

    /// Session 19 — pending "Convert to ZIP" request. Set from the kebab
    /// action so the confirmation dialog can ask BEFORE the zip runs
    /// (unlike Sign/Fill's post-op preview: zip has no visual preview
    /// worth waiting for, and PDF-sized zips can take seconds). Cleared
    /// once the user picks a resolution.
    @State private var pendingZipRequest: PendingZipRequest?

    /// Session 19 code-review P1 fix — records that the current import
    /// conflict dialog is dismissing because the user picked one of the
    /// resolution buttons (Keep Both / Replace / Skip / Cancel), NOT
    /// because they tapped outside the sheet. The dialog binding's
    /// setter can't tell those apart on its own: `role: .cancel` on the
    /// Cancel button and every other button all fire the binding's
    /// `set(false)`, and the enqueued `Task { await
    /// resolveImportConflict(...) }` hasn't cleared
    /// `pendingImportConflict` yet at that point — so the setter would
    /// misread every button tap as "user swiped out" and call
    /// `cancelImportBatch()`, silently aborting the whole batch. Every
    /// resolution button flips this flag to `true` BEFORE its Task
    /// schedules; the setter honours the flag and skips the cancel
    /// path. Same shape as `PreviewConfirmSheet.didCommit`.
    @State private var didPickImportResolution = false

    /// Filter popover visibility — `.popover(isPresented:)
    /// .presentationCompactAdaptation(.popover)` (iOS 16.4+) forces a
    /// true anchored popover on iPhone instead of the default sheet
    /// fallback, so the filter list appears directly below the icon
    /// with an arrow pointing back to it (accepted trade-off: reads
    /// slightly iPad-styled on iPhone, but avoids the Menu SwiftUI
    /// heuristic that was covering the icon when the content grew).
    @State private var isFilterPopoverPresented = false
    /// Presented from the crown `PremiumButton` in the `titleRow`.
    /// TODO(paywall): route through a shared `PaywallCoordinator` if the
    /// crown ever fires from more than these two screens.
    @State private var isPaywallPresented = false

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
                } else if store.entries.isEmpty && viewModel.hasLoadedOnce {
                    // titleRow shown ABOVE the empty state so "Your Cabinet"
                    // + premium crown stays visible even when the library
                    // is empty — matches iOS Photos / Notes convention
                    // (title always shows regardless of content), and
                    // preserves the paywall entry point (crown) at first
                    // launch when it's arguably most likely to convert.
                    // Previous version rendered the raw `EmptyStateView`
                    // with no title bar, so users landed on an anonymous
                    // "No documents yet" screen with no app identity above
                    // it.
                    VStack(spacing: 0) {
                        titleRow
                            .padding(.horizontal, DSSpacing.lg)
                            .padding(.top, DSSpacing.sm)
                        EmptyStateView(
                            icon: "tray",
                            title: "No documents yet",
                            message: "The granted folder has no supported files yet. Tap the + button to import your first document, or add files to the folder and pull down to rescan"
                        )
                    }
                } else {
                    libraryList
                }
            }
            // No `.navigationTitle` and no `.toolbar` — the title "Your
            // Cabinet" and the premium crown badge both live inline in
            // `titleRow` at the top of the list content, on the same
            // horizontal line. Rationale: iOS 26 always wraps toolbar
            // items in a Liquid Glass surface whose shape we can't force
            // to a perfect circle (ovoid capsule persisted through
            // buttonBorderShape.circle, buttonStyle.plain + own material,
            // glassEffect on button, and even the no-Button ZStack with
            // onTapGesture approach). Rendering both title + crown as
            // ordinary SwiftUI views inside content bypasses that path
            // entirely, and puts them on the parallel line the user
            // asked for as a bonus.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: store.folderPermissionState) { await viewModel.loadLibrary() }
            .refreshable { await viewModel.loadLibrary() }
            .errorAlert($viewModel.errorMessage)
            .sheet(item: $exportingRef) { ref in
                DocumentPickerExporter(urls: [ref.url]) { pickedURLs in
                    // Fires only when the user actually picks a
                    // destination and the file lands there — cancel
                    // path is silent per HIG. `pickedURLs` reports
                    // the copy's new location (not `ref.url`), so a
                    // curious future maintainer could extend the
                    // toast to name the destination folder; today it
                    // just confirms "the file left the app" using
                    // the source filename the user recognises.
                    guard !pickedURLs.isEmpty else { return }
                    toaster.show(.success, title: "Your document was saved to Files", filename: ref.name)
                }
                .ignoresSafeArea()
            }
            // `.fullScreenCover` — Paywall is a full-page product-selling
            // surface (hero + features + plans + CTA), not a modal
            // decision on top of context. Sheet's card-over-content
            // idiom competes with the sheet's own visual weight; full-
            // screen frees the paywall to own the whole viewport, the
            // way App Store subscription screens themselves do.
            .fullScreenCover(isPresented: $isPaywallPresented) {
                PaywallView()
            }
            // Import name-collision resolver (Session 19). Fires once per
            // conflicted URL in a batch — matches iOS Files.app's
            // per-file "Keep Both / Replace / Skip / Cancel" flow.
            // Ordering (safer first, destructive middle, cancel last)
            // follows the same rule as `PreviewConfirmSheet`.
            .confirmationDialog(
                importConflictTitle,
                isPresented: importConflictDialogBinding,
                titleVisibility: .visible,
                presenting: viewModel.pendingImportConflict
            ) { _ in
                Button("Keep Both") {
                    didPickImportResolution = true
                    Task { await viewModel.resolveImportConflict(.keepBoth) }
                }
                Button("Replace", role: .destructive) {
                    didPickImportResolution = true
                    Task { await viewModel.resolveImportConflict(.replace) }
                }
                Button("Skip") {
                    didPickImportResolution = true
                    Task { await viewModel.resolveImportConflict(.skip) }
                }
                Button("Cancel", role: .cancel) {
                    didPickImportResolution = true
                    viewModel.cancelImportBatch()
                }
            } message: { conflict in
                Text("\u{201C}\(conflict.filename)\u{201D} is already in your Library. Keep both copies, replace the existing one, or skip this file?")
            }
            // Fire the batch-summary toast once per import batch — the VM
            // publishes `lastImportBatchSummary` when the queue drains or
            // the user cancels; clear it back to nil so a subsequent
            // batch with the same summary still fires.
            .onChange(of: viewModel.lastImportBatchSummary) { _, summary in
                guard let summary else { return }
                toaster.show(.success, title: summary)
                viewModel.lastImportBatchSummary = nil
            }
            // Convert-to-ZIP confirmation (Session 19) — asks BEFORE the
            // zip runs so a Cancel path saves the wait on a large PDF.
            // "Replace with ZIP" is destructive (deletes source PDF after
            // the archive lands) → `role: .destructive` per HIG. Same
            // ordering rule as `PreviewConfirmSheet` and the Import
            // conflict dialog: safer first, destructive middle, cancel
            // automatic.
            .confirmationDialog(
                zipDialogTitle,
                isPresented: zipDialogBinding,
                titleVisibility: .visible,
                presenting: pendingZipRequest
            ) { request in
                Button("Keep Both") {
                    Task { await commitConvertToZip(entryID: request.entryID, name: request.filename, deleteSource: false) }
                    pendingZipRequest = nil
                }
                Button("Replace with ZIP", role: .destructive) {
                    Task { await commitConvertToZip(entryID: request.entryID, name: request.filename, deleteSource: true) }
                    pendingZipRequest = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingZipRequest = nil
                }
            } message: { request in
                Text("Would you like to keep \u{201C}\(request.filename)\u{201D} alongside the new ZIP archive, or replace it with the archive?")
            }
        }
    }

    /// Dynamic title for the ZIP dialog — same reason `importConflictTitle`
    /// is hoisted out (`confirmationDialog(_:isPresented:presenting:)` takes
    /// a `LocalizedStringKey` at the outer level, not a per-`presenting`
    /// expression).
    private var zipDialogTitle: String {
        if let name = pendingZipRequest?.filename {
            return "Convert \u{201C}\(name)\u{201D} to ZIP"
        }
        return "Convert to ZIP"
    }

    private var zipDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingZipRequest != nil },
            set: { newValue in
                if !newValue { pendingZipRequest = nil }
            }
        )
    }

    /// Local `.confirmationDialog` payload for the ZIP flow — kept as a
    /// `@State` on the view rather than the VM because the choice is a
    /// pure UI concern (VM doesn't need to know a dialog is pending;
    /// once the user picks, the view calls the VM once with the
    /// decision baked into a param).
    private struct PendingZipRequest: Identifiable, Sendable {
        let id = UUID()
        let entryID: String
        let filename: String
    }

    /// Dialog title reads the current conflict's filename; `presenting:` on
    /// `.confirmationDialog` doesn't accept a dynamic title expression, so
    /// this computed hoists the read into the enclosing view.
    private var importConflictTitle: String {
        if let name = viewModel.pendingImportConflict?.filename {
            return "\u{201C}\(name)\u{201D} already exists"
        }
        return "File already exists"
    }

    /// Two-way binding for `.confirmationDialog(isPresented:)` — reading
    /// `pendingImportConflict != nil` for present, writing `false` back as
    /// "user dismissed". Only routes through `cancelImportBatch()` when the
    /// dismissal came from a swipe-out / tap-outside (i.e. NOT from a
    /// resolution button); the resolution buttons flip
    /// `didPickImportResolution` first, and the flag is cleared here on
    /// the way out so the next dialog gets a fresh reading. Writing `true`
    /// is a no-op — only the VM's queue may open the dialog, and it does
    /// that by setting `pendingImportConflict` directly.
    ///
    /// This split was added in the Session 19 code-review P1 fix — the
    /// previous unconditional cancel-on-dismiss was silently aborting the
    /// whole batch on EVERY user tap because the resolution buttons
    /// schedule their VM work via `Task { ... }` and don't clear
    /// `pendingImportConflict` synchronously.
    private var importConflictDialogBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingImportConflict != nil },
            set: { newValue in
                if !newValue {
                    if !didPickImportResolution && viewModel.pendingImportConflict != nil {
                        // Swipe-out / tap-outside — user didn't pick any
                        // button. Treat as Cancel to stop the batch.
                        viewModel.cancelImportBatch()
                    }
                    didPickImportResolution = false
                }
            }
        )
    }

    // MARK: - List

    private var dueEntries: [LibraryEntry] { viewModel.dueReminderEntries() }
    private var groupedSections: [(bucket: DateBucket, entries: [LibraryEntry])] { viewModel.groupedEntries() }

    /// "Get Started" only when every file added today is a pre-seeded sample
    /// (name starts with "Get Started"). As soon as the user imports their own
    /// file, the bucket reverts to "Today" so the label remains accurate.
    private func sectionTitle(for group: (bucket: DateBucket, entries: [LibraryEntry])) -> String {
        guard group.bucket == .today else { return group.bucket.displayName }
        let allSeeded = group.entries.allSatisfy { $0.document.name.hasPrefix("Get Started") }
        return allSeeded ? "Get Started" : "Today"
    }

    private var libraryList: some View {
        // Single List for every state (default / filter-empty / search-
        // active / search-empty). Search results and no-result placeholders
        // render as list rows UNDER `listHeader`, never replace it — so the
        // search field + Cancel button stay reachable and the user is
        // never stuck on a screen with no way back.
        List {
            Section {
                listHeader
                    // Zero top inset — pulls the title row flush to
                    // the safe-area top (status bar) so there's no
                    // dead space between "11:22" and "Your Cabinet".
                    // Zero horizontal — insetGrouped List's own 20pt
                    // gutter is now the outer margin (matches Tools'
                    // `lg = 20` padding standard); adding sm=12 on top
                    // was double-indenting the title vs Tools.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DSSpacing.xxs, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !viewModel.searchText.isEmpty {
                // Search mode — replace normal library content with the
                // matching rows (or a no-results placeholder). `listHeader`
                // above still carries the search field + Cancel.
                if viewModel.searchResults.isEmpty {
                    Section {
                        searchNoResultsContent
                            .listRowInsets(EdgeInsets(top: DSSpacing.xl, leading: DSSpacing.md, bottom: DSSpacing.xl, trailing: DSSpacing.md))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        // `sectionRows(...)` — NOT a raw `ForEach { row(for:) }`
                        // — so the search results honor the user's `viewMode`
                        // toggle (grid vs list) exactly like the normal
                        // grouped-by-date sections below. The earlier code
                        // hardcoded `row(for:)` (always list rows), so a user
                        // browsing in grid mode saw their layout silently
                        // flip to a list the moment they typed the first
                        // character into the search field.
                        sectionRows(viewModel.searchResults)
                    }
                }
            } else if viewModel.isFiltering && dueEntries.isEmpty && groupedSections.isEmpty {
                // Filter yields no results — render the empty state as
                // a list row so the chip strip above stays tappable
                // and the Show-all button gives an obvious way back.
                Section {
                    filteredEmptyStateContent
                        .listRowInsets(EdgeInsets(top: DSSpacing.xl, leading: DSSpacing.md, bottom: DSSpacing.xl, trailing: DSSpacing.md))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                if !dueEntries.isEmpty {
                    Section {
                        sectionRows(dueEntries)
                    } header: {
                        Label("Needs Attention", systemImage: "bell.badge.fill")
                            .foregroundStyle(Color.dsStatusWarning)
                    }
                }

                ForEach(groupedSections, id: \.bucket) { group in
                    Section(sectionTitle(for: group)) {
                        sectionRows(group.entries)
                    }
                }
            }

            // Fake trailing spacer section — reserves 120pt of
            // scroll-content space after the last real row so the
            // tab pill never visually overlaps content at max
            // scroll. `safeAreaInset` + `contentMargins` on List
            // both proved unreliable through the NavigationStack
            // chain (Session 12 repeated user reports); an actual
            // hidden Section is guaranteed to occupy List height.
            Section {
                Color.clear
                    .frame(height: DSTabBarMetrics.listContentTrailingSpacer)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        // Zeroes the top scroll margin — insetGrouped's default is
        // ~30pt above the first section which, combined with the
        // now-hidden navbar, left an obvious gap between the status
        // bar and the "Your Cabinet" title. `Tools` avoids this via
        // `.prominentInlineTitle` (title lives in the navbar so the
        // scroll content starts flush); Library uses a custom large
        // title in-content, so we tighten manually here.
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(DSSpacing.xxs)
        .autoHidesTabBarOnScroll()
    }

    /// One section's items, rendered as native `List` rows in `.list` mode or as
    /// a single grid "row" in `.grid` mode (Library-Home-v10 Frame 4 — same
    /// section structure, different item renderer).
    @ViewBuilder
    private func sectionRows(_ entries: [LibraryEntry]) -> some View {
        if viewMode == .grid {
            DocumentGrid(
                entries: entries,
                onTap: { entry in
                    Task { await viewModel.recordOpen(entry.id) }
                    onOpenEditor(entry.document)
                },
                onSaveExport: { entry in
                    exportingRef = entry.document
                },
                onToggleFavourite: { entry in
                    Task { await performToggleFavourite(entry: entry) }
                },
                onRename: { entry, newStem in
                    await performRename(entryID: entry.id, to: newStem)
                },
                onConvertToZip: { entry in
                    performConvertToZip(entryID: entry.id, name: entry.document.name)
                },
                onDeleteFile: { entry in
                    Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) }
                }
            )
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
        DocumentCard(
            entry: entry,
            onTap: {
                Task { await viewModel.recordOpen(entry.id) }
                onOpenEditor(entry.document)
            },
            onSaveExport: {
                exportingRef = entry.document
            },
            onToggleFavourite: {
                Task { await performToggleFavourite(entry: entry) }
            },
            onRename: { newStem in
                await performRename(entryID: entry.id, to: newStem)
            },
            onConvertToZip: {
                Task { await performConvertToZip(entryID: entry.id, name: entry.document.name) }
            },
            onDeleteFile: {
                Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) }
            }
        )
        // Turn each row into its own rounded card with vertical breathing
        // room instead of a shared insetGrouped section card with divider
        // lines. `listRowBackground(.clear)` removes the system card fill;
        // the inner `.background(...)` paints an individual card per row.
        //
        // Horizontal `sm = 12` moved from row wrapper INSIDE the card
        // (background wraps the padded content, so the card frame — not
        // its content — now sits at the row edge). Combined with zero
        // `listRowInsets.leading/trailing`, the card visible edge sits at
        // insetGrouped's default 20pt gutter → matches Tools' `lg = 20`
        // horizontal padding standard.
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous).strokeBorder(Color.dsBorderSubtle))
        // Apple-standard subtle list-row card shadow — Level 2 elevation
        // (list rows in insetGrouped), NOT Level 3 (floating cards /
        // FAB). Single subtle contact layer keeps rows grounded on the
        // gray backdrop without the "heavily elevated" look the earlier
        // 2-layer ambient+contact recipe produced. Materials over
        // shadows is Apple's iOS 26 direction; the border already
        // carries most of the row/card separation, so shadow can be
        // dialled way back.
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Adds `xs=8` horizontal listRowInsets on top of insetGrouped's
        // own 20pt gutter → each card is inset ~28pt from the screen
        // edge. Dialled from `sm=12` (too narrow) → `xs=8` per user
        // feedback ("the cards were shrinking too much"). Middle ground
        // between full-width and heavily inset.
        .listRowInsets(EdgeInsets(top: DSSpacing.xxs, leading: DSSpacing.xs, bottom: DSSpacing.xxs, trailing: DSSpacing.xs))
        .contextMenu { contextMenu(for: entry) }
    }

    /// Inline no-result content for search (dropped into the main list
    /// as a Section body) — mirrors `filteredEmptyStateContent`'s shape
    /// so the two empty states read consistently. Not a
    /// `ContentUnavailableView` because that view wants a full-screen
    /// pane, which would hide the search field + Cancel above it and
    /// leave the user unable to try a different query or back out.
    private var searchNoResultsContent: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)
                .padding(.bottom, DSSpacing.xxs)

            Text("No Results for \u{201C}\(viewModel.searchText)\u{201D}")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)

            Text("Check the spelling or try a new search")
                .font(DSFont.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Inline empty-state row rendered UNDER `listHeader` (chip strip
    /// stays visible above it) when the current filter combination
    /// yields no documents. Uses a plain VStack instead of
    /// `ContentUnavailableView` because that view wants a full-screen
    /// pane, whereas here the chip strip must still be reachable at the
    /// top. Each active filter gets its own clear action; the type-tab
    /// case is what users hit most often (tapping `Word`/`Excel` on an
    /// empty library), so `Show all types` leads the button stack.
    private var filteredEmptyStateContent: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)
                .padding(.bottom, DSSpacing.xxs)

            Text("No results")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)

            Text("No documents match the current filter. Try a different tab or clear the status filter")
                .font(DSFont.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DSSpacing.xs) {
                if viewModel.typeFilter != .all {
                    Button("Show all types") { viewModel.typeFilter = .all }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                if viewModel.statusFilter != nil {
                    Button("Clear status filter") { viewModel.statusFilter = nil }
                }
                if viewModel.favouritesOnly {
                    Button("Clear favourites filter") { viewModel.favouritesOnly = false }
                }
            }
            .padding(.top, DSSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header content (subtitle + stat hero + type tabs + view controls)

    private var listHeader: some View {
        // `md = 16`, not `sm = 12` — the search pill (`.roundIconButtonSurface`
        // / its own capsule) and `LibraryHeroCard` each carry the shared
        // "2-layer ambient shadow" recipe (`radius: 14, y: 6`, same values
        // as `ToolCardSurface`), which reaches ~20pt below the element it's
        // on. At `sm = 12` that shadow from the search row bled into the
        // hero card's top edge right below it — read as a dark seam between
        // the two, same failure class as the "odd dark bands" the user
        // flagged in `typeTabs` (see that comment), just from stacked
        // per-view shadows overlapping instead of a shared Liquid Glass
        // sampling region. `md` gives the shadow room to fall off before
        // the next element starts, without touching the shared shadow
        // recipe other screens rely on.
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Title + hero + chip strip stay mounted at every state.
            // Previous attempts to collapse them on search focus forced
            // the enclosing insetGrouped List to reflow row heights, and
            // no timing curve masked that reflow — it always read as
            // choppy pause. Keeping the header mounted is the
            // one animation-free path: only `searchAndActionsRow` itself
            // animates its own icon → Cancel swap, and the results below
            // just re-populate as the query changes. The chip strip
            // staying visible is a bonus — the user can narrow by type
            // and search at the same time without breaking flow.
            titleRow
            searchAndActionsRow
            if !viewModel.isFiltering {
                LibraryHeroCard(copy: viewModel.heroCopy)
            }
            typeTabs
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private var typeTabs: some View {
        // `GlassEffectContainer` groups every chip's Liquid Glass surface
        // into one shared sampling region — without it, adjacent chips
        // sample independently and can visibly disagree on tone, breaking
        // the "one continuous control strip" read (Apple's own toolbar
        // pattern — see `references/liquid-glass.md`).
        //
        // Chip strip's ScrollView respects the enclosing List row's
        // insetGrouped gutter, but the hero card's rounded rect
        // (`DSRadius.card` corners) reads visually pinched INWARD at
        // the corners while the first chip's Capsule starts flush at
        // the row edge — that mismatched by a few pt, which the user
        // flagged. `.padding(.horizontal, xs)` (8pt) shifts the strip
        // right so its leading pill edge aligns with the hero card's
        // straight outline segment above.
        // No `GlassEffectContainer` wrap — its shared sampling region
        // bled a subtle ambient shadow into the gaps BETWEEN chips
        // (the odd dark bands the user flagged in the strip). Each chip
        // now renders its own Liquid Glass independently; the small
        // tone variance between adjacent chips is invisible in
        // practice, and the gaps stay clean white.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(sortedTypeFilters) { filter in
                    TypeTabButton(
                        filter: filter,
                        count: viewModel.count(for: filter),
                        isSelected: viewModel.typeFilter == filter,
                        reduceMotion: reduceMotion
                    ) {
                        viewModel.typeFilter = filter
                    }
                }
            }
            .padding(.horizontal, DSSpacing.xs)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: sortedTypeFilters)
        }
        .textCase(nil)
    }

    /// Order the type-tab chips so the four document-type chips with the
    /// most matching files sit next to `● All`, pushing empty types to
    /// the trailing edge. `.all` always leads so the user has one stable
    /// tap-back target regardless of the library composition. Ties keep
    /// `DocumentTypeFilter.allCases` order (Word → Excel → PowerPoint →
    /// PDF) so a fresh library with zero of everything still reads in a
    /// predictable order.
    private var sortedTypeFilters: [DocumentTypeFilter] {
        let indexed = DocumentTypeFilter.allCases.enumerated()
        let typed = indexed.filter { $0.element != .all }
        let sorted = typed.sorted { lhs, rhs in
            let lc = viewModel.count(for: lhs.element)
            let rc = viewModel.count(for: rhs.element)
            if lc != rc { return lc > rc }
            return lhs.offset < rhs.offset
        }
        return [.all] + sorted.map(\.element)
    }

    // MARK: - Title + premium

    /// Big page title on the leading edge, premium crown badge on the
    /// trailing edge, same baseline. Rendered inline in list content so
    /// the crown escapes iOS 26's toolbar auto-Liquid-Glass wrap (which
    /// forces an ovoid capsule shape we can't override reliably).
    ///
    /// The `.padding(.top, DSSpacing.sm)` compensates the zero
    /// `listRowInsets.top` on the section: without it, the title butted
    /// right against the status bar / Dynamic Island. 12pt gives a
    /// comfortable gap that still reads as "close, not floating".
    private var titleRow: some View {
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            Text("Your Cabinet")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DSSpacing.sm)

            PremiumButton {
                isPaywallPresented = true
            }
        }
        .padding(.top, DSSpacing.sm)
        // Extra bottom padding — the search row needs visual separation
        // from the large title above it; the default listHeader VStack
        // gap (`DSSpacing.sm` = 12pt) alone felt tight next to a 34pt
        // large title. Adds another 8pt for a total ~20pt breathing
        // gap between "Your Cabinet" baseline and the search capsule.
        .padding(.bottom, DSSpacing.xs)
    }

    // MARK: - Search + actions row

    /// Single-row header that combines the search field with view-mode
    /// toggle + filter menu. Lives inline at the top of `listHeader` rather
    /// than in `.searchable` / `.toolbar`, so the three list-management
    /// controls share one visual line and there is exactly one clear button
    /// (the ⊗ inside the field) instead of `.searchable`'s clear + Cancel
    /// duo. The premium crown stays in the navbar trailing (screen-level
    /// action, not a list-management control).
    ///
    /// Flat elevated surfaces (not `.glassEffect(...)`) — glass on the
    /// screen's light gray background renders as milky white bloom that
    /// reads heavy/puffy at small sizes (search capsule + 44pt icon
    /// circles). `Color.dsBackgroundElevated` + hairline stroke gives the
    /// controls definition without the glass overload; glass stays for
    /// the larger chip / hero surfaces below where the material has
    /// enough real estate to look right.
    private var searchAndActionsRow: some View {
        // Owns its own `@FocusState` so tapping the field no longer
        // re-runs `LibraryView.body` — see `LibrarySearchAndActionsBar`'s
        // docstring. `trailing:` is the collapsed-state neighbours
        // (view-mode toggle + filter menu); the subview swaps them for
        // Cancel when the field is engaged.
        LibrarySearchAndActionsBar(
            input: $viewModel.searchInput,
            onClear: { viewModel.clearSearch() }
        ) {
            HStack(spacing: DSSpacing.xs) {
                viewModeToggleButton
                filterMenu
            }
        }
    }

    // MARK: - Trailing actions

    /// Grid ↔ list view mode toggle. Moved from the previous `viewControlsRow`
    /// (below type tabs) to `searchAndActionsRow` (top of list, alongside
    /// search + filter) — one horizontal band of controls instead of split
    /// navbar + drawer + row-below-tabs.
    ///
    /// Uses shared `.roundIconButtonSurface()` modifier — subtle gradient
    /// fill + top-only highlight ring + tight ambient shadow. Reads as
    /// "small dimensional chip" instead of flat outline circle, matching
    /// the visual weight of the search capsule beside it.
    private var viewModeToggleButton: some View {
        Button {
            viewMode = viewMode == .list ? .grid : .list
        } label: {
            // Outline pair (Files.app pattern) — matches the filter icon
            // beside it, which is also stroke-only unless a filter is
            // active. Filled variants read too heavy next to the filter
            // circle and clash with the flat elevated round surface.
            Image(systemName: viewMode == .list
                  ? "square.grid.2x2"
                  : "list.bullet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                .roundIconButtonSurface()
        }
        .sensoryFeedback(.selection, trigger: viewMode)
        .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")
    }


    private var filterMenu: some View {
        Button {
            // Explicit wrap so the open cascade — surface fill in,
            // icon symbol swap, popover slide — is driven by ONE curve
            // (~iOS popover system 0.3s) instead of the previous mix
            // of 0.18/0.22/system that read as jerky/disjointed.
            if reduceMotion {
                isFilterPopoverPresented = true
            } else {
                withAnimation(.smooth(duration: 0.28)) {
                    isFilterPopoverPresented = true
                }
            }
        } label: {
            // Filled variant when EITHER filter is active — a single visual
            // cue that "something is narrowing this list". Matched sizing +
            // flat elevated surface with `viewModeToggleButton` so the two
            // icons read as a paired cluster next to the search capsule.
            //
            // Numeric badge appears only when 2 filters are on: with 1
            // filter the fill/outline swap on the icon itself is a
            // sufficient signal — the badge just added visual noise for
            // the common "single-filter" case. Kept for ≥2 because there
            // the count is the only cue that MORE than one dimension is
            // narrowing the list.
            Image(systemName: isAnyFilterActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                // iOS 17+ built-in symbol swap animation — replaces the
                // fill/outline crossfade with SF Symbols' layered
                // transition. Removes the "hard flick" the user flagged
                // when a status filter is applied from the popover.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                // Tinted while the popover is open so the tap is
                // visually acknowledged even in the split second before
                // the popover slides in.
                .roundIconButtonSurface(isActive: isFilterPopoverPresented)
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount >= 2 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.dsTextOnBrand)
                            .frame(minWidth: 14, minHeight: 14)
                            .padding(.horizontal, 2)
                            .background(Color.dsBrandPrimary, in: Capsule())
                            .overlay(
                                // Ring against the button surface so the
                                // badge stays distinct even when the icon
                                // fill runs close to brand primary.
                                Capsule().stroke(Color.dsBackgroundPrimary, lineWidth: 1.5)
                            )
                            .offset(x: 6, y: -6)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        // Single implicit animation for BOTH values so state changes
        // driven from the popover selection (statusFilter set → popover
        // dismiss → isActive flip → icon swap) all share one curve
        // matching iOS's popover ~0.3s system animation.
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: activeFilterCount)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isFilterPopoverPresented)
        .accessibilityLabel(activeFilterCount == 0
            ? "Filter documents"
            : "Filter documents, \(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s") active")
        .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .top) {
            filterPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Popover body — anchored via `.presentationCompactAdaptation
    /// (.popover)` so it drops down directly below the filter icon
    /// with an arrow pointing back to the icon.
    private var filterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverSectionHeader("Favourites")
            // Star is always `star` outline; the trailing checkmark is the
            // only "is active" signal. `star.fill` while OFF was ambiguous
            // (looked already on). Mirrors the Status rows' pattern below.
            popoverActionRow(
                title: "Show favourites only",
                systemImage: "star",
                iconColor: Color.dsBrandPrimary,
                isTrailingCheck: viewModel.favouritesOnly
            ) {
                viewModel.favouritesOnly.toggle()
            }

            Divider().padding(.vertical, DSSpacing.xxs)

            popoverSectionHeader("Status")
            // `list.bullet` (not `checkmark`) — the trailing checkmark on
            // the right is already SwiftUI's "selected" indicator, so a
            // second checkmark on the left read as a duplicate. A neutral
            // "all items" glyph disambiguates.
            popoverActionRow(
                title: "All",
                systemImage: "list.bullet",
                iconColor: Color.dsTextSecondary,
                isTrailingCheck: viewModel.statusFilter == nil
            ) {
                viewModel.statusFilter = nil
            }
            ForEach(DocumentStatus.allCases) { status in
                // Per-status colour matches the chip on the row itself
                // (DocumentCard.StatusPill) so the popover and the pills
                // share one colour vocabulary — user can scan colour, not
                // re-read text, to map filter → chip.
                popoverActionRow(
                    title: status.displayName,
                    systemImage: status.systemImage,
                    iconColor: statusIconColor(for: status),
                    isTrailingCheck: viewModel.statusFilter == status
                ) {
                    viewModel.statusFilter = status
                }
            }

            if viewModel.statusFilter != nil || viewModel.favouritesOnly {
                Divider().padding(.vertical, DSSpacing.xxs)
                popoverActionRow(
                    title: "Clear all filters",
                    systemImage: "xmark.circle",
                    iconColor: Color.dsStatusError,
                    tint: Color.dsStatusError
                ) {
                    viewModel.statusFilter = nil
                    viewModel.favouritesOnly = false
                }
            }
        }
        // Extra top padding so "FAVOURITES" header breathes against the
        // popover chrome (was `xs = 8` → felt cramped in the screenshot).
        .padding(.top, DSSpacing.sm)
        .padding(.bottom, DSSpacing.xs)
        // S15 shift-left trick — leading padding widens the natural
        // content box so iOS's popover positioner shifts it leftward.
        // Kept at `xs = 8` (S15 final): larger values ended up affecting
        // internal row layout too, not just the popover offset.
        .padding(.leading, DSSpacing.xs)
    }

    // MARK: - Rename + ZIP action handlers (kebab menu)

    /// Runs `LibraryViewModel.rename` and translates the outcome into a
    /// toast. Returns `true` on success so `FileActionsMenu`'s rename
    /// alert dismisses; returns `false` on collision / invalid input /
    /// filesystem error so the alert re-opens with the typed name.
    ///
    /// Toast contract — one per outcome, matches the same
    /// `title` + `filename` shape the ZIP + import flows already use:
    /// - success: `.success` with the FINAL filename (stem + kept ext) so
    ///   the row and the toast show the same string
    /// - name conflict: `.error` — user tries again in the re-opened alert
    /// - invalid name: `.error` — should be rare (Rename button also
    ///   guards empty), covers the whitespace-only slip-through
    /// - filesystem failure: `.error` with the localised system message
    /// Flips the favourite pin and posts a subtle info-style toast so
    /// the user gets confirmation even after the kebab sheet dismisses
    /// (the star icon on the row itself does swap immediately, but by
    /// the time the actions sheet slides away the swap is already
    /// off-screen for the tap-and-look muscle memory). `.info` style
    /// rather than `.success` — favouriting is a toggle, not a
    /// completed piece of work, and `.info` reads as lighter-weight
    /// confirmation matching iOS Photos / Files "Favourite" affordance
    /// tone. Copy varies with the RESULTING state (not the source
    /// state) so it reads as a report of what just happened.
    private func performToggleFavourite(entry: LibraryEntry) async {
        let willBeFavourite = !entry.metadata.isFavourite
        await viewModel.setFavourite(willBeFavourite, for: entry.id)
        toaster.show(
            .info,
            title: willBeFavourite ? "Added to your Favourites" : "Removed from your Favourites",
            filename: entry.document.name
        )
    }

    /// Confirmation already happened in `FileActionsMenu` (destructive
    /// alert) before this fires — this only executes the delete + toasts
    /// the result.
    private func performDeleteFile(entryID: String, name: String) async {
        switch await viewModel.deleteFile(entryID: entryID) {
        case .deleted:
            toaster.show(.success, title: "Your file was deleted", filename: name)
        case .failed(let message):
            toaster.show(.error, title: "We couldn't delete this file", filename: message)
        }
    }

    private func performRename(entryID: String, to newStem: String) async -> Bool {
        switch await viewModel.rename(entryID: entryID, to: newStem) {
        case .renamed(let newName):
            toaster.show(.success, title: "Your file was renamed successfully", filename: newName)
            return true
        case .nameConflict:
            toaster.show(.error, title: "This name is already in use — please try another")
            return false
        case .invalidName:
            toaster.show(.error, title: "Please enter a name for your file")
            return false
        case .failed(let message):
            toaster.show(.error, title: "We couldn't rename this file", filename: message)
            return false
        }
    }

    /// Records the user's intent to zip a file, then defers to the
    /// dialog below to ask "keep both / replace / cancel" BEFORE any
    /// zipping starts. Zip can take seconds on a large PDF, so asking
    /// upfront saves the wait for a Cancel path.
    private func performConvertToZip(entryID: String, name: String) {
        pendingZipRequest = PendingZipRequest(entryID: entryID, filename: name)
    }

    /// Fires when the user picks an outcome from the ZIP confirmation
    /// dialog. `deleteSource: true` for the destructive "Replace with
    /// ZIP" (removes source PDF after the archive lands); `false` for
    /// "Keep Both". Cancel path clears the request via the dialog's own
    /// dismissal — no VM work at all.
    ///
    /// Session 19 — switches on `ConvertToZipOutcome` (was: boolean +
    /// error string) so the `.createdButSourceRemains` case can render
    /// the honest "keep-both" toast copy instead of falsely claiming
    /// the source was replaced when the delete step silently failed
    /// (code-review P1).
    private func commitConvertToZip(entryID: String, name: String, deleteSource: Bool) async {
        switch await viewModel.convertToZip(entryID: entryID, deleteSource: deleteSource) {
        case .createdKeepingSource, .createdButSourceRemains:
            // Both paths end with the user having BOTH files on disk.
            // The user picked either "Keep Both" (expected) or "Replace"
            // where the delete quietly failed (source still there);
            // same toast copy tells the truth in both cases without
            // surfacing a scary "delete failed" alert for a state the
            // user can just fix themselves by deleting the source from
            // the kebab menu.
            toaster.show(.success, title: "Your ZIP archive is ready", filename: name)
        case .createdAndReplacedSource:
            toaster.show(.success, title: "The original file was replaced with a ZIP archive", filename: name)
        case .failed(let message):
            toaster.show(
                .error,
                title: "We couldn't create your ZIP archive",
                filename: message
            )
        }
    }

    /// Chip / pill semantic colour, mirrored from
    /// `DocumentCard.StatusPill.foreground` — keep the two in sync.
    private func statusIconColor(for status: DocumentStatus) -> Color {
        switch status {
        case .draft:    Color.dsStatusWarning
        case .reviewed: Color.dsTextSecondary
        case .signed:   Color.dsStatusSuccess
        case .sent:     Color.dsBrandPrimary
        }
    }

    private func popoverSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DSFont.caption.weight(.semibold))
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    private func popoverActionRow(
        title: String,
        systemImage: String,
        iconColor: Color = Color.dsBrandPrimary,
        isTrailingCheck: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            isFilterPopoverPresented = false
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(tint ?? iconColor)
                    .frame(width: 22)
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(tint ?? Color.dsTextPrimary)
                Spacer()
                if isTrailingCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            // md (16) vertical (was sm=12) so rows read as ~52pt tall
            // instead of ~44pt — the "too tight" spacing the user flagged. Matches
            // the touch-target-generous rhythm of Mail's filter menu.
            .padding(.vertical, DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isAnyFilterActive: Bool {
        activeFilterCount > 0
    }

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.statusFilter != nil { count += 1 }
        if viewModel.favouritesOnly { count += 1 }
        return count
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
        HStack(alignment: .center, spacing: DSSpacing.md) {
            // Leading number badge — big rounded digit inside a bright
            // gradient chip, becomes THE focal element (users care
            // "how many docs"). Chip form (not raw text) gives the
            // number an anchor + a shape to shadow, so it reads as a
            // metric card rather than large body text.
            numberChip

            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(DSFont.headline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(copy.subtitle)
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .background(cardSurface)
        .overlay(cardTopHighlight)
        // 2-layer shadow — tight ambient sharpens bottom edge, soft
        // spread reads as real elevation. Same language as
        // `ToolCardSurface` in Tools tab so cards across the app share
        // one elevation vocabulary.
        .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        .shadow(color: Color.dsBrandPrimary.opacity(0.14), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var numberChip: some View {
        Text("\(copy.count)")
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.dsTextOnBrand)
            .frame(minWidth: 66, minHeight: 66)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.dsBrandPrimary,
                                Color.dsBrandPrimary.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 6, y: 3)
    }

    /// Card fill — top-to-bottom gradient from a paper-light tint down to
    /// a hint of brand-primary wash. Not `.glassEffect(...)` here: the
    /// earlier glass tint pass looked visually indistinguishable from a
    /// flat solid on a light background (glass has nothing to refract
    /// through), so an explicit gradient gives the card actual depth.
    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.dsBackgroundElevated,
                        Color.dsBrandPrimary.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    /// Very-subtle top-only white highlight — mimics a light source from
    /// above, matches `IconBadge` / premium crown convention so the whole
    /// app shares one light-source direction.
    private var cardTopHighlight: some View {
        RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.dsBorderSubtle.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
    }
}

private struct TypeTabButton: View {
    let filter: DocumentTypeFilter
    let count: Int
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                leadingMarker
                Text(filter.displayName)
                    .font(DSFont.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(DSFont.caption)
                    .foregroundStyle(isSelected ? Color.dsTextOnBrand.opacity(0.85) : Color.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .foregroundStyle(isSelected ? Color.dsTextOnBrand : Color.dsTextPrimary)
        }
        // Selected chip: solid brand fill + tinted-brand glass overlay
        // (same 2-layer pattern the tab-bar pill uses) — real contrast
        // + wet-glass sheen. Unselected chip: flat elevated capsule,
        // NO glass. Liquid Glass on a light gray screen background has
        // nothing to refract through and its rim highlight was
        // rendering as the extra border the user flagged; a flat white
        // capsule reads clean instead.
        .background {
            Capsule().fill(isSelected ? Color.dsBrandPrimary : Color.dsBackgroundElevated)
        }
        .glassEffect(
            isSelected
                ? .regular.tint(Color.dsBrandPrimary).interactive()
                : .identity,
            in: .capsule
        )
        // No extra shadow — Liquid Glass already carries its own
        // material-based ambient occlusion, and stacking a directional
        // `y:` shadow on top made the strip read as "chip halves
        // sitting slightly below their own outline" (asymmetric top vs
        // bottom edge = the "skewed / smudged" look the user flagged). Search
        // capsule and round icon buttons still carry the 2-layer
        // ToolCardSurface shadow because those are flat elevated
        // surfaces, not glass.
        .buttonStyle(.plain)
        // Closure filter — fire haptic ONLY on the false→true transition.
        // Without it, tapping a chip while another is selected produces
        // a double bump (old chip deselect + new chip select), which
        // reads as a stuttering vibration on every chip change. Same
        // guard pattern as `PressableCardButtonStyle` in ToolsTabView.
        .sensoryFeedback(.selection, trigger: isSelected) { _, newValue in
            newValue
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isSelected)
        .accessibilityLabel("\(filter.displayName), \(count) documents")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // Chip All keeps the abstract brand dot; the four document-type chips
    // swap the dot for the app icon so users read them as "Word / Excel /
    // PowerPoint / PDF" at a glance instead of a color code.
    @ViewBuilder
    private var leadingMarker: some View {
        switch filter {
        case .all:
            Circle()
                .fill(isSelected ? Color.dsTextOnBrand : Color.dsBrandPrimary)
                .frame(width: 7, height: 7)
        case .word:
            typeIcon("DocumentIconWord")
        case .excel:
            typeIcon("DocumentIconSpreadsheet")
        case .powerPoint:
            typeIcon("DocumentIconPresentation")
        case .pdf:
            typeIcon("DocumentIconPDF")
        }
    }

    private func typeIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .antialiased(true)
            .frame(width: 18, height: 18)
    }
}

// MARK: - Shared modifiers

/// "Ghost" surface for the round icon buttons — same flat white fill
/// (`dsBackgroundElevated`) and hairline border (`dsBorderSubtle`) as
/// the search field capsule, just wrapped in `Circle` instead of
/// `Capsule`. Puts search + view-mode toggle + filter menu on the same
/// visual language so the row reads as one coherent control cluster,
/// not "clean search + heavy tinted icons stapled next to it".
///
/// `isActive` — when a button has an attached popover / sheet, pass the
/// presentation flag so the surface tints while it's open. Without this
/// the tap felt "dead" (icon didn't change) even though the popover was
/// clearly there. Subtle brand tint + slightly stronger border reads as
/// "this control is engaged" without becoming a focal element.
private struct RoundIconButtonSurface: ViewModifier {
    var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isActive ? Color.dsBrandPrimarySubtle : Color.dsBackgroundElevated,
                in: Circle()
            )
            .overlay(
                Circle().stroke(
                    isActive ? Color.dsBrandPrimary.opacity(0.35) : Color.dsBorderSubtle.opacity(0.5),
                    lineWidth: isActive ? 1 : 0.5
                )
            )
            // 2-layer shadow — same values as `ToolCardSurface` in
            // `ToolsTabView` so buttons across screens share one
            // elevation vocabulary.
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}

private extension View {
    func roundIconButtonSurface(isActive: Bool = false) -> some View {
        modifier(RoundIconButtonSurface(isActive: isActive))
    }
}

// MARK: - Search bar (extracted for focus-state isolation)

/// The search field + collapse-to-Cancel switcher, extracted from
/// `LibraryView` **specifically** to own `@FocusState` inside this
/// struct rather than on the parent. When `@FocusState` sat on
/// `LibraryView`, every tap on the field re-ran the whole
/// `LibraryView.body` — which re-diffed `titleRow` (the PremiumButton's
/// gradient / shine / shadow recipe), the horizontal `typeTabs` strip
/// of Liquid Glass chips, and the hero card. That was the click-lag
/// the user flagged even after row-height, animation-consolidation,
/// and search-input debounce fixes had all landed.
///
/// The trailing icons (view-mode + filter) are passed in via a
/// `@ViewBuilder` closure so they can keep their own bindings in
/// `LibraryView` (view mode is `@AppStorage`, filter popover state is
/// `@State`) — this subview stays focused on the search-bar mechanics.
private struct LibrarySearchAndActionsBar<Trailing: View>: View {
    @Binding var input: String
    let onClear: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Files.app collapse rule — hide the trailing icons whenever the
    /// user is actively engaged with search (focused OR carries a
    /// pending query). Reads `input` (live), not the debounced
    /// `searchText`, so the Cancel button appears the moment the user
    /// starts typing.
    private var isCollapsed: Bool {
        isFocused || !input.isEmpty
    }

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            searchFieldPill
            if isCollapsed {
                cancelButton
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                trailing()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Fixed row height keeps the enclosing `List` from re-measuring
        // any row on focus / cancel-button swap. List reflow was the
        // main source of the "search feels laggy" video.
        .frame(height: DSSize.minimumTouchTarget)
        // Single `.smooth` curve covers both the pill border thickening
        // (via `isFocused`) and the trailing swap; the parent no longer
        // needs its own `.animation` modifier over the same value.
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isFocused)
    }

    // MARK: - Pieces

    private var searchFieldPill: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.dsTextSecondary)
            TextField("Search documents", text: $input)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
            if !input.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .frame(height: DSSize.minimumTouchTarget)
        .background(Color.dsBackgroundElevated, in: Capsule())
        .overlay(
            Capsule().stroke(
                isFocused
                    ? Color.dsBrandPrimary.opacity(0.4)
                    : Color.dsBorderSubtle.opacity(0.5),
                lineWidth: isFocused ? 1.2 : 0.5
            )
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var cancelButton: some View {
        Button {
            onClear()
            isFocused = false
        } label: {
            Text("Cancel")
                .font(DSFont.body)
                .foregroundStyle(Color.dsBrandPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close search")
    }
}
