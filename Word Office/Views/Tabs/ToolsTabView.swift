import SwiftUI

/// Tools home — unified 2-column card grid across Convert / Organize /
/// Fill & Sign, per approved mockup `Wireframe/Tools-Home-CardGrid-v1.html`.
/// Scan & OCR stays as a standalone hero above the grids (spec §6 —
/// primary attention grabber).
///
/// Session 12 refactor (2026-09-04) replaced the previous mixed layout
/// (Convert = paired cards, Organize/Fill & Sign = list rows) with one
/// consistent card component + `LazyVGrid`. Every card uses the same
/// press animation (scale to 0.97 via `PressableCardButtonStyle`) and
/// selection haptic on tap-down, so the whole grid feels like one system.
struct ToolsTabView: View {
    let container: DependencyContainer
    @Environment(DSToastPresenter.self) private var toaster

    // Eager-init all 4 VMs in `init` (via `State(wrappedValue:)`) rather
    // than lazily in `.task`. Reason from Session 10 afternoon bugfix: this
    // view lives inside `RootView.libraryShell`'s ZStack-of-three-tabs
    // mount-all-at-once pattern, and lazy `.task`-based init caused
    // taps on tool cards to push destinations BEFORE VMs were assigned
    // (the destination fell through to a `ProgressView` fallback and
    // never re-rendered). Eager `State(wrappedValue:)` guarantees VMs
    // are non-nil at first push; SwiftUI's `@State` identity semantics
    // discard subsequent init values, so factories run once per view
    // identity.
    @State private var pdfToolsVM: PDFToolsViewModel
    @State private var ocrVM: OCRViewModel
    @State private var signatureVM: SignatureViewModel
    @State private var fillFormVM: FillFormViewModel
    /// Editor sheet target — set by tool child views via `onOpenFile`
    /// callback after a save. Owned here (not `RootView`) because
    /// `EditorPlaceholderView` needs `container` and the sheet scopes
    /// naturally to the tools tab that produced the file.
    @State private var editingRef: DocumentRef?
    /// Gallery sheet payload — set by tool child views' `onShowGallery`
    /// closure for multi-file outputs (Split N>1, PDF→Image, Scan
    /// both formats). Wrapped because `[URL]` isn't `Identifiable` for
    /// `sheet(item:)`.
    @State private var galleryPayload: GalleryPayload?
    /// URL the gallery user tapped, held across the two-sheet handoff.
    /// Gallery calls `dismiss()`, `galleryPayload` clears, THEN
    /// `openPendingEditorIfNeeded` fires from the sheet's `onDismiss`
    /// and safely presents the editor sheet.
    @State private var pendingEditorURL: URL?
    /// Presented from the crown `PremiumButton` in the `titleRow`. Mirror
    /// of the same flag in `LibraryView`.
    @State private var isPaywallPresented = false
    @State private var navPath = NavigationPath()
    @State private var isImageConvertSheetPresented = false
    /// Set when the user taps a file-requiring tool card. Cleared after
    /// navigation in `handleSourcePickerDismiss`.
    @State private var pendingDestination: PDFToolDestination? = nil
    @State private var isSourcePickerPresented = false

    init(container: DependencyContainer) {
        self.container = container
        self._pdfToolsVM = State(wrappedValue: container.makePDFToolsViewModel())
        self._ocrVM = State(wrappedValue: container.makeOCRViewModel())
        self._signatureVM = State(wrappedValue: container.makeSignatureViewModel())
        self._fillFormVM = State(wrappedValue: container.makeFillFormViewModel())
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                // Grouped VStack pattern: header + grid share a tight
                // 8pt gap (belong together visually), then a larger
                // 24pt gap BETWEEN section groups. Restores the
                // grouping cue that a uniform-spacing VStack washed
                // out (all elements equidistant reads as generic AI
                // layout).
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    // Inline large title + premium crown on the trailing
                    // edge — same pattern as `LibraryView.titleRow`, kept
                    // out of the toolbar so the crown escapes iOS 26's
                    // toolbar auto-Liquid-Glass wrap (which forces an
                    // ovoid capsule around the circular badge).
                    titleRow
                        // `lg = 20` matches every other Tools section
                        // (convert grid, organize grid, fill & sign grid
                        // all use lg) — one horizontal rhythm.
                        .padding(.horizontal, DSSpacing.lg)

                    section {
                        sectionHeader("Convert", systemImage: "arrow.left.arrow.right")
                        convertGrid
                    }

                    section {
                        sectionHeader("Organize", systemImage: "doc.on.doc")
                        organizeGrid
                    }

                    section {
                        sectionHeader("Fill & Sign", systemImage: "signature")
                        fillAndSignGrid
                    }

                    // Explicit trailing spacer — a concrete view child
                    // in the layout stack always contributes its full
                    // height. `safeAreaInset`/`contentMargins`/
                    // `.padding(.bottom)` all proved unreliable through
                    // this NavigationStack chain on the iPhone 16e sim;
                    // a spacer view is the only guarantee. Bumped
                    // 60→100 after continued overlap reports (Session
                    // 12) — the last card + its shadow need a
                    // comfortable 90pt gap above the Liquid Glass
                    // pill's translucent top edge.
                    Color.clear
                        .frame(height: DSTabBarMetrics.gridContentTrailingSpacer)
                        .accessibilityHidden(true)
                }
            }
            .autoHidesTabBarOnScroll()
            .background(Color.dsBackgroundSecondary)
            // `.navigationTitle("Tools")` remains for accessibility +
            // parent back-button semantics; the visible title lives in
            // `titleRow` above. `.toolbarVisibility(.hidden)` collapses
            // the empty navbar strip so scroll content starts flush with
            // the safe area.
            .navigationTitle("Tools")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: PDFToolDestination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(item: $editingRef) { ref in
                EditorSheet(container: container, ref: ref)
            }
            .sheet(item: $galleryPayload, onDismiss: openPendingEditorIfNeeded) { payload in
                ToolResultGalleryView(urls: payload.urls) { tappedURL in
                    pendingEditorURL = tappedURL
                }
                .toastHost(toaster)
            }
            // `.fullScreenCover` — see LibraryView paywall present site.
            .fullScreenCover(isPresented: $isPaywallPresented) {
                PaywallView()
            }
            .sheet(isPresented: $isImageConvertSheetPresented) {
                ImageConvertPickerSheet { direction in
                    isImageConvertSheetPresented = false
                    // imageToPDF uses PhotosPicker inside ConvertFlowView —
                    // no source picker needed. pdfToImage shows source picker
                    // the same way as other file-requiring tools.
                    if direction == .imageToPDF {
                        navPath.append(PDFToolDestination.convert(direction))
                    } else {
                        isImageConvertSheetPresented = false
                        pendingDestination = .convert(direction)
                        isSourcePickerPresented = true
                    }
                }
            }
            .sheet(isPresented: $isSourcePickerPresented, onDismiss: handleSourcePickerDismiss) {
                FileSourcePickerSheet(
                    onLibrary: { pendingDestination = withSource(.library) },
                    onBrowse:  { pendingDestination = withSource(.browse)  }
                )
            }
        }
    }

    /// Copies `pendingDestination` with the given source attached, ready to
    /// be set back into `pendingDestination` before dismiss fires.
    private func withSource(_ source: FilePickerSource) -> PDFToolDestination? {
        switch pendingDestination {
        case .merge:              return .merge(source: source)
        case .split:              return .split(source: source)
        case .convert(let dir, _): return .convert(dir, source: source)
        case .fillForm:           return .fillForm(source: source)
        case .sign:               return .sign(source: source)
        default:                  return pendingDestination
        }
    }

    /// Called by SwiftUI after the source-picker sheet fully dismisses.
    /// Navigates to `pendingDestination` only if the user actually selected a
    /// source (Library or Browse). A swipe-dismiss without picking leaves the
    /// source nil — skip navigation and just clear pending state.
    private func handleSourcePickerDismiss() {
        defer { pendingDestination = nil }
        guard let dest = pendingDestination, sourceWasSelected(dest) else { return }
        navPath.append(dest)
    }

    private func sourceWasSelected(_ dest: PDFToolDestination) -> Bool {
        switch dest {
        case .merge(let s), .split(let s), .fillForm(let s), .sign(let s):
            return s != nil
        case .convert(_, let s):
            return s != nil
        default:
            return true
        }
    }

    /// Big page title on the leading edge, premium crown on the trailing
    /// edge — same shape as `LibraryView.titleRow`, so the two home
    /// screens read as the same visual family.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            Text("Tools")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DSSpacing.sm)

            PremiumButton {
                isPaywallPresented = true
            }
        }
        .padding(.top, DSSpacing.sm)
    }

    // MARK: - Callbacks passed to destination views

    /// Builds a `DocumentRef` and presents the editor sheet. Falls back
    /// to `.pdf` for unrecognised extensions — editor tolerates a wrong
    /// hint, scanner corrects on next refresh.
    private func openFile(_ url: URL) {
        editingRef = DocumentRef(
            name: url.lastPathComponent,
            url: url,
            modifiedAt: url.contentModificationDateOrNow,
            kind: DocumentKind.fromUTI(url: url) ?? .pdf
        )
    }

    /// Presents the multi-file gallery sheet.
    private func showGallery(_ urls: [URL]) {
        galleryPayload = GalleryPayload(urls: urls)
    }

    /// Fires from the gallery sheet's `onDismiss` — opens whichever file
    /// the user tapped, now that the gallery is off-screen and it's
    /// safe to present the editor sheet on top.
    private func openPendingEditorIfNeeded() {
        guard let url = pendingEditorURL else { return }
        pendingEditorURL = nil
        openFile(url)
    }

    // MARK: - Grids

    /// Grid columns spec: 2 flexible columns with 12pt inter-column gap.
    /// Same `gridColumns` reused across Convert/Organize/Fill & Sign so
    /// row-height and card widths stay consistent across the whole page.
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: DSSpacing.sm),
            GridItem(.flexible(), spacing: DSSpacing.sm)
        ]
    }

    private var convertGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: DSSpacing.sm) {
            // "To PDF" and "PDF to Word" keep their own cards (distinct
            // workflows). "PDF to Image" and "Image to PDF" are merged
            // into one hub card — user picks direction inside.
            Button {
                pendingDestination = .convert(.officeToPDF)
                isSourcePickerPresented = true
            } label: { ConvertToolCard(direction: .officeToPDF) }
            .buttonStyle(PressableCardButtonStyle())

            Button {
                pendingDestination = .convert(.pdfToWord)
                isSourcePickerPresented = true
            } label: { ConvertToolCard(direction: .pdfToWord) }
            .buttonStyle(PressableCardButtonStyle())

            Button { isImageConvertSheetPresented = true } label: {
                ToolCard(
                    icon: "photo.stack.fill",
                    title: "Image & PDF",
                    subtitle: "PDF to photos, or photos to PDF",
                    tint: .dsDocumentPDF
                )
            }
            .buttonStyle(PressableCardButtonStyle())
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var organizeGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: DSSpacing.sm) {
            Button {
                pendingDestination = .merge()
                isSourcePickerPresented = true
            } label: {
                ToolCard(
                    icon: "doc.on.doc.fill",
                    title: "Merge PDFs",
                    subtitle: "Join multiple PDFs into one file",
                    tint: .dsDocumentPDF
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            Button {
                pendingDestination = .split()
                isSourcePickerPresented = true
            } label: {
                ToolCard(
                    icon: "square.split.2x1",
                    title: "Split PDF",
                    subtitle: "Extract pages or custom ranges",
                    tint: .dsDocumentPDF
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            // Scan & OCR moved off its own hero row into Organize per
            // user request — the section now mirrors Fill & Sign's
            // 3-card layout. The tool itself is still on-device Vision
            // OCR (camera / photos / PDF → editable text).
            NavigationLink(value: PDFToolDestination.scan) {
                ToolCard(
                    icon: "viewfinder",
                    title: "Scan & OCR",
                    subtitle: "Scan to searchable, editable text",
                    tint: .dsBrandPrimary
                )
            }
            .buttonStyle(PressableCardButtonStyle())
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var fillAndSignGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: DSSpacing.sm) {
            Button {
                pendingDestination = .fillForm()
                isSourcePickerPresented = true
            } label: {
                ToolCard(
                    icon: "square.and.pencil",
                    title: "Fill Form",
                    subtitle: "Add text to forms and scans",
                    tint: .dsBrandPrimary
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            Button {
                pendingDestination = .sign()
                isSourcePickerPresented = true
            } label: {
                ToolCard(
                    icon: "signature",
                    title: "Sign",
                    subtitle: "Draw and stamp your signature",
                    tint: .dsDocumentImage
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(value: PDFToolDestination.print) {
                ToolCard(
                    icon: "printer.fill",
                    title: "Print",
                    subtitle: "Print wirelessly via AirPrint",
                    tint: .dsBrandPrimary
                )
            }
            .buttonStyle(PressableCardButtonStyle())
            // LazyVGrid's natural behaviour for 3 items in 2-col grid: the
            // bottom-right cell stays empty. No filler needed — an empty
            // cell reads as "that's all" rather than a broken layout.
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    // MARK: - Section header + grouping

    /// Groups a section header + its grid so they share a tight 8pt
    /// vertical gap (visually "belong together"), while the outer
    /// `VStack(spacing: DSSpacing.xl)` handles the wider 24pt gap
    /// BETWEEN sections. Keeps the layout hierarchy legible without
    /// resorting to explicit backgrounds around sections.
    @ViewBuilder
    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            content()
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            // Small icon in a soft brand-tinted rounded square, matches
            // the tool card icon-badge language on a smaller scale so
            // the section header + its cards read as one motif.
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.dsBrandPrimary.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dsBrandPrimary)
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Destinations

    private func destinationView(for destination: PDFToolDestination) -> some View {
        // Wrapping switch in Group so `.hidesTabBar()` applies uniformly
        // to every destination — every pushed tool view uses the full
        // bottom strip for its own action bar / PDF canvas.
        Group {
            switch destination {
            case .merge(let source):
                MergeView(viewModel: pdfToolsVM, initialSource: source, onOpenFile: openFile)
            case .split(let source):
                SplitView(viewModel: pdfToolsVM, initialSource: source, onOpenFile: openFile, onShowGallery: showGallery)
            case .convert(let direction, let source):
                ConvertFlowView(viewModel: pdfToolsVM, direction: direction, initialSource: source, onOpenFile: openFile, onShowGallery: showGallery)
            case .scan:
                ScanFlowView(viewModel: ocrVM, onOpenFile: openFile, onShowGallery: showGallery)
            case .fillForm(let source):
                FillFormView(viewModel: fillFormVM, initialSource: source, onOpenFile: openFile)
            case .sign(let source):
                SignFlowView(viewModel: signatureVM, initialSource: source, onOpenFile: openFile)
            case .print:
                PrintFlowView(viewModel: pdfToolsVM)
            }
        }
        .hidesTabBar()
    }
}

// MARK: - Card components

/// Standard tool card — single icon badge + title + subtitle. Used by
/// Organize (Merge/Split) and Fill & Sign (Fill Form / Sign / Print).
/// Layout is deliberately mirror-matched to `ConvertToolCard` (same
/// header height, same title/subtitle typography, same padding) so
/// the whole Tools grid reads as one component family — only the
/// header content differs.
private struct ToolCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconBadge(systemImage: icon, tint: tint, size: 34)
            Spacer(minLength: DSSpacing.md)
            Text(title)
                .font(DSFont.callout.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .toolCardSurface()
    }
}

/// Convert-direction card — 2 icon badges + arrow between (Word → PDF,
/// PDF → Image, etc.) The direction indicator IS the primary info for
/// Convert (users pick a direction, not a tool), so it earns a bigger
/// header slot than the single-icon variant.
private struct ConvertToolCard: View {
    let direction: ConvertDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                IconBadge(systemImage: leadingIcon, tint: leadingTint, size: 30)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.dsTextTertiary.opacity(0.7))
                IconBadge(systemImage: trailingIcon, tint: trailingTint, size: 30)
            }
            Spacer(minLength: DSSpacing.md)
            Text(direction.title)
                .font(DSFont.callout.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(DSFont.footnote)
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .toolCardSurface()
    }

    private var leadingIcon: String {
        switch direction {
        // `doc.text.fill` (not `doc.on.doc.fill`) — a single Word-like
        // text doc, matches the `pdfToWord.trailingIcon` used on the
        // opposite Convert card so both directions read "text doc".
        // The earlier `doc.on.doc.fill` collided with the Merge PDFs
        // card's own stacked-docs glyph, which made this "To PDF"
        // card read as "combine multiple docs → PDF" rather than
        // "one Office file → PDF".
        case .officeToPDF: "doc.text.fill"
        case .pdfToWord, .pdfToImage: "doc.fill"
        case .imageToPDF: "photo.fill"
        }
    }
    private var trailingIcon: String {
        switch direction {
        case .officeToPDF, .imageToPDF: "doc.fill"
        case .pdfToWord: "doc.text.fill"
        case .pdfToImage: "photo.fill"
        }
    }
    private var leadingTint: Color {
        switch direction {
        case .officeToPDF: .dsDocumentWord
        case .pdfToWord, .pdfToImage: .dsDocumentPDF
        case .imageToPDF: .dsDocumentImage
        }
    }
    private var trailingTint: Color {
        switch direction {
        case .officeToPDF, .imageToPDF: .dsDocumentPDF
        case .pdfToWord: .dsDocumentWord
        case .pdfToImage: .dsDocumentImage
        }
    }
    private var subtitle: LocalizedStringKey {
        switch direction {
        case .officeToPDF: "From Word, Excel or PowerPoint"
        case .pdfToWord:   "Save as an editable Word file"
        case .pdfToImage:  "Export each page as an image"
        case .imageToPDF:  "Combine photos into one PDF"
        }
    }
}

/// Rounded-square icon badge with a soft top-left gradient wash and a
/// thin light rim along the top edge — reads as slightly dimensional
/// rather than a flat tint chip. `size` keeps the two variants
/// visually calibrated (34 single, 30 paired so a 2-icon row still
/// fits the same header height).
///
/// Deliberately NOT unified with `DSDocumentTypeBadge` in the design
/// system: that one is a flat tint chip keyed to `DocumentKind`, sized
/// fixed for `DSFileRow` (design doc §6.8 — document-type color on file
/// icons/badges). This one is dimensional, keyed to an arbitrary SF
/// Symbol + tint + free-form size, and belongs to the tool-card visual
/// language (matches `ToolCardSurface`'s dimensional treatment). Lifting
/// them under one abstraction would either wash out the flat file-row
/// badge or over-decorate the file rows — kept as two intent-specific
/// components, private to their callers.
private struct IconBadge: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Faint top-only white highlight — mimics a light
                    // source from above, gives the badge a hint of
                    // dimensionality without adding shadow noise.
                    RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.6
                        )
                )
            Image(systemName: systemImage)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Card surface modifier

/// Shared card shell — layered shadow (a tight 1pt drop + a soft
/// 12pt spread) + very-subtle gradient fill + hairline border. Two
/// shadows read as real elevation instead of a flat card; the fill
/// gradient (top brighter, bottom slightly cooler) adds a light-
/// source cue without any solid tinting.
///
/// Applied via ViewModifier so `ToolCard` and `ConvertToolCard` share
/// EXACTLY the same surface — no chance of the two drifting apart on
/// future edits.
private struct ToolCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private let corner: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(DSSpacing.md - 2) // 14pt
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.dsBorderSubtle.opacity(0.6), lineWidth: 0.5)
            )
            // Tight ambient shadow — sharpens the bottom edge, hints at
            // the card sitting on the page.
            .shadow(color: shadowColor.opacity(colorScheme == .dark ? 0.5 : 0.05), radius: 2, x: 0, y: 1)
            // Soft spread shadow — the "lifted" sensation. Kept subtle
            // (0.06 opacity light / 0.4 dark) so the grid doesn't feel
            // heavy when 4 cards stack.
            .shadow(color: shadowColor.opacity(colorScheme == .dark ? 0.4 : 0.06), radius: 14, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var surfaceFill: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.dsBackgroundElevated, Color.dsBackgroundElevated.opacity(0.92)]
                : [Color.dsBackgroundElevated, Color.dsBackgroundElevated.opacity(0.96)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shadowColor: Color {
        // Pure black shadow in light mode reads natural; in dark mode
        // a deeper black is still needed to register at all against
        // the dark background, but we bump the opacity above rather
        // than lightening the color.
        .black
    }
}

private extension View {
    func toolCardSurface() -> some View {
        modifier(ToolCardSurface())
    }
}

/// Custom `ButtonStyle` for every tool card + Scan hero + any tappable
/// grid item. Two effects: a subtle 0.97 scale on press (springs back
/// on release), and a selection haptic fired ONCE at the moment the
/// finger touches down. Together they signal "you tapped this" without
/// waiting for the NavigationStack push animation to make it obvious.
///
/// The haptic uses `.sensoryFeedback(_:trigger:)` with a
/// `(oldValue, newValue) -> Bool?` closure so it fires only on the
/// `false → true` transition — otherwise it would also fire on release
/// (`true → false`), giving a double-tap sensation.
private struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            // Subtle brightness dip on press — reads as the card
            // recessing into the page, complementing the scale.
            // Pure `.brightness(-0.03)` on a light card ≈ 3% darker,
            // barely perceptible individually but adds a lot to the
            // "physical" feel when combined with scale + haptic.
            .brightness(configuration.isPressed ? -0.03 : 0)
            // `~/CLAUDE.md`: "No spring physics for UI chrome" outright,
            // and every animation wrapped in a reduced-motion check —
            // `nil` here means an instant, non-animated state change.
            // 0.15s ease-out matches the cadence used elsewhere for chrome
            // (FAB menu open/close, tab-bar visual toggle in `RootView`).
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, newValue in
                newValue
            }
    }
}

// MARK: - Image & PDF direction picker sheet

/// Compact bottom sheet presented from the "Image & PDF" tool card.
/// User picks a direction here; the sheet dismisses and the parent
/// `NavigationStack` (path-based) pushes directly into `ConvertFlowView`
/// for the chosen direction.
private struct ImageConvertPickerSheet: View {
    let onPick: (ConvertDirection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.md)

            Text("Image & PDF")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.bottom, DSSpacing.md)

            VStack(spacing: DSSpacing.xs) {
                directionRow(
                    icon: "doc.fill",
                    tint: Color.dsDocumentPDF,
                    title: "PDF to Image",
                    subtitle: "Export pages as PNG files",
                    direction: .pdfToImage
                )
                Divider().padding(.leading, 56 + DSSpacing.md * 2)
                directionRow(
                    icon: "photo.fill",
                    tint: Color.dsDocumentImage,
                    title: "Image to PDF",
                    subtitle: "Combine photos into a PDF",
                    direction: .imageToPDF
                )
            }
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .padding(.horizontal, DSSpacing.md)

        }
        .padding(.bottom, DSSpacing.md)
        .presentationDetents([.height(224)])
        .presentationDragIndicator(.hidden)
        .background(Color.dsBackgroundSecondary)
    }

    private func directionRow(icon: String, tint: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey, direction: ConvertDirection) -> some View {
        Button {
            onPick(direction)
        } label: {
            HStack(spacing: DSSpacing.md) {
                IconBadge(systemImage: icon, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DSFont.callout.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(subtitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet payloads + wrappers

/// Wraps a `[URL]` array so `sheet(item:)` can key on it. Identity is
/// a per-presentation UUID, not the URL contents — presenting the same
/// two-file set twice in a row should re-present the sheet, not
/// silently skip because the "item" looks unchanged.
private struct GalleryPayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

#Preview {
    ToolsTabView(container: DependencyContainer())
        .environment(DSToastPresenter())
}
