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
    static let fabDiameter: CGFloat = 56

    @Bindable var viewModel: LibraryViewModel
    let container: DependencyContainer

    /// Open state of the popup menu — owned by `RootView` and threaded in
    /// here so `RootView.libraryShell` can render a full-screen invisible
    /// scrim that dismisses the menu on any outside tap (matching native
    /// `Menu`/`.popover` UX). If this were `@State private` here, the scrim
    /// couldn't observe or write the flag.
    @Binding var isMenuOpen: Bool
    @State private var isPresentingImporter = false
    @State private var isPresentingScan = false
    @State private var comingSoonKind: DocumentKind?
    @State private var ocrVM: OCRViewModel?

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
                    if let ocrVM {
                        ScanFlowView(viewModel: ocrVM)
                    } else {
                        ProgressView()
                    }
                }
            }
            .task { if ocrVM == nil { ocrVM = container.makeOCRViewModel() } }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            if isMenuOpen { closeMenu() } else { openMenu() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.fabDiameter, height: Self.fabDiameter)
                .background(
                    LinearGradient(
                        colors: [Color.dsBrandPrimary, Color.dsBrandPrimaryPressed],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Circle()
                )
                .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 14, y: 6)
                .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
        }
        .accessibilityLabel(isMenuOpen ? "Close" : "Add")
    }

    /// Explicit `withAnimation` at both call sites (not one shared `.animation(value:)`
    /// on the container) — open and close each get their own short, fixed duration
    /// instead of inheriting whatever transaction happens to be in flight, which is
    /// what made the close transition feel sluggish under `.popover`.
    private func openMenu() {
        withAnimation(.easeOut(duration: 0.2)) { isMenuOpen = true }
    }

    private func closeMenu() {
        // Idempotency guard: if `isMenuOpen` is already false when this
        // fires (e.g., the outside-tap scrim in `RootView` already toggled
        // the shared binding one tick before a menu row's action ran),
        // opening a `withAnimation` transaction on a no-op state change
        // spends a frame animating nothing. Mirrors `RootView.closeFABMenu`.
        guard isMenuOpen else { return }
        withAnimation(.easeOut(duration: 0.15)) { isMenuOpen = false }
    }

    // MARK: - Menu content

    private var addMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuSectionHeader("Create new")
            ForEach([DocumentKind.docx, .xlsx, .pptx], id: \.self) { kind in
                menuRow(icon: kind.systemImage, title: createLabel(for: kind)) {
                    closeMenu()
                    Task { await handleCreate(kind: kind) }
                }
            }

            Divider().padding(.vertical, DSSpacing.xxs)

            menuSectionHeader("Add existing")
            menuRow(icon: "square.and.arrow.down", title: "Import file") {
                closeMenu()
                isPresentingImporter = true
            }

            Divider().padding(.vertical, DSSpacing.xxs)

            menuSectionHeader("Scan")
            menuRow(icon: "viewfinder", title: "Scan document") {
                closeMenu()
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
}
