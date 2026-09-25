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
    var onMarkDone: (LibraryEntry) -> Void
    var onDeleteFile: (LibraryEntry) -> Void
    var onChangeStatus: (LibraryEntry, DocumentStatus) -> Void = { _, _ in }
    var leadingPadding: CGFloat = DSSpacing.xxl
    /// Called with the first tile's frame (in the `libraryTipSpace` coordinate
    /// space) for coachmark anchoring — nil means this grid skips tip tracking.
    var onFirstCardFrame: ((CGRect) -> Void)? = nil

    private let columns = [GridItem(.flexible(), spacing: DSSpacing.sm), GridItem(.flexible(), spacing: DSSpacing.sm)]

    // Long-press target — set by a tile's onLongPress, cleared when the
    // sheet dismisses. Kept at DocumentGrid level so the fullScreenCover
    // attaches to the LazyVGrid container rather than to individual tiles
    // (a context menu on tiles inside a LazyVGrid inside a List row
    // causes iOS to highlight the whole row — kept as comment so this
    // choice is never re-debated).
    @State private var statusPickerEntry: LibraryEntry?

    var body: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.md) {
            ForEach(entries) { entry in
                let isFirst = entry.id == entries.first?.id
                DocumentTile(
                    entry: entry,
                    onTap: { onTap(entry) },
                    onSaveExport: { onSaveExport(entry) },
                    onToggleFavourite: { onToggleFavourite(entry) },
                    onRename: { newStem in await onRename(entry, newStem) },
                    onConvertToZip: { onConvertToZip(entry) },
                    onMarkDone: { onMarkDone(entry) },
                    onDeleteFile: { onDeleteFile(entry) },
                    onLongPress: {
                        UIView.setAnimationsEnabled(false)
                        statusPickerEntry = entry
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            UIView.setAnimationsEnabled(true)
                        }
                    }
                )
                .onGeometryChange(for: CGRect.self) { geo in
                    geo.frame(in: .named("libraryTipSpace"))
                } action: { frame in
                    if isFirst { onFirstCardFrame?(frame) }
                }
            }
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, DSSpacing.xs)
        .padding(.bottom, DSSpacing.sm)
        .fullScreenCover(isPresented: Binding(
            get: { statusPickerEntry != nil },
            set: { if !$0 { statusPickerEntry = nil } }
        )) {
            if let entry = statusPickerEntry {
                StatusPickerSheet(
                    entry: entry,
                    onSelect: { status in onChangeStatus(entry, status) },
                    onDismiss: { statusPickerEntry = nil }
                )
                .presentationBackground(Color.clear)
            }
        }
    }
}

// MARK: - Status picker sheet

/// Bottom sheet for changing a document's status from the grid tile long-press.
/// Mirrors the FileActionsMenu pattern: fullScreenCover + scrim + slide-up card
/// + drag pill. Icon rows match the list view's context menu visual language.
private struct StatusPickerSheet: View {
    let entry: LibraryEntry
    var onSelect: (DocumentStatus) -> Void
    var onDismiss: () -> Void

    @State private var cardIsPresented = false
    /// Starts at 0.28 immediately so the scrim covers UIKit's presenter
    /// background from frame 0. Only animated to 0 on dismiss.
    @State private var scrimOpacity: Double = 0.28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if cardIsPresented {
                    sheetCard.transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear {
            guard !cardIsPresented else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                cardIsPresented = true
            }
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            cardIsPresented = false
            scrimOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            UIView.setAnimationsEnabled(false)
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                UIView.setAnimationsEnabled(true)
            }
        }
    }

    private var sheetCard: some View {
        VStack(spacing: 0) {
            // Drag pill — HIG standard 36×5pt
            Capsule()
                .fill(Color.dsTextTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.sm)
                .accessibilityHidden(true)

            // Document identity header
            HStack(spacing: DSSpacing.sm) {
                DocumentKindIcon(kind: entry.document.kind)
                    .frame(width: 28, height: 28)
                Text(entry.document.name)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.sm)

            Rectangle()
                .fill(Color.dsBorderSubtle.opacity(0.7))
                .frame(height: 0.5)
                .padding(.horizontal, DSSpacing.md)

            // Section label
            Text("Change status")
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)

            // Status rows
            VStack(spacing: 0) {
                ForEach(DocumentStatus.userSelectableCases) { status in
                    statusRow(status)
                    if status != DocumentStatus.userSelectableCases.last {
                        Rectangle()
                            .fill(Color.dsBorderSubtle.opacity(0.7))
                            .frame(height: 0.5)
                            .padding(.leading, 30 + DSSpacing.sm)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.md)
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: DSRadius.large,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DSRadius.large,
                style: .continuous
            )
            .fill(Color.dsBackgroundPrimary)
            .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(0.14), radius: 24, y: -4)
    }

    private func statusRow(_ status: DocumentStatus) -> some View {
        let isCurrent = status == entry.metadata.status
        return Button {
            onSelect(status)
            dismiss()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.dsTextTertiary : status.tintColor)
                    .frame(width: 30, height: 30)
                    .background(
                        isCurrent ? Color.dsSurfaceSecondary : status.tintColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(status.displayName)
                    .font(DSFont.body)
                    .foregroundStyle(isCurrent ? Color.dsTextTertiary : Color.dsTextPrimary)

                Spacer(minLength: DSSpacing.md)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.dsTextTertiary)
                }
            }
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(StatusRowButtonStyle())
        .disabled(isCurrent)
    }
}

// MARK: - DocumentTile

private struct DocumentTile: View {
    let entry: LibraryEntry
    var onTap: () -> Void
    var onSaveExport: () -> Void
    var onToggleFavourite: () -> Void
    var onRename: (String) async -> Bool
    var onConvertToZip: () -> Void
    var onMarkDone: () -> Void
    var onDeleteFile: () -> Void
    /// Fires on long-press; parent (DocumentGrid) owns the status picker UI.
    var onLongPress: () -> Void = {}

    private static let tileHeight: CGFloat = 152
    /// Set to true by the long-press recognizer before it calls onLongPress(),
    /// so the Button's touch-up (which fires after the long-press threshold)
    /// can suppress the onTap() call that would otherwise also fire.
    @State private var suppressNextTap = false

    var body: some View {
        Button {
            if suppressNextTap { suppressNextTap = false; return }
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DocumentKindIcon(kind: entry.document.kind)
                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

                Text(entry.document.name)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: Self.tileHeight, alignment: .topLeading)
            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous).strokeBorder(Color.dsBorderSubtle.opacity(0.6), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        // `highPriorityGesture` gives the long-press recognizer precedence
        // over the Button's tap so iOS cancels the tap when the threshold
        // is reached. `suppressNextTap` is a belt-and-suspenders fallback
        // in case Button's UIControl still fires on touch-up.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                suppressNextTap = true
                onLongPress()
            }
        )
        .overlay(alignment: .bottomTrailing) {
            FileActionsMenu(
                shareURL: entry.document.url,
                onSaveExport: onSaveExport,
                onRename: onRename,
                onConvertToZip: onConvertToZip,
                currentStatus: entry.metadata.status,
                onMarkDone: onMarkDone,
                onDelete: onDeleteFile
            )
            .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            favouriteButton
                .padding(4)
        }
    }

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

// MARK: - Button style

private struct StatusRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.dsSurfacePressed : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
