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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    /// Reports whether a section "View all" page (status buckets / Continue
    /// Working) is on screen, so `RootView` can hide the mascot there.
    /// Folder detail pages deliberately don't report — the mascot stays.
    var onViewAllVisibilityChange: (Bool) -> Void = { _ in }

    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .list
    @AppStorage("library.openDocumentTipSeen") private var tipSeen: Bool = false
    @AppStorage("library.foldersTipSeen") private var foldersTipSeen: Bool = false
    @State private var tipPresented: Bool = false
    /// Measured size of the rendered TipCallout. Height used to place the
    /// bubble above the section header; width used to center it over the card.
    /// Defaults cover a typical 2-line subheadline bubble (95×240pt).
    @State private var tipCalloutHeight: CGFloat = 95
    @State private var tipCalloutWidth: CGFloat = 240
    /// Target card's real frame (`libraryTipSpace` coordinate space), fed by
    /// `TipAnchorFrameKey` — see `tipOverlay`.
    @State private var tipAnchorFrame: CGRect?
    /// "Get Started" section header row's frame — used for y-positioning so the
    /// tooltip bubble clears the header entirely (the header sits between the
    /// type chips and the first card, so anchoring to the card top caused the
    /// bubble to overlap the header).
    @State private var tipSectionHeaderFrame: CGRect?

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

    /// Presented from the crown `PremiumButton` in the `titleRow`.
    /// TODO(paywall): route through a shared `PaywallCoordinator` if the
    /// crown ever fires from more than these two screens.
    @State private var isPaywallPresented = false
    @State private var badgePulse = false
    @State private var navPath = NavigationPath()
    /// Set by the mascot tap → scrolls to that section and shows a highlight ring.
    @State private var highlightedStatus: DocumentStatus? = nil
    /// Per-session search text scoped to the "View all" destination —
    /// cleared automatically when the user pops back.
    @State private var allFilesSearchInput: String = ""
    /// Set to `true` the moment `.task` fires its first iteration so the
    /// "No documents yet" empty state never flashes during the 1-frame
    /// gap between permission becoming `.granted` and `loadLibrary()`
    /// setting `isLoading = true`.
    @State private var hasInitialLoadStarted = false
    @State private var cardPreviewWidth: CGFloat = 320
    // Files / Folders tab switcher
    @State private var libraryTab: LibraryTab = .files
    /// Non-nil while the Files tab is filtered to one folder's contents.
    @State private var activeFolderID: UUID? = nil
    /// Entry pending folder assignment — drives `AssignFolderSheet`.
    @State private var folderAssignEntryID: String? = nil
    @State private var folderSearchText: String = ""
    @State private var folderSortOrder: FolderSortOrder = .nameAsc
    @State private var isSearchExpanded: Bool = false
    @State private var isFolderSearchExpanded: Bool = false
    @State private var isTypeFilterSheetPresented: Bool = false
    @State private var isFileFilterSheetPresented: Bool = false
    private var folderManager: FolderManager { FolderManager.shared }

    var body: some View {
        NavigationStack(path: $navPath) {
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
                } else if store.entries.isEmpty && !viewModel.isLoading && hasInitialLoadStarted {
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
            // Registered on the root Group so it's always active regardless
            // of which tab (Files/Folders) is currently shown. The old
            // registration on libraryListContent's List was only active when
            // libraryTab == .files, leaving .folder destinations unresolved
            // when the user tapped a folder card from the Folders tab.
            .navigationDestination(for: LibrarySectionID.self) { id in
                switch id {
                case .status(let s):
                    statusAllFilesDestination(status: s)
                        .onAppear { onViewAllVisibilityChange(true) }
                        .onDisappear { onViewAllVisibilityChange(false) }
                case .continueWorking:
                    continueWorkingAllFilesDestination
                        .onAppear { onViewAllVisibilityChange(true) }
                        .onDisappear { onViewAllVisibilityChange(false) }
                case .folder(let fid):  folderDetailDestination(folderID: fid)
                }
            }
            .task(id: store.folderPermissionState) {
                hasInitialLoadStarted = true
                await viewModel.loadLibrary()
            }
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
            // Folder assignment sheet — long-press context menu "Add to Folder".
            .sheet(item: Binding(
                get: { folderAssignEntryID.map { FolderAssignID(id: $0) } },
                set: { folderAssignEntryID = $0?.id }
            )) { item in
                AssignFolderSheet(entryID: item.id, folderManager: folderManager) { folderName in
                    let msg = folderName.map { "Added to \"\($0)\"" } ?? "Removed from folder"
                    toaster.show(.success, title: msg)
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DSRadius.large)
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
            // Convert-to-ZIP — custom overlay so we get a scrim behind
            // the dialog. Native `.confirmationDialog` gives no scrim.
            .overlay {
                if let request = pendingZipRequest {
                    ZipConfirmDialog(
                        filename: request.filename,
                        onKeepBoth: {
                            let r = request; pendingZipRequest = nil
                            Task { await commitConvertToZip(entryID: r.entryID, name: r.filename, deleteSource: false) }
                        },
                        onReplace: {
                            let r = request; pendingZipRequest = nil
                            Task { await commitConvertToZip(entryID: r.entryID, name: r.filename, deleteSource: true) }
                        },
                        onCancel: { pendingZipRequest = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                }
            }
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.22), value: pendingZipRequest != nil)
        }
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
    private var continueEntries: [LibraryEntry] { viewModel.continueWorkingEntries() }

    /// Home's primary grouping (2026-09-13) — was `DateBucket` (Today/
    /// Previous 7 Days/...), now `DocumentStatus` (Draft/Reviewed/Done) so
    /// the list actually delivers on the onboarding's "every file tagged
    /// Draft, Reviewed or Done — see what needs your attention at a glance"
    /// promise, instead of status only being a buried filter option. Date
    /// moved to `dateFilter` in the popover instead (narrows within
    /// sections rather than replacing them).
    private var groupedSections: [(status: DocumentStatus, entries: [LibraryEntry])] { viewModel.groupedByStatus() }

    /// Sections filtered by active folder when one is selected.
    private var filteredGroupedSections: [(status: DocumentStatus, entries: [LibraryEntry])] {
        guard let folderID = activeFolderID else { return groupedSections }
        let assignedIDs = Set(folderManager.assignments.compactMap { $0.value == folderID ? $0.key : nil })
        return groupedSections.compactMap { group in
            let filtered = group.entries.filter { assignedIDs.contains($0.id) }
            return filtered.isEmpty ? nil : (status: group.status, entries: filtered)
        }
    }

    // ZStack keeps both scroll hierarchies alive — avoids the UITableView
    // create/destroy cost on every tab switch (which caused the visible flash).
    // Opacity + allowsHitTesting swap which view receives interaction;
    // suppressTabBarHiddenPreference prevents the inactive view's scroll
    // auto-hide state from bleeding into the active tab's tab-bar visibility.
    // ZStack keeps both scroll hierarchies alive — avoids the UITableView
    // create/destroy cost on every tab switch (which caused the visible flash).
    // Opacity + allowsHitTesting swap which view receives interaction;
    // suppressTabBarHiddenPreference prevents the inactive view's scroll
    // auto-hide state from bleeding into the active tab's tab-bar visibility.
    // Background: explicit systemGroupedBackground prevents the parent
    // NavigationStack's systemBackground (white) from bleeding through during
    // the 220ms opacity cross-fade between tabs.
    @ViewBuilder private var libraryList: some View {
        ZStack {
            libraryListContent
                .opacity(libraryTab == .files ? 1 : 0)
                .allowsHitTesting(libraryTab == .files)
                .suppressTabBarHiddenPreference(unless: libraryTab == .files)
            folderTabList
                .opacity(libraryTab == .folders ? 1 : 0)
                .allowsHitTesting(libraryTab == .folders)
                .suppressTabBarHiddenPreference(unless: libraryTab == .folders)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    /// Folders tab — `FolderGridView` with its scrollable header (titleRow +
    /// banner + tabs + sort row).
    private var folderTabList: some View {
        FolderGridView(
            folderManager: folderManager,
            searchText: $folderSearchText,
            sortOrder: $folderSortOrder,
            onSelectFolder: { folderID in
                navPath.append(LibrarySectionID.folder(folderID))
            }
        ) {
            VStack(spacing: 0) {
                titleRow
                    .padding(.horizontal, DSSpacing.lg)
                homeBannerView
                    .padding(.top, DSSpacing.xs)
                    .padding(.bottom, 4)
                libTabRow
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.sm)
                foldersActionRow
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.sm)
                    .padding(.bottom, DSSpacing.md)
                if !foldersTipSeen {
                    FoldersTipBanner { foldersTipSeen = true }
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.bottom, DSSpacing.lg)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.smooth(duration: 0.3), value: foldersTipSeen)
        }
        .hidesTabBarVisually(isFolderSearchExpanded)
    }

    // [Sort▼] [🔍] — or inline search bar when expanded
    private var foldersActionRow: some View {
        Group {
            if isFolderSearchExpanded {
                LibrarySearchBar(
                    placeholder: "Search folders",
                    input: $folderSearchText,
                    onCancel: {
                        folderSearchText = ""
                        withAnimation(.smooth(duration: 0.24)) { isFolderSearchExpanded = false }
                    }
                )
            } else {
                HStack(spacing: 0) {
                    folderSortButton
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { isFolderSearchExpanded = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.dsBrandPrimary)
                            .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                            .roundIconButtonSurface()
                    }
                    .buttonStyle(LibraryIconButtonStyle())
                    .accessibilityLabel("Search folders")
                }
                .frame(height: DSSize.minimumTouchTarget)
            }
        }
        .animation(.smooth(duration: 0.24), value: isFolderSearchExpanded)
    }

    private var folderSortButton: some View {
        let isActive = folderSortOrder != .nameAsc
        return Menu {
            Picker("Sort", selection: $folderSortOrder) {
                ForEach(FolderSortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.systemImage).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sort")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isActive ? Color.white : Color.dsBrandPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: DSSize.minimumTouchTarget)
            .background(
                isActive ? Color.dsBrandPrimary : Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.clear : Color(UIColor.separator).opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(isActive ? 0.12 : 0.07), radius: isActive ? 5 : 4, y: isActive ? 3 : 2)
            .shadow(color: .black.opacity(isActive ? 0.05 : 0.03), radius: isActive ? 12 : 10, y: isActive ? 5 : 3)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isActive)
        }
        .accessibilityLabel("Sort folders: \(folderSortOrder.rawValue)")
    }

    @ViewBuilder private var tipOverlay: some View {
        if tipPresented, let cardFrame = tipAnchorFrame {
            // y-anchor: use the section header top when measured (guarantees
            // the bubble clears the "Get Started" header that sits between the
            // type chips and the first card); fall back to the card top if the
            // header frame hasn't landed yet.
            let yAnchor = tipSectionHeaderFrame?.minY ?? cardFrame.minY
            TipCallout()
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: TipCalloutSizeKey.self,
                                               value: geo.size)
                    }
                }
                .onPreferenceChange(TipCalloutSizeKey.self) {
                    tipCalloutHeight = $0.height
                    tipCalloutWidth  = $0.width
                }
                .offset(
                    x: max(0, cardFrame.midX - tipCalloutWidth / 2),
                    y: max(8, yAnchor - tipCalloutHeight - 8)
                )
                .allowsHitTesting(false)
        }
    }

    private var libraryListContent: some View {
        ScrollViewReader { proxy in
        // Single List for every state (default / filter-empty / search-
        // active / search-empty). Search results and no-result placeholders
        // render as list rows UNDER `listHeader`, never replace it — so the
        // search field + Cancel button stay reachable and the user is
        // never stuck on a screen with no way back.
        List {
            // Full scrollable header: title + banner + tabs + filter row.
            // No safeAreaInset — everything scrolls with list content.
            Section {
                VStack(spacing: 0) {
                    titleRow
                        .padding(.horizontal, DSSpacing.lg)
                    homeBannerView
                        .padding(.top, DSSpacing.xs)
                        .padding(.bottom, 4)
                    libTabRow
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.top, DSSpacing.sm)
                    filesActionRow
                        .padding(.leading, DSSpacing.lg + DSSpacing.xs + 3) // align with section-header leading edge
                        .padding(.trailing, DSSpacing.lg)
                        .padding(.top, DSSpacing.sm)
                        .padding(.bottom, DSSpacing.md)
                }
                // Negative leading/trailing counteracts insetGrouped section-container
                // margins (~20pt per side) so the header fills the full screen width,
                // and items' own .padding(.horizontal, DSSpacing.lg) provides the
                // correct 20pt screen-edge margins — matching the Folders tab.
                .listRowInsets(EdgeInsets(top: 0, leading: -DSSpacing.lg, bottom: 0, trailing: -DSSpacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                listHeader
                    .listRowInsets(EdgeInsets(top: DSSpacing.xxs, leading: 0, bottom: 4, trailing: 0))
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
                            .listRowInsets(EdgeInsets())
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
            } else if viewModel.isFiltering && dueEntries.isEmpty && filteredGroupedSections.isEmpty {
                // Filter yields no results — render the empty state as
                // a list row so the chip strip above stays tappable
                // and the Show-all button gives an obvious way back.
                Section {
                    filteredEmptyStateContent
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                // Show a spinner while the initial scan runs so the list
                // isn't blank-white during the 200–800 ms it takes to read
                // the folder. `libraryList` is always shown when isLoading=true
                // (condition above keeps the empty-state branch gated on
                // !isLoading), so this only fires on initial load.
                if viewModel.isLoading && store.entries.isEmpty {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if !continueEntries.isEmpty && viewMode == .list {
                    Section {
                        continueWorkingTabHeader(count: continueEntries.count)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: 0,
                                leading: 3,
                                bottom: 0,
                                trailing: DSSpacing.xs))
                            .listRowBackground(
                                HStack(spacing: 0) {
                                    Color.dsBrandPrimary.frame(width: 3)
                                    Color.clear
                                }
                            )
                        let _prefix = Array(continueEntries.prefix(4))
                        ForEach(_prefix) { entry in
                            cardContent(for: entry)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 0,
                                    leading: 3 + DSSpacing.xs,
                                    bottom: DSSpacing.xs,
                                    trailing: DSSpacing.xs))
                                .listRowBackground(
                                    HStack(spacing: 0) {
                                        Color.dsBrandPrimary.frame(width: 3)
                                        Color.clear
                                    }
                                )
                        }
                    }
                }

                if !dueEntries.isEmpty {
                    Section {
                        sectionRows(dueEntries)
                    } header: {
                        Label("Needs Attention", systemImage: "bell.badge.fill")
                            .foregroundStyle(Color.dsStatusWarning)
                    }
                }

                if viewMode == .list {
                    // Individual List rows — each card is its own row so iOS
                    // scopes context-menu lift to that card only.
                    // Rail: 3pt tint bar drawn in the leading gutter via
                    // listRowBackground, which fills the row including insets.
                    // Content offset (leading: 11pt) matches timelineGroupedContent's
                    // .padding(.leading, 3 + DSSpacing.xs) so the visual is identical.
                    Section {
                        ForEach(filteredGroupedSections, id: \.status) { group in
                            let isFirst = group.status == filteredGroupedSections.first?.status
                            // Tip anchors to first section's first card (may be .getStarted,
                            // .draft, or whatever comes first when samples are filtered out).
                            let firstTipStatus = filteredGroupedSections.first?.status

                            statusTabHeader(
                                status: group.status,
                                count: group.entries.count,
                                highlighted: highlightedStatus == group.status
                            )
                                // Capture the first section header's y so tipOverlay
                                // can anchor the bubble ABOVE it (not above the card,
                                // which would put the bubble on top of this row).
                                .onGeometryChange(for: CGRect.self) { geo in
                                    geo.frame(in: .named("libraryTipSpace"))
                                } action: { newValue in
                                    guard dueEntries.isEmpty && group.status == firstTipStatus else { return }
                                    tipSectionHeaderFrame = newValue
                                }
                                // Border overlays on listRowBackground (not on content) so
                                // all rows share the same cell-background origin regardless
                                // of their different listRowInsets — fixes the misalignment
                                // visible in the Mascot scroll-to-section highlight ring.
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedStatus == group.status)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: isFirst ? 0 : DSSpacing.xs,
                                    leading: 3,
                                    bottom: 0,
                                    trailing: DSSpacing.xs))
                                .listRowBackground(
                                    HStack(spacing: 0) {
                                        group.status.tintColor.frame(width: 3)
                                        group.status.tintColor
                                            .opacity(highlightedStatus == group.status ? 0.05 : 0)
                                    }
                                    .overlay(alignment: .top)     { group.status.tintColor.opacity(highlightedStatus == group.status ? 0.85 : 0).frame(height: 2.5) }
                                    .overlay(alignment: .leading) { group.status.tintColor.opacity(highlightedStatus == group.status ? 0.85 : 0).frame(width:  2.5) }
                                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedStatus == group.status)
                                )
                                .id("lib-\(group.status.rawValue)")

                            let _prefixEntries = Array(group.entries.prefix(4))
                            let _lastEntryID   = _prefixEntries.last?.id
                            ForEach(_prefixEntries) { entry in
                                let attachTip = dueEntries.isEmpty &&
                                    group.status == firstTipStatus &&
                                    entry.id == group.entries.first?.id
                                let isLastEntry = entry.id == _lastEntryID
                                Group {
                                    cardContent(for: entry)
                                        // Reports this card's real on-screen frame (in the
                                        // `libraryTipSpace` coordinate space) up to the tip
                                        // overlay below, so the coachmark anchors to the
                                        // card's actual position/width instead of a guessed
                                        // Spacer+padding offset — same approach as AirTag
                                        // Finder's `Coachmark` (renderBox.localToGlobal).
                                        // `onGeometryChange` (not a PreferenceKey +
                                        // background GeometryReader) — List's internal
                                        // UIKit-bridged sizing pass re-instantiates row
                                        // content off-screen for measurement, and a
                                        // preference written during that pass was winning
                                        // over the real on-screen frame (reproduced: tip
                                        // rendered near the tab bar instead of the card).
                                        .onGeometryChange(for: CGRect.self) { geo in
                                            geo.frame(in: .named("libraryTipSpace"))
                                        } action: { newValue in
                                            guard attachTip else { return }
                                            tipAnchorFrame = newValue
                                        }
                                        .onAppear {
                                            guard attachTip, !tipSeen, !tipPresented else { return }
                                            Task { @MainActor in
                                                try? await Task.sleep(for: .seconds(1))
                                                withAnimation(.easeIn(duration: 0.2)) { tipPresented = true }
                                                try? await Task.sleep(for: .seconds(4))
                                                withAnimation(.easeOut(duration: 0.2)) { tipPresented = false }
                                                tipSeen = true
                                            }
                                        }
                                }
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedStatus == group.status)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 0,
                                    leading: 3 + DSSpacing.xs,
                                    bottom: DSSpacing.xs,
                                    trailing: DSSpacing.xs))
                                .listRowBackground(
                                    HStack(spacing: 0) {
                                        group.status.tintColor.frame(width: 3)
                                        group.status.tintColor
                                            .opacity(highlightedStatus == group.status ? 0.05 : 0)
                                    }
                                    .overlay(alignment: .leading) { group.status.tintColor.opacity(highlightedStatus == group.status ? 0.85 : 0).frame(width: 2.5) }
                                    .overlay(alignment: .bottom)  { group.status.tintColor.opacity((highlightedStatus == group.status) && isLastEntry ? 0.85 : 0).frame(height: 2.5) }
                                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlightedStatus == group.status)
                                )
                            }
                        }
                    }
                } else {
                    // Grid mode: kept as single-row spine (grid cards don't swipe).
                    Section {
                        timelineGroupedGrid
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(6)
        // Smooth list-content transitions: rows fade in when the initial
        // scan finishes (isLoading → entries appear) and when filter/search
        // changes the visible set. The `value` pair covers both directions.
        .animation(.smooth(duration: 0.28), value: viewModel.isLoading)
        .animation(.smooth(duration: 0.22), value: viewModel.typeFilter)
        .autoHidesTabBarOnScroll()
        .onChange(of: libraryTab) { _, newTab in
            if newTab == .folders {
                withAnimation(.smooth(duration: 0.2)) { isSearchExpanded = false }
                viewModel.clearSearch()
            } else {
                withAnimation(.smooth(duration: 0.2)) { isFolderSearchExpanded = false }
                folderSearchText = ""
            }
        }
        // Coordinate space + overlay live here (not on NavigationStack) so
        // geo.frame(in: .named("libraryTipSpace")) and the overlay share the
        // same (0,0) origin — the top-left of libraryListContent, which
        // already includes the safeAreaInset (titleRow) offset. Placing
        // both at NavigationStack level caused a mismatch: the overlay's
        // origin was above the titleRow but card frames were measured below it.
        .coordinateSpace(name: "libraryTipSpace")
        .overlay(alignment: .topLeading) { tipOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .mascotScrollToReviewed)) { _ in
            let scrollID = viewMode == .list ? "lib-reviewed" : "grid-reviewed"
            proxy.scrollTo(scrollID, anchor: .top)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                highlightedStatus = .reviewed
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    highlightedStatus = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mascotScrollToDraft)) { _ in
            let scrollID = viewMode == .list ? "lib-draft" : "grid-draft"
            proxy.scrollTo(scrollID, anchor: .top)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                highlightedStatus = .draft
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    highlightedStatus = nil
                }
            }
        }
        } // ScrollViewReader
        .hidesTabBarVisually(isSearchExpanded)
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
                onMarkDone: { entry in
                    Task { await performMarkDone(entry: entry) }
                },
                onDeleteFile: { entry in
                    Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) }
                },
                onChangeStatus: { entry, status in
                    Task {
                        await viewModel.setStatus(status, for: entry.id)
                        toaster.show(
                            (status == .draft || status == .getStarted) ? .info : .success,
                            title: "Marked as \(status.displayName)",
                            filename: entry.document.name
                        )
                    }
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

    // MARK: - Continue Working header + View All

    /// Section header for the "Continue Working" group — mirrors `statusTabHeader`
    /// visual language (pill + count/View-all button) but uses orange and a
    /// distinct label since this is a cross-cutting feature, not a status bucket.
    @ViewBuilder
    private func continueWorkingTabHeader(count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Continue Working")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.dsBrandPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.dsBrandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                if count > 4 {
                    Button {
                        navPath.append(LibrarySectionID.continueWorking)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.dsBrandPrimary)
                                .frame(width: 7, height: 7)
                                .scaleEffect(badgePulse ? 1.35 : 1.0)
                                .opacity(badgePulse ? 0.5 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                    value: badgePulse
                                )
                            Text("View all")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.dsBrandPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.dsBrandPrimary)
                            .frame(width: 7, height: 7)
                            .scaleEffect(badgePulse ? 1.35 : 1.0)
                            .opacity(badgePulse ? 0.5 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: badgePulse
                            )
                        Text("\(count)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.dsBrandPrimary.opacity(0.6))
                    }
                }
            }
            .padding(.bottom, DSSpacing.sm)
            .onAppear { badgePulse = true }
        }
    }

    /// "View all" destination for the Continue Working section.
    /// Same layout as `statusAllFilesDestination` — back button + title +
    /// search + content. Entries come from `continueWorkingEntries()` which
    /// respects active type/date filters.
    @ViewBuilder
    private var continueWorkingAllFilesDestination: some View {
        let allEntries = viewModel.continueWorkingEntries()
        let query = allFilesSearchInput.trimmingCharacters(in: .whitespaces)
        let entries: [LibraryEntry] = query.isEmpty
            ? allEntries
            : allEntries.filter { $0.document.name.localizedCaseInsensitiveContains(query) }

        List {
            Section {
                ZStack {
                    Text("Continue Working")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.dsBrandPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Button { navPath.removeLast() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.dsBrandPrimary)
                                .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                                .roundIconButtonSurface()
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                          bottom: DSSpacing.xxs, trailing: DSSpacing.xl))
            }

            Section {
                LibrarySearchAndActionsBar(
                    input: $allFilesSearchInput,
                    onClear: { allFilesSearchInput = "" }
                ) {
                    viewModeToggleButton
                }
                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                          bottom: DSSpacing.md, trailing: DSSpacing.xl))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if viewMode == .list {
                Section {
                    ForEach(entries) { entry in
                        cardContent(for: entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                                      bottom: DSSpacing.xs, trailing: DSSpacing.xl))
                    }
                }
            } else {
                Section {
                    DocumentGrid(
                        entries: entries,
                        onTap: { entry in
                            Task { await viewModel.recordOpen(entry.id) }
                            onOpenEditor(entry.document)
                        },
                        onSaveExport: { entry in exportingRef = entry.document },
                        onToggleFavourite: { entry in Task { await performToggleFavourite(entry: entry) } },
                        onRename: { entry, newStem in await performRename(entryID: entry.id, to: newStem) },
                        onConvertToZip: { entry in performConvertToZip(entryID: entry.id, name: entry.document.name) },
                        onMarkDone: { entry in Task { await performMarkDone(entry: entry) } },
                        onDeleteFile: { entry in Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) } },
                        onChangeStatus: { entry, status in
                            Task {
                                await viewModel.setStatus(status, for: entry.id)
                                toaster.show(
                                    (status == .draft || status == .getStarted) ? .info : .success,
                                    title: "Marked as \(status.displayName)",
                                    filename: entry.document.name
                                )
                            }
                        },
                        leadingPadding: DSSpacing.xl
                    )
                    .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: 0, bottom: 0, trailing: DSSpacing.xl))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                Color.clear
                    .frame(height: DSTabBarMetrics.listContentTrailingSpacer)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.dsBackgroundPrimary)
        .contentMargins(.top, 0, for: .scrollContent)
        .autoHidesTabBarOnScroll()
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { allFilesSearchInput = "" }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No documents to continue" : "No results",
                    systemImage: "arrow.clockwise.circle",
                    description: Text(query.isEmpty
                        ? "Files you want to keep editing will appear here"
                        : "No documents match \"\(query)\"")
                )
            }
        }
    }

    /// Dedicated folder-scoped view: shows Continue Working + status sections
    /// filtered to files assigned to `folderID`. Delegates to `FolderDetailContent`
    /// (a proper View struct) so that `store.entries` is read reactively inside
    /// that struct's `body` — fixes the "No files" blank that appeared when
    /// entries hadn't loaded at navigation-push time.
    private func folderDetailDestination(folderID: UUID) -> some View {
        let folder = folderManager.folders.first(where: { $0.id == folderID })
        return FolderDetailContent(
            folderID: folderID,
            folderName: folder?.name ?? "Folder",
            folderColor: folder?.color ?? Color.dsBrandPrimary,
            store: store,
            onBack: { navPath.removeLast() },
            onTap: { entry in
                Task { await viewModel.recordOpen(entry.id) }
                onOpenEditor(entry.document)
            },
            onSaveExport: { entry in exportingRef = entry.document },
            onToggleFavourite: { entry in Task { await performToggleFavourite(entry: entry) } },
            onRename: { entry, stem in await performRename(entryID: entry.id, to: stem) },
            onConvertToZip: { entry in performConvertToZip(entryID: entry.id, name: entry.document.name) },
            onMarkDone: { entry in Task { await performMarkDone(entry: entry) } },
            onDeleteFile: { entry in Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) } },
            onChangeStatus: { [toaster] entry, status in
                Task {
                    await viewModel.setStatus(status, for: entry.id)
                    toaster.show(
                        (status == .draft || status == .getStarted) ? .info : .success,
                        title: "Marked as \(status.displayName)",
                        filename: entry.document.name
                    )
                }
            }
        )
    }

    /// Full-screen "View all" destination for one status bucket.
    /// Data comes from `viewModel.groupedByStatus()` which already respects
    /// `dateFilter`, `typeFilter`, and `favouritesOnly` — so whatever window
    /// the user has active in the parent screen carries over here automatically.
    /// Navigation bar is hidden — back button + status pill live in content
    /// (avoids iOS 26 Liquid Glass wrapping toolbar items into ovoid capsules).
    @ViewBuilder
    private func statusAllFilesDestination(status: DocumentStatus) -> some View {
        let allEntries = viewModel.groupedByStatus()
            .first(where: { $0.status == status })?.entries ?? []
        let query = allFilesSearchInput.trimmingCharacters(in: .whitespaces)
        let entries: [LibraryEntry] = query.isEmpty
            ? allEntries
            : allEntries.filter { $0.document.name.localizedCaseInsensitiveContains(query) }
        let statusBg: Color = switch status {
        case .getStarted: Color.dsBrandPrimary.opacity(0.08)
        case .draft:      .dsStatusWarningBackground
        case .reviewed:   .dsBrandPrimarySubtle
        case .done:       .dsStatusSuccessBackground
        }

        List {
            // ── Row 1: back button (left) + title centered via ZStack ──
            Section {
                ZStack {
                    // Title centered across the full row
                    Text(status.displayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(status.tintColor)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Back button pinned to leading edge
                    HStack {
                        Button { navPath.removeLast() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.dsBrandPrimary)
                                .frame(width: DSSize.minimumTouchTarget,
                                       height: DSSize.minimumTouchTarget)
                                .roundIconButtonSurface()
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                          bottom: DSSpacing.xxs, trailing: DSSpacing.xl))
            }

            // ── Row 2: search + view-mode toggle (no filter button) ──
            // Apple HIG: 16pt side margin (md) for content, 12pt bottom gap before cards.
            Section {
                LibrarySearchAndActionsBar(
                    input: $allFilesSearchInput,
                    onClear: { allFilesSearchInput = "" }
                ) {
                    viewModeToggleButton
                }
                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                          bottom: DSSpacing.md, trailing: DSSpacing.xl))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // ── Content ──
            // Apple HIG: 16pt (md) side margins, 8pt (xs) vertical gap between cards.
            if viewMode == .list {
                Section {
                    ForEach(entries) { entry in
                        cardContent(for: entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.xl,
                                                      bottom: DSSpacing.xs, trailing: DSSpacing.xl))
                    }
                }
            } else {
                Section {
                    DocumentGrid(
                        entries: entries,
                        onTap: { entry in
                            Task { await viewModel.recordOpen(entry.id) }
                            onOpenEditor(entry.document)
                        },
                        onSaveExport: { entry in exportingRef = entry.document },
                        onToggleFavourite: { entry in Task { await performToggleFavourite(entry: entry) } },
                        onRename: { entry, newStem in await performRename(entryID: entry.id, to: newStem) },
                        onConvertToZip: { entry in performConvertToZip(entryID: entry.id, name: entry.document.name) },
                        onMarkDone: { entry in Task { await performMarkDone(entry: entry) } },
                        onDeleteFile: { entry in Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) } },
                        onChangeStatus: { entry, status in
                            Task {
                                await viewModel.setStatus(status, for: entry.id)
                                toaster.show(
                                    (status == .draft || status == .getStarted) ? .info : .success,
                                    title: "Marked as \(status.displayName)",
                                    filename: entry.document.name
                                )
                            }
                        },
                        leadingPadding: DSSpacing.xl
                    )
                    .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: 0, bottom: 0, trailing: DSSpacing.xl))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                Color.clear
                    .frame(height: DSTabBarMetrics.listContentTrailingSpacer)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.dsBackgroundPrimary)
        .contentMargins(.top, 0, for: .scrollContent)
        .autoHidesTabBarOnScroll()
        // Hide system nav bar — back + title live in content above (same
        // rationale as the root LibraryView: iOS 26 Liquid Glass wraps
        // toolbar items in ovoid capsules we can't reshape).
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { allFilesSearchInput = "" }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No \(status.displayName) documents" : "No results",
                    systemImage: "doc.text",
                    description: Text(query.isEmpty
                        ? (viewModel.dateFilter != nil
                            ? "No files in this window — try a different date filter"
                            : "No files here yet")
                        : "No documents match \"\(query)\"")
                )
            }
        }
    }

    /// Core card visual — no listRow modifiers, no per-card rail.
    /// Used by both `row(for:)` (search results / single-item List rows) and
    /// `timelineGroupedContent` (where the rail is drawn at the section level).
    private func cardContent(for entry: LibraryEntry) -> some View {
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
            onMarkDone: {
                Task { await performMarkDone(entry: entry) }
            },
            onDeleteFile: {
                Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) }
            },
            onAddToFolder: {
                // Delay until the FileActionsMenu fullScreenCover has
                // fully dismissed (~340ms) before presenting AssignFolderSheet.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    folderAssignEntryID = entry.id
                }
            }
        )
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 10)
        .background(Color.dsBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            .strokeBorder(Color.dsBorderSubtle))
        .dsCardShadow()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardPreviewWidth = $0 }
        .contextMenu(menuItems: {
            contextMenu(for: entry)
        }, preview: {
            HStack(spacing: DSSpacing.md) {
                DocumentKindIcon(kind: entry.document.kind)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(entry.document.name)
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    Text(entry.document.modifiedAt, format: .relative(presentation: .named))
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.md)
            .frame(width: cardPreviewWidth)
            .background(Color.dsBackgroundElevated,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        })
    }

    private func row(for entry: LibraryEntry) -> some View {
        cardContent(for: entry)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(entry.metadata.status.tintColor)
                .frame(width: 3)
                .padding(.vertical, DSRadius.card)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DSSpacing.xxs, leading: DSSpacing.lg, bottom: DSSpacing.xxs, trailing: DSSpacing.md))
    }

    /// Grouped list rendered as a continuous timeline spine.
    ///
    /// Layout: each section's content VStack has a `.background(alignment: .leading)`
    /// that draws a 3 pt `Rectangle` behind its leading edge. The Rectangle's height
    /// Folder-divider tab header — plain label sticker style:
    /// name left, count right, subtle rectangular tinted background.
    /// No icon, no nested badges, small corner radius so it reads as
    /// a label rather than a UI pill.
    @ViewBuilder
    private func statusTabHeader(status: DocumentStatus, count: Int, highlighted: Bool = false) -> some View {
        let bg: Color = switch status {
        case .getStarted: Color.dsBrandPrimary.opacity(0.08)
        case .draft:      .dsStatusWarningBackground
        case .reviewed:   .dsBrandPrimarySubtle
        case .done:       .dsStatusSuccessBackground
        }
        let needsAttention = count > 0 && status != .done

        return VStack(spacing: 0) {
        HStack(spacing: DSSpacing.sm) {
            // Left: status pill — icon + name only
            HStack(spacing: 6) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(status.displayName)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(status.tintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)

            // Right: ● View all › (overflow) or ● count (normal)
            if count > 4 {
                Button {
                    navPath.append(LibrarySectionID.status(status))
                } label: {
                    HStack(spacing: 4) {
                        if needsAttention && !reduceMotion {
                            Circle()
                                .fill(status.tintColor)
                                .frame(width: 7, height: 7)
                                .scaleEffect(badgePulse ? 1.35 : 1.0)
                                .opacity(badgePulse ? 0.5 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                    value: badgePulse
                                )
                        } else if needsAttention {
                            Circle()
                                .fill(status.tintColor)
                                .frame(width: 7, height: 7)
                        }
                        Text("View all")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(status.tintColor)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    if needsAttention && !reduceMotion {
                        Circle()
                            .fill(status.tintColor)
                            .frame(width: 7, height: 7)
                            .scaleEffect(badgePulse ? 1.35 : 1.0)
                            .opacity(badgePulse ? 0.5 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: badgePulse
                            )
                    } else if needsAttention {
                        Circle()
                            .fill(status.tintColor)
                            .frame(width: 7, height: 7)
                    }
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(status.tintColor.opacity(0.6))
                }
            }
        }
        .padding(.bottom, DSSpacing.sm)
        .onAppear { badgePulse = true }
        }
        // Highlight tint fill + scale — border is drawn section-spanning in listRowBackground.
        .background(
            status.tintColor.opacity(highlighted ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .scaleEffect(highlighted ? 1.02 : 1.0, anchor: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: highlighted)
    }

    /// equals the content's height automatically (background fills parent frame).
    /// `VStack(spacing: 0)` ensures adjacent section rectangles are flush with zero
    /// gap → Draft orange → Reviewed blue → Done green with no break in the bar.
    /// Shimmer rail uses `TimelineRailShimmer` (isolated subview) to avoid
    /// driving LibraryView body at 60 fps.
    private var timelineGroupedContent: some View {
        VStack(spacing: 0) {
            ForEach(filteredGroupedSections, id: \.status) { group in
                let firstTipStatus = filteredGroupedSections.first?.status
                VStack(alignment: .leading, spacing: 0) {
                    statusTabHeader(status: group.status, count: group.entries.count)

                    VStack(spacing: DSSpacing.xs) {
                        ForEach(group.entries.prefix(4)) { entry in
                            let attachTip = dueEntries.isEmpty &&
                                group.status == firstTipStatus &&
                                entry.id == group.entries.first?.id
                            cardContent(for: entry)
                                .onGeometryChange(for: CGRect.self) { geo in
                                    geo.frame(in: .named("libraryTipSpace"))
                                } action: { newValue in
                                    guard attachTip else { return }
                                    tipAnchorFrame = newValue
                                }
                                .onAppear {
                                    guard attachTip, !tipSeen, !tipPresented else { return }
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1))
                                        guard tipAnchorFrame != nil else { return }
                                        withAnimation(.easeIn(duration: 0.2)) { tipPresented = true }
                                        try? await Task.sleep(for: .seconds(4))
                                        withAnimation(.easeOut(duration: 0.2)) { tipPresented = false }
                                        tipSeen = true
                                    }
                                }
                        }
                    }

                    Color.clear.frame(height: DSSpacing.xxs)
                }
                .padding(.leading, 3 + DSSpacing.xs)
                .background(alignment: .leading) {
                    TimelineRailShimmer(color: group.status.tintColor)
                }
            }
        }
        .padding(.trailing, DSSpacing.xs)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: filteredGroupedSections.map(\.status))
    }

    /// Grouped grid rendered as a continuous timeline spine — same rail pattern
    /// as `timelineGroupedContent` but uses `DocumentGrid` (LazyVGrid) per section.
    private var timelineGroupedGrid: some View {
        VStack(spacing: 0) {
            if !continueEntries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    continueWorkingTabHeader(count: continueEntries.count)
                        .padding(.trailing, DSSpacing.xs)
                    DocumentGrid(
                        entries: Array(continueEntries.prefix(4)),
                        onTap: { entry in
                            Task { await viewModel.recordOpen(entry.id) }
                            onOpenEditor(entry.document)
                        },
                        onSaveExport: { entry in exportingRef = entry.document },
                        onToggleFavourite: { entry in Task { await performToggleFavourite(entry: entry) } },
                        onRename: { entry, newStem in await performRename(entryID: entry.id, to: newStem) },
                        onConvertToZip: { entry in performConvertToZip(entryID: entry.id, name: entry.document.name) },
                        onMarkDone: { entry in Task { await performMarkDone(entry: entry) } },
                        onDeleteFile: { entry in Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) } },
                        onChangeStatus: { entry, status in
                            Task {
                                await viewModel.setStatus(status, for: entry.id)
                                toaster.show(
                                    (status == .draft || status == .getStarted) ? .info : .success,
                                    title: "Marked as \(status.displayName)",
                                    filename: entry.document.name
                                )
                            }
                        },
                        leadingPadding: 0
                    )
                    Color.clear.frame(height: DSSpacing.xxs)
                }
                .padding(.leading, 3 + DSSpacing.xs)
                .background(alignment: .leading) {
                    TimelineRailShimmer(color: Color.dsBrandPrimary)
                }
            }

            ForEach(filteredGroupedSections, id: \.status) { group in
                // Attach coachmark to the first tile of the first section
                // (may be .draft or .done when samples are filtered out).
                let firstTipStatus = filteredGroupedSections.first?.status
                let attachTip = dueEntries.isEmpty && group.status == firstTipStatus

                VStack(alignment: .leading, spacing: 0) {
                    // DocumentGrid adds its own .padding(.trailing, DSSpacing.xs) internally,
                    // so the header needs the same extra offset to keep "View all" flush.
                    statusTabHeader(status: group.status, count: group.entries.count,
                                    highlighted: highlightedStatus == group.status)
                        .padding(.trailing, DSSpacing.xs)
                        .onGeometryChange(for: CGRect.self) { geo in
                            geo.frame(in: .named("libraryTipSpace"))
                        } action: { newValue in
                            guard dueEntries.isEmpty && group.status == firstTipStatus else { return }
                            tipSectionHeaderFrame = newValue
                        }

                    DocumentGrid(
                        entries: Array(group.entries.prefix(4)),
                        onTap: { entry in
                            Task { await viewModel.recordOpen(entry.id) }
                            onOpenEditor(entry.document)
                        },
                        onSaveExport: { entry in exportingRef = entry.document },
                        onToggleFavourite: { entry in Task { await performToggleFavourite(entry: entry) } },
                        onRename: { entry, newStem in await performRename(entryID: entry.id, to: newStem) },
                        onConvertToZip: { entry in performConvertToZip(entryID: entry.id, name: entry.document.name) },
                        onMarkDone: { entry in Task { await performMarkDone(entry: entry) } },
                        onDeleteFile: { entry in Task { await performDeleteFile(entryID: entry.id, name: entry.document.name) } },
                        onChangeStatus: { entry, status in
                            Task {
                                await viewModel.setStatus(status, for: entry.id)
                                toaster.show(
                                    (status == .draft || status == .getStarted) ? .info : .success,
                                    title: "Marked as \(status.displayName)",
                                    filename: entry.document.name
                                )
                            }
                        },
                        leadingPadding: 0,
                        onFirstCardFrame: attachTip ? { frame in tipAnchorFrame = frame } : nil
                    )
                    .onAppear {
                        guard attachTip, !tipSeen, !tipPresented else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1))
                            guard tipAnchorFrame != nil else { return }
                            withAnimation(.easeIn(duration: 0.2)) { tipPresented = true }
                            try? await Task.sleep(for: .seconds(4))
                            withAnimation(.easeOut(duration: 0.2)) { tipPresented = false }
                            tipSeen = true
                        }
                    }

                    Color.clear.frame(height: DSSpacing.xxs)
                }
                .padding(.leading, 3 + DSSpacing.xs)
                .background(alignment: .leading) {
                    TimelineRailShimmer(color: group.status.tintColor)
                }
                .background(
                    group.status.tintColor
                        .opacity(highlightedStatus == group.status ? 0.05 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            group.status.tintColor.opacity(highlightedStatus == group.status ? 0.8 : 0),
                            lineWidth: 1.5
                        )
                )
                .id("grid-\(group.status.rawValue)")
            }
        }
        .padding(.trailing, DSSpacing.xs)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: filteredGroupedSections.map(\.status))
    }

    /// Inline no-result content for search (dropped into the main list
    /// as a Section body) — mirrors `filteredEmptyStateContent`'s shape
    /// so the two empty states read consistently. Not a
    /// `ContentUnavailableView` because that view wants a full-screen
    /// pane, which would hide the search field + Cancel above it and
    /// leave the user unable to try a different query or back out.
    private var searchNoResultsContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
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
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.dsTextTertiary)
                    .padding(.bottom, DSSpacing.xxs)

                Text("No results")
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)

                Text("No documents match the current filter. Try a different tab or clear the date filter")
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
                    if viewModel.dateFilter != nil {
                        Button("Clear date filter") { viewModel.dateFilter = nil }
                    }
                }
                .padding(.top, DSSpacing.xs)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityElement(children: .combine)
    }


    // MARK: - Header content (subtitle + stat hero + type tabs + view controls)

    /// "You're viewing sample files" — surfaces the "Change folder…" action
    /// right where a first-run user actually needs it: looking at the 3
    /// Session-19-seeded tour files, with no signal they aren't their own docs.
    private var sampleLibraryBanner: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 32, height: 32)
                .background(Color.dsBrandPrimarySubtle, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're viewing sample files")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("Choose your own folder to see your real documents")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DSSpacing.xs)

            Button("Choose") {
                Task { await onRequestPermission() }
            }
            .font(DSFont.footnote.weight(.bold))
            .foregroundStyle(Color.dsBrandPrimary)
            .buttonStyle(.plain)
        }
        .padding(DSSpacing.sm)
        .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .strokeBorder(Color.dsBorderSubtle)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var homeBannerView: some View {
        let isIPad = horizontalSizeClass == .regular
        return Image("HomeBanner")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: isIPad ? 200 : 130)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: isIPad ? 18 : 14, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            .padding(.horizontal, DSSpacing.lg)
    }

    // Only the active-folder chip remains here; action row is in safeAreaInset.
    @ViewBuilder
    private var listHeader: some View {
        if libraryTab == .files, let folderID = activeFolderID,
           let folder = folderManager.folders.first(where: { $0.id == folderID }) {
            HStack(spacing: DSSpacing.xs) {
                Label(folder.name, systemImage: "folder.fill")
                    .font(DSFont.caption.weight(.medium))
                    .foregroundStyle(folder.color)
                Spacer(minLength: 0)
                Button {
                    activeFolderID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, 5)
            .background(folder.color.opacity(0.10), in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    // [Type▼] [Spacer] [🔍] [Filter▼] [⊞] — or inline search bar when expanded
    private var filesActionRow: some View {
        Group {
            if isSearchExpanded {
                LibrarySearchBar(
                    placeholder: "Search documents",
                    input: $viewModel.searchInput,
                    onCancel: {
                        viewModel.clearSearch()
                        withAnimation(.smooth(duration: 0.24)) { isSearchExpanded = false }
                    }
                )
            } else {
                HStack(spacing: DSSpacing.sm) {
                    typeFilterButton
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { isSearchExpanded = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.dsBrandPrimary)
                            .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                            .roundIconButtonSurface()
                    }
                    .buttonStyle(LibraryIconButtonStyle())
                    .accessibilityLabel("Search documents")
                    fileFilterButton
                    viewModeToggleButton
                }
                .frame(height: DSSize.minimumTouchTarget)
            }
        }
        .animation(.smooth(duration: 0.24), value: isSearchExpanded)
    }

    // [Type▼] — secondary chip when All; brand-filled only when a type is selected
    private var typeFilterButton: some View {
        Button {
            isTypeFilterSheetPresented = true
        } label: {
            HStack(spacing: 5) {
                if let assetName = viewModel.typeFilter.assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: viewModel.typeFilter.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
                Text(viewModel.typeFilter.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(isTypeFilterSheetPresented ? .degrees(180) : .zero)
                    .animation(.smooth(duration: 0.2), value: isTypeFilterSheetPresented)
            }
            .foregroundStyle(Color.dsTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: DSSize.minimumTouchTarget)
            .background(
                Color(UIColor.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(LibraryIconButtonStyle())
        .popover(isPresented: $isTypeFilterSheetPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            TypeFilterSheet(selection: $viewModel.typeFilter)
                .frame(width: 300)
                .presentationCompactAdaptation(.none)
        }
        .accessibilityLabel(viewModel.typeFilter == .all ? "Filter by type" : "Type: \(viewModel.typeFilter.displayName)")
    }

    // [Filter] — funnel icon (not circle variant) avoids confusion with List-view toggle
    private var fileFilterButton: some View {
        let isActive = viewModel.dateFilter != nil || viewModel.favouritesOnly
        return Button {
            isFileFilterSheetPresented = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: isActive ? .bold : .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                .roundIconButtonSurface(isActive: isActive)
        }
        .buttonStyle(LibraryIconButtonStyle())
        .popover(isPresented: $isFileFilterSheetPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            FileFilterSheet(
                favouritesOnly: $viewModel.favouritesOnly,
                dateFilter: Binding(
                    get: { viewModel.dateFilter },
                    set: { viewModel.dateFilter = $0 }
                )
            )
            .frame(width: 300)
            .presentationCompactAdaptation(.none)
        }
        .accessibilityLabel(isActive ? "Filters active" : "Filter documents")
    }

    // MARK: - Title + premium

    private var titleRow: some View {
        HStack(alignment: .center, spacing: DSSpacing.xs) {
            Text("Cabinet")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .layoutPriority(1)
            Spacer(minLength: 4)
            PremiumButton { isPaywallPresented = true }
        }
        .padding(.top, DSSpacing.sm)
        .padding(.bottom, DSSpacing.xxs)
    }

    // MARK: - Files/Folders custom tab switcher

    private var libTabRow: some View {
        HStack(spacing: 2) {
            libTabSegment(.files, "Files")
            libTabSegment(.folders, "Folders")
        }
        .padding(4)
        .background {
            ZStack {
                // Outer shell
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
                    )
                // Single sliding indicator — offset-based, no matchedGeometryEffect.
                // Works correctly even when two libTabRow instances exist simultaneously
                // (cross-fade transition), because each instance animates its own offset
                // independently rather than competing for a shared namespace.
                GeometryReader { geo in
                    let pad: CGFloat = 4
                    let gap: CGFloat = 2
                    let w = (geo.size.width - pad * 2 - gap) / 2
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.dsBrandPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: Color.dsBrandPrimary.opacity(0.25), radius: 6, y: 2)
                        .frame(width: w, height: 46)
                        .offset(x: libraryTab == .files ? pad : (pad + w + gap), y: pad)
                        .animation(.smooth(duration: 0.22), value: libraryTab)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: libraryTab)
    }

    private func libTabSegment(_ tab: LibraryTab, _ title: String) -> some View {
        let isSelected = libraryTab == tab
        return Button {
            withAnimation(.smooth(duration: 0.22)) { libraryTab = tab }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.dsTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Trailing actions

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
        .buttonStyle(LibraryIconButtonStyle())
        .sensoryFeedback(.selection, trigger: viewMode)
        .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")
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
    /// One-tap "Mark as Done" from the kebab menu (2026-09-14) — a shortcut
    /// for the single most common status transition, alongside the
    /// existing long-press "Change status" context menu which still
    /// exposes all 3 statuses.
    private func performMarkDone(entry: LibraryEntry) async {
        await viewModel.setStatus(.done, for: entry.id)
        toaster.show(.success, title: "Marked as Done", filename: entry.document.name)
    }

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
        // Delay matches the kebab-menu dismiss animation (~350ms) so the
        // fullScreenCover is fully gone before the confirmation dialog fires.
        // Without the delay the dialog presents while the cover is still on
        // screen and renders as a centered floating card instead of an action
        // sheet, because it can't find the correct presentation host.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            pendingZipRequest = PendingZipRequest(entryID: entryID, filename: name)
        }
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

    // MARK: - Context menu (unchanged — long-press to change status)

    @ViewBuilder
    private func contextMenu(for entry: LibraryEntry) -> some View {
        Section("Change status") {
            ForEach(DocumentStatus.userSelectableCases) { status in
                Button {
                    Task {
                        await viewModel.setStatus(status, for: entry.id)
                        toaster.show(
                            (status == .draft || status == .getStarted) ? .info : .success,
                            title: "Marked as \(status.displayName)",
                            filename: entry.document.name
                        )
                    }
                } label: {
                    Label(status.displayName, systemImage: status.systemImage)
                }
                .disabled(status == entry.metadata.status)
            }
        }

        if !folderManager.folders.isEmpty {
            Section("Folders") {
                Button {
                    folderAssignEntryID = entry.id
                } label: {
                    let currentFolder = folderManager.folder(for: entry.id)
                    Label(
                        currentFolder != nil ? "Move to Folder…" : "Add to Folder…",
                        systemImage: "folder.badge.plus"
                    )
                }
            }
        }
    }
}


// MARK: - View mode

enum LibraryViewMode: String {
    case list
    case grid
}

// MARK: - Library tab

enum LibraryTab: String, Hashable {
    case files
    case folders
}

// MARK: - Section navigation

/// Typed navigation key for `NavigationStack.navigationDestination(for:)`.
/// Replaces bare `DocumentStatus` appends so the "Continue Working" section
/// can share the same `navPath` without a separate destination registration.
enum LibrarySectionID: Hashable {
    case status(DocumentStatus)
    case continueWorking
    case folder(UUID)
}

/// Wraps a String entry ID so it can be used with `sheet(item:)`.
private struct FolderAssignID: Identifiable {
    let id: String
}

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

/// Section header for `groupedSections` — plain "Draft (2)" (label + live count)
/// with a thin colored accent bar on the leading edge. The same `tintColor` bar
/// runs along each card's leading edge in `row(for:)`, so "these rows belong
/// together" comes from repeated color within a section.
private struct StatusSectionHeader: View {
    let status: DocumentStatus
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(status.tintColor)
                .frame(width: 3)
            Text("\(status.displayName) (\(count))")
                .font(DSFont.title3.weight(.bold))
                .foregroundStyle(status.tintColor)
                .padding(.leading, DSSpacing.md)
        }
        .padding(.leading, -DSSpacing.lg)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.growDownward.combined(with: .opacity))
    }
}

/// `AnyTransition.scale` only takes one uniform `scale:` factor — no
/// separate x/y variant — so a "grows downward, doesn't shrink sideways"
/// reveal needs a custom transition built on `.scaleEffect(x:y:anchor:)`
/// via `Animatable`, not the built-in `.scale`.
private struct VerticalGrowModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.scaleEffect(x: 1, y: progress, anchor: .top)
    }
}

private extension AnyTransition {
    static var growDownward: AnyTransition {
        .modifier(
            active: VerticalGrowModifier(progress: 0),
            identity: VerticalGrowModifier(progress: 1)
        )
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
            .shadow(color: .black.opacity(0.07), radius: 4, y: 1.5)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

private extension View {
    func roundIconButtonSurface(isActive: Bool = false) -> some View {
        modifier(RoundIconButtonSurface(isActive: isActive))
    }
}

// MARK: - Search bar (extracted for focus-state isolation)

/// Popover type filter — shown anchored below the Type pill; avoids covering action-row icons.
private struct TypeFilterSheet: View {
    @Binding var selection: DocumentTypeFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filter by Type")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xs)

            ForEach(DocumentTypeFilter.allCases) { filter in
                Button {
                    selection = filter
                    dismiss()
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Group {
                            if let assetName = filter.assetName {
                                Image(assetName)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: filter.systemImage)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.dsBrandPrimary)
                            }
                        }
                        .frame(width: 34, height: 34)

                        Text(filter.displayName)
                            .font(DSFont.body)
                            .foregroundStyle(Color.dsTextPrimary)

                        Spacer(minLength: 0)

                        if filter == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.dsBrandPrimary)
                        }
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if filter != DocumentTypeFilter.allCases.last {
                    Divider()
                        .padding(.leading, DSSpacing.lg + 34 + DSSpacing.sm)
                }
            }

            Color.clear.frame(height: DSSpacing.md)
        }
    }
}

/// Popover file filter — Favourites toggle + date modified picker.
private struct FileFilterSheet: View {
    @Binding var favouritesOnly: Bool
    @Binding var dateFilter: DateBucket?
    @Environment(\.dismiss) private var dismiss

    private var isActive: Bool { favouritesOnly || dateFilter != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Filters")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: 0)
                if isActive {
                    Button {
                        favouritesOnly = false
                        dateFilter = nil
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.dsBrandPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.xs)

            Toggle(isOn: $favouritesOnly) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: favouritesOnly ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundStyle(favouritesOnly ? Color.yellow : Color.dsBrandPrimary)
                        .frame(width: 34, height: 34)
                    Text("Favourites Only")
                        .font(DSFont.body)
                        .foregroundStyle(Color.dsTextPrimary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)

            Divider()
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.xs)

            Text("Date Modified")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dsTextSecondary)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xxs)

            dateRow("All Time", icon: "calendar", value: nil)

            Divider().padding(.leading, DSSpacing.lg + 34 + DSSpacing.sm)

            ForEach(DateBucket.allCases, id: \.self) { bucket in
                dateRow(bucket.displayName, icon: "calendar.badge.clock", value: bucket)
                if bucket != DateBucket.allCases.last {
                    Divider().padding(.leading, DSSpacing.lg + 34 + DSSpacing.sm)
                }
            }

            Color.clear.frame(height: DSSpacing.lg)
        }
    }

    private func dateRow(_ label: String, icon: String, value: DateBucket?) -> some View {
        Button {
            dateFilter = value
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.dsBrandPrimary)
                    .frame(width: 34, height: 34)
                Text(label)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: 0)
                if dateFilter == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Spring press animation for round icon buttons (search, filter, view-mode).
private struct LibraryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Inline search bar for sticky `safeAreaInset` headers.
/// Always shows Cancel + auto-focuses on appear.
/// Does NOT call `hidesTabBarVisually` — safe inside safeAreaInset.
private struct LibrarySearchBar: View {
    var placeholder: String = "Search"
    @Binding var input: String
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            searchPill
            cancelButton
        }
        .frame(height: DSSize.minimumTouchTarget)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isFocused)
        .task { isFocused = true }
    }

    private var searchPill: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? Color.dsBrandPrimary : Color.dsTextSecondary)
                .font(.system(size: 15, weight: .medium))
            TextField(placeholder, text: $input)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
            if !input.isEmpty {
                Button { input = "" } label: {
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
                isFocused ? Color.dsBrandPrimary.opacity(0.4) : Color.dsBorderSubtle.opacity(0.5),
                lineWidth: isFocused ? 1.2 : 0.5
            )
        )
        .shadow(color: .black.opacity(0.09), radius: 6, y: 4)
    }

    private var cancelButton: some View {
        Button {
            isFocused = false
            input = ""
            onCancel()
        } label: {
            Text("Cancel")
                .font(DSFont.body)
                .foregroundStyle(Color.dsBrandPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close search")
    }
}

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
        // Hide the tab bar while the keyboard is up so search results
        // have the full screen. Published as a preference here (not on
        // LibraryView) to preserve the @FocusState isolation that keeps
        // LibraryView.body from re-running on every keystroke.
        .hidesTabBarVisually(isFocused)
    }

    // MARK: - Pieces

    private var searchFieldPill: some View {
        HStack(spacing: DSSpacing.xs) {
            Button { isFocused = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .buttonStyle(.plain)
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
        .shadow(color: .black.opacity(0.09), radius: 6, y: 4)
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

// MARK: - Folders first-launch tip

private struct FoldersTipBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Organise with folders")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text("Long-press any file and tap \u{201C}Add to Folder\u{201D} to keep your documents organised")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.smooth(duration: 0.25)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.dsTextTertiary)
                    .frame(width: 28, height: 28)
                    .background(Color(UIColor.systemFill), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(DSSpacing.sm)
        .background(Color.dsBrandPrimary.opacity(0.07), in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBrandPrimary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

private struct TipCalloutSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct TipCallout: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Your file is here — edit it to update its working status")
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .frame(maxWidth: 260)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .fill(Color.dsBackgroundElevated)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                }
            Image(systemName: "arrowtriangle.down.fill")
                .resizable()
                .frame(width: 14, height: 8)
                .foregroundStyle(Color.dsBackgroundElevated)
                .offset(y: -1)
        }
    }
}

// MARK: - ZIP Confirm Dialog

/// Centered confirmation dialog with a scrim — replaces the native
/// `.confirmationDialog` so we can add a semi-transparent overlay behind
/// the card (the native API provides none).
private struct ZipConfirmDialog: View {
    let filename: String
    let onKeepBoth: () -> Void
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                // Header
                VStack(spacing: DSSpacing.xs) {
                    Text("Convert \u{201C}\(filename)\u{201D} to ZIP")
                        .font(DSFont.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.dsTextPrimary)
                    Text("Keep \u{201C}\(filename)\u{201D} alongside the new ZIP, or replace it with the archive?")
                        .font(DSFont.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.md)

                Divider()

                DialogButton(label: "Keep Both", color: Color.dsBrandPrimary, weight: .medium, action: onKeepBoth)

                Divider()

                DialogButton(label: "Replace with ZIP", color: Color.dsStatusError, weight: .medium, action: onReplace)

                Divider()

                DialogButton(label: "Cancel", color: Color.dsTextSecondary, weight: .regular, action: onCancel)
            }
            .background(Color.dsBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            .padding(.horizontal, DSSpacing.xl)
        }
    }
}

private struct DialogButton: View {
    let label: String
    let color: Color
    let weight: Font.Weight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DSFont.body.weight(weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(DialogButtonStyle())
    }
}

private struct DialogButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.dsSurfacePressed : Color.clear)
    }
}

// MARK: - Folder detail (reactive)

/// Reactive folder-detail screen. Because `store.entries` is read inside this
/// struct's `body`, `@Observable` tracks the dependency and re-renders whenever
/// entries load or change — fixing the blank "No files" state that occurred when
/// `navigationDestination` built the view before the store had finished loading.
private struct FolderDetailContent: View {
    let folderID: UUID
    let folderName: String
    let folderColor: Color
    let store: LibraryStore

    var onBack: () -> Void
    var onTap: (LibraryEntry) -> Void
    var onSaveExport: (LibraryEntry) -> Void
    var onToggleFavourite: (LibraryEntry) -> Void
    var onRename: (LibraryEntry, String) async -> Bool
    var onConvertToZip: (LibraryEntry) -> Void
    var onMarkDone: (LibraryEntry) -> Void
    var onDeleteFile: (LibraryEntry) -> Void
    var onChangeStatus: (LibraryEntry, DocumentStatus) -> Void

    @State private var localSearch: String = ""
    @State private var viewMode: LibraryViewMode = .list

    var body: some View {
        // Read directly from @Observable store + FolderManager in body so SwiftUI
        // auto-tracks both — no onAppear/onChange needed.
        let fm = FolderManager.shared
        let ids = Set(fm.assignments.compactMap { $0.value == folderID ? $0.key : nil })
        let folderEntries = store.entries
            .filter { ids.contains($0.id) }
            .sorted { $0.document.modifiedAt > $1.document.modifiedAt }

        let query = localSearch.trimmingCharacters(in: .whitespaces)
        let displayed: [LibraryEntry] = query.isEmpty
            ? folderEntries
            : folderEntries.filter { $0.document.name.localizedCaseInsensitiveContains(query) }

        let continueItems = displayed
            .filter { $0.metadata.isContinueWorking }
            .sorted { $0.metadata.lastModifiedAt > $1.metadata.lastModifiedAt }
        let continueIDs = Set(continueItems.map(\.id))
        let rest = displayed.filter { !continueIDs.contains($0.id) }

        let grouped = Dictionary(grouping: rest) { $0.metadata.status }
        let sections: [(status: DocumentStatus, entries: [LibraryEntry])] = DocumentStatus.allCases.compactMap { s in
            guard let es = grouped[s], !es.isEmpty else { return nil }
            return (s, es)
        }
        let gridEntries = continueItems + rest
        let isEmpty = displayed.isEmpty

        return listBody(query: query, continueItems: continueItems,
                        sections: sections, gridEntries: gridEntries, isEmpty: isEmpty)
    }

    // MARK: List body

    @ViewBuilder
    private func listBody(
        query: String,
        continueItems: [LibraryEntry],
        sections: [(status: DocumentStatus, entries: [LibraryEntry])],
        gridEntries: [LibraryEntry],
        isEmpty: Bool
    ) -> some View {
        List {
            if viewMode == .list {
                // ── Continue Working (brand rail — matches Home) ──
                if !continueItems.isEmpty {
                    Section {
                        cwHeader(count: continueItems.count)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 3,
                                                       bottom: 0, trailing: DSSpacing.xs))
                            .listRowBackground(HStack(spacing: 0) {
                                Color.dsBrandPrimary.frame(width: 3); Color.clear
                            })
                        ForEach(continueItems) { entry in
                            cardRow(for: entry)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: 3 + DSSpacing.xs,
                                                           bottom: DSSpacing.xs, trailing: DSSpacing.xs))
                                .listRowBackground(HStack(spacing: 0) {
                                    Color.dsBrandPrimary.frame(width: 3); Color.clear
                                })
                        }
                    }
                }

                // ── Status sections (colored rail) ──
                ForEach(sections, id: \.status) { group in
                    let isFirst = group.status == sections.first?.status
                    Section {
                        sectionHeader(status: group.status, count: group.entries.count)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: isFirst && continueItems.isEmpty ? 0 : DSSpacing.xs,
                                                       leading: 3,
                                                       bottom: 0,
                                                       trailing: DSSpacing.xs))
                            .listRowBackground(HStack(spacing: 0) {
                                group.status.tintColor.frame(width: 3); Color.clear
                            })
                        ForEach(group.entries) { entry in
                            cardRow(for: entry)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: 3 + DSSpacing.xs,
                                                           bottom: DSSpacing.xs, trailing: DSSpacing.xs))
                                .listRowBackground(HStack(spacing: 0) {
                                    group.status.tintColor.frame(width: 3); Color.clear
                                })
                        }
                    }
                }
            } else {
                // ── Grid mode: section headers + per-group grids ──
                if !continueItems.isEmpty {
                    Section {
                        cwHeader(count: continueItems.count)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 3,
                                                       bottom: DSSpacing.xs, trailing: DSSpacing.xs))
                            .listRowBackground(HStack(spacing: 0) {
                                Color.dsBrandPrimary.frame(width: 3); Color.clear
                            })
                        gridSection(entries: continueItems, tintColor: Color.dsBrandPrimary)
                    }
                }
                ForEach(sections, id: \.status) { group in
                    let isFirst = group.status == sections.first?.status
                    Section {
                        sectionHeader(status: group.status, count: group.entries.count)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: isFirst && continueItems.isEmpty ? 0 : DSSpacing.sm,
                                                       leading: 3,
                                                       bottom: DSSpacing.xs,
                                                       trailing: DSSpacing.xs))
                            .listRowBackground(HStack(spacing: 0) {
                                group.status.tintColor.frame(width: 3); Color.clear
                            })
                        gridSection(entries: group.entries, tintColor: group.status.tintColor)
                    }
                }
            }

            // Bottom safe-area spacer
            Section {
                Color.clear
                    .frame(height: DSTabBarMetrics.listContentTrailingSpacer)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(6)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .autoHidesTabBarOnScroll()
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { localSearch = "" }
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No files in this folder" : "No results",
                    systemImage: query.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(query.isEmpty
                        ? "Assign files to this folder from the library"
                        : "No documents match \"\(query)\"")
                )
            }
        }
        // ── Sticky title + search header ──
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                // Title row — back button left, folder name centered
                ZStack {
                    Text(folderName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 56)
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.dsBrandPrimary)
                                .frame(width: DSSize.minimumTouchTarget,
                                       height: DSSize.minimumTouchTarget)
                                .roundIconButtonSurface()
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .frame(height: 52)

                // Search + view-mode toggle
                LibrarySearchAndActionsBar(
                    input: $localSearch,
                    onClear: { localSearch = "" }
                ) {
                    viewModeToggle
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }
            // Matches insetGrouped list background so the sticky header blends seamlessly.
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }
    }

    // One grid row for a set of entries inside the folder detail grid mode.
    // tintColor drives the 3pt left rail in listRowBackground — matches list mode rail pattern.
    // leadingPadding = 3 + DSSpacing.xs so grid tiles align with list-mode card edges (same 8pt gap from rail).
    private func gridSection(entries: [LibraryEntry], tintColor: Color) -> some View {
        DocumentGrid(
            entries: entries,
            onTap: { onTap($0) },
            onSaveExport: { onSaveExport($0) },
            onToggleFavourite: { onToggleFavourite($0) },
            onRename: { entry, stem in await onRename(entry, stem) },
            onConvertToZip: { onConvertToZip($0) },
            onMarkDone: { onMarkDone($0) },
            onDeleteFile: { onDeleteFile($0) },
            onChangeStatus: { onChangeStatus($0, $1) },
            leadingPadding: 3 + DSSpacing.xs
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(HStack(spacing: 0) {
            tintColor.frame(width: 3)
            Color.clear
        })
        .listRowSeparator(.hidden)
    }

    // Continue Working section header — mirrors Home's continueWorkingTabHeader (brand pill + dot count).
    private func cwHeader(count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Continue Working")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.dsBrandPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.dsBrandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.dsBrandPrimary)
                        .frame(width: 7, height: 7)
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsBrandPrimary.opacity(0.6))
                }
            }
            .padding(.bottom, DSSpacing.sm)
        }
    }

    // MARK: Helpers

    private func cardRow(for entry: LibraryEntry) -> some View {
        DocumentCard(
            entry: entry,
            onTap: { onTap(entry) },
            onSaveExport: { onSaveExport(entry) },
            onToggleFavourite: { onToggleFavourite(entry) },
            onRename: { stem in await onRename(entry, stem) },
            onConvertToZip: { onConvertToZip(entry) },
            onMarkDone: { onMarkDone(entry) },
            onDeleteFile: { onDeleteFile(entry) }
        )
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 10)
        .background(Color.dsBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            .strokeBorder(Color.dsBorderSubtle))
        .dsCardShadow()
    }

    // Section header — mirrors Home's statusTabHeader (same pill + dot count, 15pt font).
    private func sectionHeader(status: DocumentStatus, count: Int) -> some View {
        let bg: Color = switch status {
        case .getStarted: Color.dsBrandPrimary.opacity(0.08)
        case .draft:      .dsStatusWarningBackground
        case .reviewed:   .dsBrandPrimarySubtle
        case .done:       .dsStatusSuccessBackground
        }
        return VStack(spacing: 0) {
            HStack(spacing: DSSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                    Text(status.displayName)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(status.tintColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.tintColor)
                        .frame(width: 7, height: 7)
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(status.tintColor.opacity(0.6))
                }
            }
            .padding(.bottom, DSSpacing.sm)
        }
    }

    private var viewModeToggle: some View {
        Button {
            viewMode = viewMode == .list ? .grid : .list
        } label: {
            Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
                .frame(width: DSSize.minimumTouchTarget, height: DSSize.minimumTouchTarget)
                .roundIconButtonSurface()
        }
        .buttonStyle(LibraryIconButtonStyle())
        .sensoryFeedback(.selection, trigger: viewMode)
        .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")
    }
}

// MARK: - Isolated shimmer rail

/// Animated 3pt timeline rail segment. Owns its own `@State` so the animation
/// loop never invalidates its parent (LibraryView). Without extraction,
/// `.repeatForever` on a parent `@State` causes the entire LibraryView body
/// to re-evaluate at 60fps even while the user is just scrolling.
private struct TimelineRailShimmer: View {
    let color: Color
    @State private var phase: CGFloat = -0.15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(color)
            if !reduceMotion {
                LinearGradient(
                    stops: [
                        .init(color: .clear,               location: max(0, min(1, phase - 0.12))),
                        .init(color: .white.opacity(0.55),  location: max(0, min(1, phase))),
                        .init(color: .clear,               location: max(0, min(1, phase + 0.12))),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: 3)
        .onAppear {
            guard !reduceMotion else { return }
            phase = -0.15
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                phase = 1.15
            }
        }
    }
}
