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
    // than lazily in `.task`. Reason from Session 10 chiều bugfix: this
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

    init(container: DependencyContainer) {
        self.container = container
        self._pdfToolsVM = State(wrappedValue: container.makePDFToolsViewModel())
        self._ocrVM = State(wrappedValue: container.makeOCRViewModel())
        self._signatureVM = State(wrappedValue: container.makeSignatureViewModel())
        self._fillFormVM = State(wrappedValue: container.makeFillFormViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Grouped VStack pattern: header + grid share a tight
                // 8pt gap (belong together visually), then a larger
                // 24pt gap BETWEEN section groups. Restores the
                // grouping cue that a uniform-spacing VStack washed
                // out (all elements equidistant reads as generic AI
                // layout).
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    scanHero

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
            .prominentInlineTitle("Tools")
            .navigationDestination(for: PDFToolDestination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(item: $editingRef) { ref in
                ToolsEditorSheet(container: container, ref: ref)
            }
            .sheet(item: $galleryPayload, onDismiss: openPendingEditorIfNeeded) { payload in
                ToolResultGalleryView(urls: payload.urls) { tappedURL in
                    pendingEditorURL = tappedURL
                }
                .toastHost(toaster)
            }
        }
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

    // MARK: - Scan hero

    private var scanHero: some View {
        NavigationLink(value: PDFToolDestination.scan) {
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.dsBrandPrimary,
                                    Color.dsBrandPrimary.mix(with: .black, by: 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            // Faint top-only rim for a physical light-source cue.
                            RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                    Image(systemName: "viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.dsTextOnBrand)
                }
                .frame(width: 52, height: 52)
                .shadow(color: Color.dsBrandPrimary.opacity(0.35), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.dsStatusSuccess).frame(width: 5, height: 5)
                        Text("Scan & OCR").font(DSFont.headline).foregroundStyle(Color.dsTextPrimary)
                    }
                    Text("On-device — camera, photos, or PDF → editable text")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }

                Spacer(minLength: DSSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(DSSpacing.md)
            .background(
                LinearGradient(
                    colors: [Color.dsBrandPrimarySubtle, Color.dsBackgroundElevated],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                    .strokeBorder(Color.dsBorderSubtle.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(PressableCardButtonStyle())
        .padding(.horizontal, DSSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan and OCR. On-device — camera, photos, or PDF to editable text.")
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
            ForEach(ConvertDirection.allCases, id: \.self) { direction in
                NavigationLink(value: PDFToolDestination.convert(direction)) {
                    ConvertToolCard(direction: direction)
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private var organizeGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: DSSpacing.sm) {
            NavigationLink(value: PDFToolDestination.merge) {
                ToolCard(
                    icon: "doc.on.doc.fill",
                    title: "Merge PDFs",
                    subtitle: "Combine 2 or more files into one",
                    tint: .dsDocumentPDF
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(value: PDFToolDestination.split) {
                ToolCard(
                    icon: "square.split.2x1",
                    title: "Split PDF",
                    subtitle: "Break one file into page ranges",
                    tint: .dsDocumentPDF
                )
            }
            .buttonStyle(PressableCardButtonStyle())
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private var fillAndSignGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: DSSpacing.sm) {
            NavigationLink(value: PDFToolDestination.fillForm) {
                ToolCard(
                    icon: "square.and.pencil",
                    title: "Fill Form",
                    subtitle: "Type text on any PDF — forms or scans",
                    tint: .dsBrandPrimary
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(value: PDFToolDestination.sign) {
                ToolCard(
                    icon: "signature",
                    title: "Sign",
                    subtitle: "Draw your signature, place on PDF",
                    tint: .dsDocumentImage
                )
            }
            .buttonStyle(PressableCardButtonStyle())

            NavigationLink(value: PDFToolDestination.print) {
                ToolCard(
                    icon: "printer.fill",
                    title: "Print",
                    subtitle: "Send to any AirPrint printer nearby",
                    tint: .dsBrandPrimary
                )
            }
            .buttonStyle(PressableCardButtonStyle())
            // LazyVGrid's natural behaviour for 3 items in 2-col grid: the
            // bottom-right cell stays empty. No filler needed — an empty
            // cell reads as "that's all" rather than a broken layout.
        }
        .padding(.horizontal, DSSpacing.md)
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
        .padding(.horizontal, DSSpacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Destinations

    private func destinationView(for destination: PDFToolDestination) -> some View {
        // Wrapping switch in Group so `.hidesTabBar()` applies uniformly
        // to every destination — every pushed tool view uses the full
        // bottom strip for its own action bar / PDF canvas.
        Group {
            switch destination {
            case .merge:
                MergeView(viewModel: pdfToolsVM, onOpenFile: openFile)
            case .split:
                SplitView(viewModel: pdfToolsVM, onOpenFile: openFile, onShowGallery: showGallery)
            case .convert(let direction):
                ConvertFlowView(viewModel: pdfToolsVM, direction: direction, onOpenFile: openFile, onShowGallery: showGallery)
            case .scan:
                ScanFlowView(viewModel: ocrVM, onOpenFile: openFile, onShowGallery: showGallery)
            case .fillForm:
                FillFormView(viewModel: fillFormVM, onOpenFile: openFile)
            case .sign:
                SignFlowView(viewModel: signatureVM, onOpenFile: openFile)
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
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(DSFont.caption)
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
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .toolCardSurface()
    }

    private var leadingIcon: String {
        switch direction {
        case .officeToPDF: "doc.on.doc.fill"
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
        case .officeToPDF: "Word, Excel, PowerPoint"
        case .pdfToWord:   "Text only, no formatting"
        case .pdfToImage:  "Export pages as PNG"
        case .imageToPDF:  "Combine photos"
        }
    }
}

/// Rounded-square icon badge with a soft top-left gradient wash and a
/// thin light rim along the top edge — reads as slightly dimensional
/// rather than a flat tint chip. `size` keeps the two variants
/// visually calibrated (34 single, 30 paired so a 2-icon row still
/// fits the same header height).
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
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, newValue in
                newValue
            }
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

/// Sheet wrapper for the editor — owns its own `dismiss` environment
/// so the Done button closes via `dismiss()` instead of writing to
/// the parent's `editingRef` binding from outside (swiftui-expert-skill
/// convention "sheets own their actions").
///
/// Hosts its own `.toastHost(...)` overlay so the success toast fired
/// by tool save right before this sheet appears stays visible — the
/// scene-root overlay in `Word_OfficeApp` sits BELOW every SwiftUI
/// sheet in z-order and would otherwise be hidden.
private struct ToolsEditorSheet: View {
    let container: DependencyContainer
    let ref: DocumentRef
    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    var body: some View {
        NavigationStack {
            EditorPlaceholderView(container: container, ref: ref)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .toastHost(toaster)
    }
}

#Preview {
    ToolsTabView(container: DependencyContainer())
        .environment(DSToastPresenter())
}
