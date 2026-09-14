import SwiftUI

/// "Templates" gallery — presented full-screen (`LibraryAddButton`'s
/// `.fullScreenCover(isPresented: $isPresentingTemplateGallery)`) when the
/// user picks a document kind from its "Create new" menu, instead of
/// jumping straight to a blank document.
///
/// `Blank Document` always leads the grid and calls `onCreateBlank` — same
/// blank-creation path `LibraryAddButton.handleCreate` already uses. Every
/// other template is mock content (no real template files exist yet), so
/// tapping one shows "Coming soon", mirroring the alert
/// `LibraryAddButton` already shows for unsupported blank kinds.
struct TemplateGalleryView: View {
    @State private var selectedKind: DocumentKind
    @State private var comingSoonTemplate: DocumentTemplate?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onCreateBlank: (DocumentKind) -> Void
    private let onSelectTemplate: (DocumentTemplate) -> Void

    /// `onSelectTemplate` defaults to a no-op — the local "Coming soon"
    /// alert already covers today's behaviour. A real caller can still
    /// observe the tap (e.g. for analytics) without owning the alert.
    init(
        initialKind: DocumentKind,
        onCreateBlank: @escaping (DocumentKind) -> Void,
        onSelectTemplate: @escaping (DocumentTemplate) -> Void = { _ in }
    ) {
        self._selectedKind = State(initialValue: initialKind)
        self.onCreateBlank = onCreateBlank
        self.onSelectTemplate = onSelectTemplate
    }

    private static let availableKinds: [DocumentKind] = [.docx, .xlsx, .pptx]
    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.md),
        GridItem(.flexible(), spacing: DSSpacing.md)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                kindSegmentedControl
                templateGrid
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xl)
        }
        .background(Color.dsBackgroundPrimary.ignoresSafeArea())
        .alert(
            "Coming soon",
            isPresented: Binding(
                get: { comingSoonTemplate != nil },
                set: { if !$0 { comingSoonTemplate = nil } }
            ),
            presenting: comingSoonTemplate
        ) { _ in
            Button("OK", role: .cancel) { comingSoonTemplate = nil }
        } message: { template in
            Text("\"\(template.title)\" isn't ready yet. Start from a blank \(template.kind.displayName) document for now.")
        }
    }

    // MARK: - Header

    /// No close affordance visible in the reference screenshot, but a
    /// full-screen presentation needs one (rule.md #accessibility —
    /// every interactive surface must have a way out without relying on
    /// system swipe-to-dismiss, which `.fullScreenCover` doesn't offer).
    /// No search button — removed per user request; nothing implements it.
    ///
    /// Plain `VStack` (button, then title) rather than overlaying the title
    /// on top of the button row with a fixed top-padding offset — the
    /// overlay version put the title outside normal layout flow, so at
    /// larger Dynamic Type sizes (where `.largeTitle` can grow to 2 lines)
    /// it would have grown downward into `kindSegmentedControl` instead of
    /// pushing it down. It also read to VoiceOver as "Close, Templates
    /// heading" — the button before the heading it belongs under.
    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            Text("Templates")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.bottom, DSSpacing.xs)
    }

    // MARK: - Kind segmented control

    /// Same two-layer treatment as `LibraryView.TypeTabButton` (selected =
    /// solid brand fill + tinted Liquid Glass sheen; unselected = flat
    /// elevated capsule, no glass) — reused rather than invented fresh, so
    /// every pill/chip control in the app reads as one family.
    private var kindSegmentedControl: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(Self.availableKinds, id: \.self) { kind in
                TemplateKindTab(
                    kind: kind,
                    isSelected: selectedKind == kind,
                    reduceMotion: reduceMotion
                ) {
                    selectedKind = kind
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Grid

    private var templateGrid: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.md) {
            BlankTemplateCard(kind: selectedKind) {
                onCreateBlank(selectedKind)
            }
            ForEach(TemplateCatalog.templates(for: selectedKind)) { template in
                TemplateCard(template: template) {
                    comingSoonTemplate = template
                    onSelectTemplate(template)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selectedKind)
    }
}

// MARK: - Kind tab

private struct TemplateKindTab: View {
    let kind: DocumentKind
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(kind.friendlyName)
                .font(DSFont.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? Color.dsTextOnBrand : Color.dsTextPrimary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
        }
        // Same 2-layer surface as `TypeTabButton`: a flat Capsule fill first,
        // then Liquid Glass only on the selected pill. Unselected stays
        // `.identity` (no glass) — glass with nothing behind it to refract
        // reads as an unwanted extra rim on a flat elevated surface.
        .background {
            Capsule().fill(isSelected ? Color.dsBrandPrimary : Color.dsBackgroundElevated)
        }
        .glassEffect(
            isSelected
                ? .regular.tint(Color.dsBrandPrimary).interactive()
                : .identity,
            in: .capsule
        )
        // Unselected pill had no border/shadow, so on a near-white screen
        // background it read as bare floating text instead of a tappable
        // chip. Border + 2-layer shadow are the exact "elevation
        // vocabulary" values `RoundIconButtonSurface`/`ToolCardSurface`
        // already use everywhere else in the app (LibraryView's round icon
        // buttons, ToolsTabView's cards) — reused verbatim, not invented,
        // so this chip reads as the same family of elevated surface.
        .overlay {
            if !isSelected {
                Capsule().stroke(Color.dsBorderSubtle.opacity(0.5), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0 : 0.05), radius: 2, y: 1)
        .shadow(color: .black.opacity(isSelected ? 0 : 0.06), radius: 14, y: 6)
        // Selected pill gets the FAB's own brand-tinted shadow recipe
        // instead — a stronger, colored "lift" appropriate for the one
        // active choice, same values `LibraryAddButton.fabButton` uses.
        .shadow(color: Color.dsBrandPrimary.opacity(isSelected ? 0.28 : 0), radius: 12, y: 6)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected) { _, newValue in newValue }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(kind.displayName) templates")
    }
}

// MARK: - Blank card

private struct BlankTemplateCard: View {
    let kind: DocumentKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .fill(Color.dsDocumentPage)
                    RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                        .strokeBorder(
                            Color.dsBorderSubtle,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .aspectRatio(0.86, contentMode: .fit)

                Text("Blank Document")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel("Create blank \(kind.displayName) document")
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: DocumentTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                TemplateThumbnailView(
                    kind: template.kind,
                    style: template.thumbnail,
                    contentShape: template.contentShape,
                    accentColor: template.accentColor
                )
                .aspectRatio(0.86, contentMode: .fit)

                Text(template.title)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityLabel("\(template.title) template, \(template.kind.displayName)")
    }
}

// MARK: - Thumbnail (placeholder "page preview", no image assets)

private struct TemplateThumbnailView: View {
    let kind: DocumentKind
    let style: DocumentTemplate.ThumbnailStyle
    let contentShape: DocumentTemplate.ContentShape
    let accentColor: Color

    /// Fixed pattern, not `.random(in:)` — a random width recomputed on
    /// every body evaluation would flicker each time the view re-renders.
    private static let lineWidths: [CGFloat] = [0.95, 0.6, 0.85, 0.55, 0.9, 0.7, 0.8]
    private static let shortLineWidths: [CGFloat] = [0.85, 0.55, 0.7]

    var body: some View {
        Group {
            switch kind {
            case .xlsx: spreadsheetLayout
            case .pptx: slideLayout
            default:    documentLayout
            }
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `dsDocumentPage` — the app's existing "this represents a paper
        // page" token, already used for document canvases elsewhere. Stays
        // light in both themes on purpose, same as a real page would.
        .background(Color.dsDocumentPage, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .strokeBorder(Color.dsDocumentPageBorder)
        )
    }

    // MARK: Word — paragraph page (+ 2 genre-specific shapes)

    private var documentLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            if style.hasAccentTitle {
                Capsule().fill(accentColor).frame(width: 46, height: 6)
                Capsule().fill(accentColor.opacity(0.55)).frame(width: 30, height: 5)
                Color.clear.frame(height: 3)
            }
            if style.isFeatured {
                RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.5))
                    )
                    .frame(height: 32)
                    .padding(.bottom, 3)
            }
            switch contentShape {
            case .paragraph:    paragraphLines(Self.lineWidths)
            case .invoiceLines: invoiceLineItems
            case .bulletList:   bulletLines(Self.lineWidths)
            }
            Spacer(minLength: 0)
        }
    }

    /// "Bill to" header (2 short fields) + 3 label/amount rows + one bolder,
    /// accent-colored total row — an invoice's actual structure, not just
    /// paragraph text.
    private var invoiceLineItems: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Capsule().fill(Color.gray.opacity(0.3)).frame(width: 34, height: 4)
                Spacer(minLength: 0)
                Capsule().fill(Color.gray.opacity(0.3)).frame(width: 24, height: 4)
            }
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        Capsule().fill(Color.gray.opacity(0.28)).frame(width: 50, height: 3.5)
                        Spacer(minLength: 0)
                        Capsule().fill(Color.gray.opacity(0.28)).frame(width: 20, height: 3.5)
                    }
                }
            }
            Capsule().fill(accentColor.opacity(0.3)).frame(height: 1)
            HStack {
                Capsule().fill(accentColor).frame(width: 36, height: 5)
                Spacer(minLength: 0)
                Capsule().fill(accentColor).frame(width: 26, height: 5)
            }
        }
    }

    /// Bullet-prefixed short lines instead of full-width paragraph
    /// capsules — reads as notes/action items, not prose.
    private func bulletLines(_ widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(widths, id: \.self) { widthFactor in
                HStack(spacing: 4) {
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: 3.5, height: 3.5)
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 3.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: widthFactor, y: 1, anchor: .leading)
                }
            }
        }
    }

    // MARK: Excel — header row + grid of cells

    /// 3 columns × 5 rows reads as "a spreadsheet" at a glance in a way no
    /// amount of paragraph lines does — `isFeatured` tints one row (like a
    /// totals row) instead of adding an unrelated image-placeholder block,
    /// since that's what actually varies row-to-row on a real sheet.
    private var spreadsheetLayout: some View {
        VStack(spacing: 4) {
            gridRow(fillOpacity: style.hasAccentTitle ? 0.9 : 0.45, cellHeight: 7)
            ForEach(0..<5, id: \.self) { row in
                gridRow(
                    fillOpacity: style.isFeatured && row == 1 ? 0.22 : 0.12,
                    cellHeight: 9
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func gridRow(fillOpacity: Double, cellHeight: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accentColor.opacity(fillOpacity))
                    .frame(height: cellHeight)
            }
        }
    }

    // MARK: PowerPoint — 16:9 slide preview + outline

    private static let chartBarHeights: [CGFloat] = [0.4, 0.8, 0.55, 1.0]

    /// A real 16:9 slide (not a square block) with a title + subtitle text
    /// block bottom-left, drop-shadowed slightly off the page — the actual
    /// giveaway that this is "a presentation" rather than a colored square.
    /// `hasAccentTitle` adds the subtitle line; `isFeatured` swaps the
    /// outline-only look for a small bar-chart placeholder, standing in for
    /// a data/content slide instead of a plain title card.
    private var slideLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white).frame(width: 42, height: 5)
                    if style.hasAccentTitle {
                        Capsule().fill(.white.opacity(0.7)).frame(width: 26, height: 3.5)
                    }
                }
                .padding(8)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

            if style.isFeatured {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Self.chartBarHeights, id: \.self) { heightFactor in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(accentColor.opacity(0.35))
                            .frame(width: 8, height: 16 * heightFactor)
                    }
                }
            }

            paragraphLines(Self.shortLineWidths)
            Spacer(minLength: 0)
        }
    }

    // MARK: Shared

    // `id: \.self` — the checklist bans `\.offset`/`.indices` identity
    // because it silently misattributes state/animations if the backing
    // array ever reorders. Both `lineWidths` arrays are fixed `static let`
    // constants that never reorder, and every value in each is unique, so
    // the value itself is a safe, stable identity.
    private func paragraphLines(_ widths: [CGFloat]) -> some View {
        ForEach(widths, id: \.self) { widthFactor in
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 3.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: widthFactor, y: 1, anchor: .leading)
        }
    }
}

// MARK: - Badge

private struct KindBadge: View {
    let kind: DocumentKind

    var body: some View {
        Text(kind.shortBadgeLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 3)
            .background(kind.badgeColor, in: RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Small shared pieces

/// Same shape as `ToolsTabView`'s private `PressableCardButtonStyle` (scale
/// 0.96 + brightness dip + selection haptic, reduce-motion gated). Kept as
/// its own copy here since this file lives outside the main target for now
/// — worth hoisting to one shared `DesignSystem/Components` file at merge
/// time instead of having two copies.
private struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, newValue in
                newValue
            }
    }
}

/// Apple's own small dismiss-chip sizing (Photos, Quick Look, share sheets):
/// a compact ~30pt circle, not a large 44pt one — a full-size filled circle
/// for a single "close" action read as heavy-handed for the first thing on
/// the screen. The 44×44 outer frame keeps the tap target at the HIG
/// minimum without growing the visible circle.
private struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.dsTextSecondary)
                .frame(width: 30, height: 30)
                .background(Color.dsSurfaceSecondary, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private extension DocumentKind {
    /// Short badge/tab label matching the reference screenshot exactly
    /// ("XLS" / "PPT", not the raw `.xlsx`/`.pptx` uppercased rawValue).
    /// Still used on the small per-card corner badge, where "PowerPoint"
    /// wouldn't fit — see `friendlyName` for the segmented tab label.
    var shortBadgeLabel: String {
        switch self {
        case .xlsx: return "XLS"
        case .pptx: return "PPT"
        default:    return displayName
        }
    }

    /// Segmented-tab label — a regular user reads "DOCX/XLS/PPT" as
    /// unfamiliar file-extension jargon, not as "the Word one". App names
    /// instead, matching `LibraryAddButton.createLabel(for:)`'s own
    /// "Word document" / "Spreadsheet" / "Presentation" framing (just
    /// shorter, since a tab has less room than a menu row).
    var friendlyName: String {
        switch self {
        case .docx: return "Word"
        case .xlsx: return "Excel"
        case .pptx: return "PowerPoint"
        default:    return displayName
        }
    }

    /// One fixed color per kind — every badge/tab for the same kind reads
    /// as the same color, regardless of which template it's tagging. Reuses
    /// the app's existing "document type" tokens (same ones the Library's
    /// own file-kind icons already use) instead of the template's own
    /// `accentColor`, which is meant for that one card's thumbnail variety,
    /// not for a kind-identifying tag.
    var badgeColor: Color {
        switch self {
        case .docx: return .dsDocumentWord
        case .xlsx: return .dsDocumentSpreadsheet
        case .pptx: return .dsDocumentPresentation
        default:    return .dsDocumentGeneric
        }
    }
}

// MARK: - Preview

#Preview("Templates — Dark") {
    TemplateGalleryView(initialKind: .docx, onCreateBlank: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Templates — Light") {
    TemplateGalleryView(initialKind: .docx, onCreateBlank: { _ in })
        .preferredColorScheme(.light)
}
