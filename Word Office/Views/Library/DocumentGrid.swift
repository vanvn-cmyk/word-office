import SwiftUI

/// 2-column grid renderer for one section's entries — same data pipeline as
/// `DocumentCard`'s list rows (Library-Home-v10 mockup Frame 4: grid is an
/// alternate item renderer, not a separate screen). Used inside `LibraryView`
/// when `viewMode == .grid`.
struct DocumentGrid: View {
    let entries: [LibraryEntry]
    var onTap: (LibraryEntry) -> Void
    var onSaveExport: (LibraryEntry) -> Void
    var onToggleFavourite: (LibraryEntry) -> Void
    var onRename: (LibraryEntry, String) async -> Bool
    var onConvertToZip: (LibraryEntry) -> Void
    var onDeleteFile: (LibraryEntry) -> Void

    // `xs = 8` outer padding + `xs = 8` column spacing widen each tile
    // vs. the previous `sm = 12` — user asked for wider grid cards.
    // Compact but not edge-to-edge so shadows don't collide with the
    // list's own insetGrouped gutter.
    private let columns = [GridItem(.flexible(), spacing: DSSpacing.xs), GridItem(.flexible(), spacing: DSSpacing.xs)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
            ForEach(entries) { entry in
                DocumentTile(
                    entry: entry,
                    onTap: { onTap(entry) },
                    onSaveExport: { onSaveExport(entry) },
                    onToggleFavourite: { onToggleFavourite(entry) },
                    onRename: { newStem in await onRename(entry, newStem) },
                    onConvertToZip: { onConvertToZip(entry) },
                    onDeleteFile: { onDeleteFile(entry) }
                )
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.bottom, DSSpacing.sm)
    }
}

private struct DocumentTile: View {
    let entry: LibraryEntry
    var onTap: () -> Void
    var onSaveExport: () -> Void
    var onToggleFavourite: () -> Void
    var onRename: (String) async -> Bool
    var onConvertToZip: () -> Void
    var onDeleteFile: () -> Void

    /// Fixed tile height so a rename that changes the filename from
    /// 2 lines to 1 line (or the reverse) doesn't reflow the whole grid.
    /// Tight budget (icon 44 + xs 8 + 2-line subheadline ~40 + xs 8 +
    /// pill ~24 + sm 12 × 2 = 148pt) plus ~4pt breathing. Trimmed from
    /// 176 per user request.
    private static let tileHeight: CGFloat = 152

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DocumentKindIcon(kind: entry.document.kind)
                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

                Text(entry.document.name)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                StatusPillTag(status: entry.metadata.status)

                // Push everything to the top so a short (single-line)
                // filename leaves the extra room BELOW the pill rather
                // than centring content vertically — reads more like a
                // stable card layout with the pill anchored just under
                // the name.
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight, alignment: .topLeading)
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous).strokeBorder(Color.dsBorderSubtle))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            // Kebab stays bottom-right (shares the row with the status
            // pill on the leading edge — see the history above); the
            // favourite star (added back below) takes the now-free
            // top-right corner instead of competing for this spot.
            FileActionsMenu(
                shareURL: entry.document.url,
                onSaveExport: onSaveExport,
                onRename: onRename,
                onConvertToZip: onConvertToZip,
                onDelete: onDeleteFile
            )
            .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            favouriteButton
                .padding(4)
        }
    }

    /// Same visual language as `DocumentCard.favouriteButton` (list rows)
    /// — outline star untinted, filled gold star in a soft tinted circle
    /// once favourited, so the state reads the same across both view
    /// modes ("áp dụng cho cả view ngang và dọc").
    private var favouriteButton: some View {
        Button(action: onToggleFavourite) {
            Image(systemName: entry.metadata.isFavourite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.metadata.isFavourite ? Color.dsPremiumGoldEnd : Color.dsTextTertiary)
                .frame(width: 28, height: 28)
                .background(
                    entry.metadata.isFavourite ? Color.dsPremiumGoldEnd.opacity(0.12) : Color.dsBackgroundElevated,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.metadata.isFavourite ? "Remove from Favourites" : "Add to Favourites")
        .sensoryFeedback(.selection, trigger: entry.metadata.isFavourite)
    }
}

/// `StatusPill` in `DocumentCard.swift` is `private` — same visual, kept as its
/// own small type here rather than widening that file's access just for reuse.
private struct StatusPillTag: View {
    let status: DocumentStatus

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.displayName)
                .font(DSFont.caption)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 2)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .draft:    Color.dsStatusWarning
        case .reviewed: Color.dsTextSecondary
        case .signed:   Color.dsStatusSuccess
        case .sent:     Color.dsBrandPrimary
        }
    }

    private var background: Color {
        switch status {
        case .draft:    Color.dsStatusWarningBackground
        case .reviewed: Color.dsSurfaceSecondary
        case .signed:   Color.dsStatusSuccessBackground
        case .sent:     Color.dsBrandPrimarySubtle
        }
    }
}
