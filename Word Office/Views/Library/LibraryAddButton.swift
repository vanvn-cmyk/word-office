import SwiftUI

/// The Library "+" — one sibling view in `RootView.customTabBar`'s `HStack`,
/// next to the tab bar pill (same row, always visible, all 3 tabs). Two
/// native mechanisms for achieving this were tried first and both broke real
/// rendering, which is why the tab bar is hand-drawn instead of a system
/// `TabView`/`Tab`:
/// - `.overlay(alignment:)` attached directly to a `TabView` produced a dark
///   corner-clipping artifact on the tab bar itself, on every tab.
/// - `.tabViewBottomAccessory` (Apple's dedicated "control beside the tab
///   bar" slot) turned out to be built for bar-shaped content: it wraps
///   whatever you give it in its own full-width pill container and **clips**
///   anything that expands beyond that container's bounds — including this
///   view's own popup menu when opened.
/// As a plain sibling in a hand-drawn `HStack` there's no system layer left
/// to fight, so this same view works unmodified.
///
/// The menu itself is a self-built overlay (not `.popover`) so open/close
/// timing is fully ours via explicit `withAnimation` calls — `.popover`'s own
/// adaptive presentation/dismissal timing was fighting the icon's rotation
/// and made the close transition read as sluggish.
struct LibraryAddButton: View {
    /// Diameter of the circular FAB. Also used to compute how far above the
    /// FAB the popup menu sits (see `body`'s `.padding(.bottom, ...)`), so both
    /// values stay in lockstep.
    static let fabDiameter: CGFloat = 60

    @Bindable var viewModel: LibraryViewModel
    let container: DependencyContainer
    /// Read here so the FAB scan sheet's inner `.toastHost(_:)` can bridge
    /// the environment presenter into an explicit param — SwiftUI sheets
    /// present above scene-root overlays, and the scene's toast host is
    /// invisible under a sheet. Same reason `EditorSheet` also hosts
    /// its own toast.
    @Environment(DSToastPresenter.self) private var toaster
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Open state of the popup menu — owned by `RootView` and threaded in
    /// here so `RootView.libraryShell` can render a full-screen invisible
    /// scrim that dismisses the menu on any outside tap (matching native
    /// `Menu`/`.popover` UX). If this were `@State private` here, the scrim
    /// couldn't observe or write the flag.
    @Binding var isMenuOpen: Bool
    @State private var isPresentingImporter = false
    @State private var isPresentingScan = false
    @State private var comingSoonKind: DocumentKind?

    /// Eager-init in `init` (via `State(wrappedValue:)`) rather than lazily
    /// in `.task { ocrVM = container.make…() }` on `body`. The lazy pattern
    /// produced a real bug in `ToolsTabView` (see its file comment): a `.task`
    /// on a view mounted inside the ZStack-of-three-tabs did not populate
    /// state before a downstream sheet (`.sheet(isPresented: $isPresentingScan)`
    /// here) tried to read it, so the sheet rendered a `ProgressView`
    /// fallback and never updated. `LibraryAddButton` is in exactly that
    /// mount pattern (it's a sibling in `RootView.customTabBar`, always
    /// alive even when the Library tab is not selected), so it has the same
    /// exposure and needs the same eager-init fix.
    @State private var ocrVM: OCRViewModel

    init(viewModel: LibraryViewModel, container: DependencyContainer, isMenuOpen: Binding<Bool>) {
        self._viewModel = Bindable(wrappedValue: viewModel)
        self.container = container
        self._isMenuOpen = isMenuOpen
        self._ocrVM = State(wrappedValue: container.makeOCRViewModel())
    }

    var body: some View {
        // `fabButton` is the ONLY layout-participating child here. The popup
        // menu attaches via `.overlay` so it doesn't contribute to this view's
        // size — otherwise the enclosing `HStack` in `RootView.customTabBar`
        // expands to the menu's 220pt width when opened, pushing FAB + menu
        // past the right screen edge (tab pill ~228 + spacing 12 + menu 220 =
        // 460 > screen width - 32pt padding on any current iPhone).
        //
        // Positioning trick: anchor the padded box's BOTTOM-trailing corner to
        // the FAB's bottom-trailing corner (via `.overlay(alignment:
        // .bottomTrailing)`), then pad the menu at the bottom by
        // (`Self.fabDiameter` + `DSSpacing.lg`). The invisible bottom padding
        // pushes the visible menu upward so its bottom sits `DSSpacing.lg`
        // above the FAB's top edge. `.fixedSize()` guards against the
        // overlay's parent-size proposal (56×56) squeezing the menu's
        // intrinsic 220×~380 dimensions.
        //
        // Why `DSSpacing.lg` and not a smaller value: the sibling tab pill in
        // `RootView.customTabBar` uses the same `HStack(alignment: .bottom)`,
        // and the pill is 12pt taller than the FAB (56 button + 12pt inner
        // padding for the material capsule), so its TOP sits 12pt above the
        // FAB's top. A gap of just `DSSpacing.sm` (12pt) puts the menu bottom
        // flush with the pill's top — visually reads as overlap. `DSSpacing.lg`
        // (20pt) clears the pill top with 8pt of visible breathing room.
        //
        // Padding was preferred over `.alignmentGuide(.top)` here because
        // `.transition` did not reliably propagate a modified `.top` guide out
        // to the overlay's alignment placement in practice — the menu
        // rendered downward from FAB.top instead of upward.
        fabButton
            .overlay(alignment: .bottomTrailing) {
                if isMenuOpen {
                    addMenuContent
                        .fixedSize()
                        .padding(.bottom, Self.fabDiameter + DSSpacing.lg)
                        .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .fileImporter(
                isPresented: $isPresentingImporter,
                allowedContentTypes: AddFileMenu.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await viewModel.importFiles(from: urls) }
                }
            }
            .alert(
                "Coming soon",
                isPresented: Binding(
                    get: { comingSoonKind != nil },
                    set: { if !$0 { comingSoonKind = nil } }
                ),
                presenting: comingSoonKind
            ) { _ in
                Button("OK", role: .cancel) { comingSoonKind = nil }
            } message: { kind in
                Text("Creating a blank \(kind.displayName) document needs the full Office SDK, which isn't wired in yet. Word documents already work — or import an existing file")
            }
            .sheet(isPresented: $isPresentingScan) {
                NavigationStack {
                    // Sheet root has no back chevron; ScanFlowView needs its
                    // own Cancel here — differs from the Tools-tab push where
                    // the system back chevron already covers dismissal.
                    ScanFlowView(viewModel: ocrVM, showsExplicitCancel: true)
                }
                // In-sheet toast host — save-success toasts fired from
                // ScanFlowView would otherwise render below this sheet and
                // stay invisible for the 3s dismiss window.
                .toastHost(toaster)
            }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            if isMenuOpen { $isMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion) } else { openMenu() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.dsTextOnBrand)
                .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
                .frame(width: Self.fabDiameter, height: Self.fabDiameter)
        }
        // Liquid Glass with brand tint + interactive feedback (iOS 26
        // pattern, matches Apple Music / Reminders floating action
        // buttons). `.interactive()` gives the built-in press dip that
        // glass surfaces have — better than a custom scale animation.
        // `GlassEffectContainer` in `RootView.customTabBar` groups this
        // with the tab pill for coherent glass sampling.
        .glassEffect(.regular.tint(Color.dsBrandPrimary).interactive(), in: .circle)
        .shadow(color: Color.dsBrandPrimary.opacity(0.28), radius: 12, y: 6)
        .accessibilityLabel(isMenuOpen ? "Close" : "Add")
    }

    /// Explicit `withAnimation` (not one shared `.animation(value:)` on the
    /// container) — open gets its own short, fixed duration instead of
    /// inheriting whatever transaction happens to be in flight, which is
    /// what made the close transition feel sluggish under `.popover`.
    /// Closing is handled by the shared `Binding<Bool>.closeMenuAnimated`
    /// helper (see `Binding+MenuAnimation.swift`) — every closer, whether
    /// menu row, scrim tap, tab switch, or FAB re-tap, uses the same
    /// idempotent guard + 0.15s ease-out, so they can never drift apart.
    private func openMenu() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isMenuOpen = true }
    }

    // MARK: - Menu content

    private var addMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuSectionHeader("Create new")
            ForEach([DocumentKind.docx, .xlsx, .pptx], id: \.self) { kind in
                menuRow(image: iconAssetName(for: kind), title: createLabel(for: kind)) {
                    $isMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion)
                    Task { await handleCreate(kind: kind) }
                }
            }

            Divider().padding(.vertical, DSSpacing.xxs)

            menuSectionHeader("Add existing")
            menuRow(icon: "square.and.arrow.down", title: "Import file") {
                $isMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion)
                isPresentingImporter = true
            }

            Divider().padding(.vertical, DSSpacing.xxs)

            menuSectionHeader("Scan")
            menuRow(icon: "viewfinder", title: "Scan document") {
                $isMenuOpen.closeMenuAnimated(reduceMotion: reduceMotion)
                isPresentingScan = true
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .frame(width: 220)
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous).strokeBorder(Color.dsBorderSubtle))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        // `.contentShape` on the finished card so the whole card absorbs
        // hit-testing. Without this, taps into "dead" regions (section
        // headers, dividers, padding between rows) fall through the overlay
        // to the underlying `fabButton` and toggle the menu shut
        // unexpectedly — SwiftUI's `.background(Color, in: Shape)` fill
        // isn't guaranteed to absorb taps for the overlay parent.
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        // Group the menu for VoiceOver so it reads as a labeled container
        // of options rather than 5 orphan buttons floating next to the FAB.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add options")
    }

    private func menuSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DSFont.caption.weight(.semibold))
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DSFont.body)
                .foregroundStyle(Color.dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }

    /// Same shape as the SF-Symbol overload above, but takes an asset
    /// image name so the Create New rows can render the full-color app
    /// icons (Word / Excel / PowerPoint) instead of the generic
    /// `doc.text` / `tablecells` / `rectangle.on.rectangle` symbols.
    /// Import file and Scan document keep the symbol overload — they
    /// aren't tied to one document family.
    private func menuRow(image: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(image)
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }

    private func handleCreate(kind: DocumentKind) async {
        let outcome = await viewModel.createBlankDocument(kind: kind)
        if outcome == .unsupported {
            comingSoonKind = kind
        }
    }

    private func createLabel(for kind: DocumentKind) -> String {
        switch kind {
        case .docx: "Word document"
        case .xlsx: "Spreadsheet"
        case .pptx: "Presentation"
        default:    kind.displayName
        }
    }

    /// Asset name for the Create New menu row icons — matches the four
    /// imageset folders in `Assets.xcassets`. The `default` branch is
    /// unreachable in practice (the forEach iterates the fixed
    /// `[.docx, .xlsx, .pptx]` triple) but Swift requires exhaustive
    /// switch on the open `DocumentKind` enum.
    private func iconAssetName(for kind: DocumentKind) -> String {
        switch kind {
        case .docx: return "DocumentIconWord"
        case .xlsx: return "DocumentIconSpreadsheet"
        case .pptx: return "DocumentIconPresentation"
        default:
            assertionFailure("iconAssetName: no asset for \(kind) — add it to Assets.xcassets")
            return ""
        }
    }
}
