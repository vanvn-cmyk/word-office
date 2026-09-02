import SwiftUI

/// 2-column grid renderer for one section's entries — same data pipeline as
/// `DocumentCard`'s list rows (Library-Home-v10 mockup Frame 4: grid is an
/// alternate item renderer, not a separate screen). Used inside `LibraryView`
/// when `viewMode == .grid`.
struct DocumentGrid: View {
    let entries: [LibraryEntry]
    var onTap: (LibraryEntry) -> Void
    var onToggleFavourite: (LibraryEntry) -> Void

    private let columns = [GridItem(.flexible(), spacing: DSSpacing.sm), GridItem(.flexible(), spacing: DSSpacing.sm)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
            ForEach(entries) { entry in
                DocumentTile(entry: entry) {
                    onTap(entry)
                } onToggleFavourite: {
                    onToggleFavourite(entry)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
    }
}

private struct DocumentTile: View {
    let entry: LibraryEntry
    var onTap: () -> Void
    var onToggleFavourite: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSDocumentTypeBadge(kind: entry.document.kind)
                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

                Text(entry.document.name)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                StatusPillTag(status: entry.metadata.status)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous).strokeBorder(Color.dsBorderSubtle))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            FavouriteToggleButton(isFavourite: entry.metadata.isFavourite, action: onToggleFavourite)
                .scaleEffect(0.8)
        }
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
