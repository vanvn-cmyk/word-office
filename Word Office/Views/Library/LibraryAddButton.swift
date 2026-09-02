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
    @Bindable var viewModel: LibraryViewModel
    let container: DependencyContainer

    @State private var isMenuOpen = false
    @State private var isPresentingImporter = false
    @State private var isPresentingScan = false
    @State private var comingSoonKind: DocumentKind?
    @State private var ocrVM: OCRViewModel?

    var body: some View {
        VStack(alignment: .trailing, spacing: DSSpacing.sm) {
            if isMenuOpen {
                addMenuContent
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
            fabButton
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
            isMenuOpen ? closeMenu() : openMenu()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
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
    }

    private func menuSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DSFont.caption.weight(.semibold))
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xxs)
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
