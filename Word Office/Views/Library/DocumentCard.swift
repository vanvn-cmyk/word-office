import SwiftUI
import UIKit

/// One row in the Library list — type badge · name/status/modified · optional
/// reminder chip · kebab (ellipsis) menu with 3 actions. Stateless leaf;
/// parent wires each action via a callback (`onTap` for row open,
/// `onSaveExport`/`onToggleFavourite`, plus `entry.document.url` for the
/// inline share sheet). "Edit" was dropped from the menu — tapping the
/// row itself already opens the editor, the menu item was redundant.
struct DocumentCard: View {
    let entry: LibraryEntry
    var onTap: (() -> Void)? = nil
    var onSaveExport: (() -> Void)? = nil
    var onToggleFavourite: (() -> Void)? = nil
    var onRename: ((String) async -> Bool)? = nil
    var onConvertToZip: (() -> Void)? = nil
    var onDeleteFile: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                DocumentKindIcon(kind: entry.document.kind)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(entry.document.name)
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                        // Room for the trailing icon column so a long
                        // filename elides before running under the star/
                        // kebab instead of behind them.
                        .padding(.trailing, 30)

                    HStack(spacing: DSSpacing.xs) {
                        StatusPill(status: entry.metadata.status)
                        // `format: .relative(presentation: .named)` renders
                        // once with natural language ("yesterday", "6 days
                        // ago", "now"). Deliberately not `style: .relative`,
                        // which is SwiftUI's live-updating DateStyle that
                        // ticks per second and outputs compound units
                        // ("6 days, 3 hrs") without an "ago" suffix — see
                        // `DSFileRow` for the same rationale.
                        Text(entry.document.modifiedAt, format: .relative(presentation: .named))
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DSSpacing.xs)

                if let remindAt = entry.metadata.remindAt {
                    ReminderChip(date: remindAt)
                }
            }
            .padding(.vertical, DSSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // Star above, kebab below, as an OVERLAY — not an `HStack` sibling
        // (that first attempt made the whole row grow to fit two 44pt
        // touch targets stacked, ~92pt, well past the row's own ~56pt
        // content height: "ai bắt bạn tăng height card"). An overlay lets
        // the row's height stay driven by its own content; the icon
        // column just needs to fit inside whatever that already is.
        // `28pt` icons here (not `DSSize.minimumTouchTarget` = 44) to
        // actually fit — matches the grid tile's own star/kebab sizing,
        // so this isn't a new, arbitrary deviation from the 44pt HIG
        // touch-target guideline, just consistency with the one other
        // place these same two controls already ship smaller.
        .overlay(alignment: .trailing) {
            VStack(spacing: DSSpacing.xxs) {
                favouriteButton

                // Sibling control, not nested inside the row's Button —
                // List gives each top-level control its own independent
                // tap target this way (a Menu nested in another Button's
                // label never receives its own taps).
                FileActionsMenu(
                    shareURL: entry.document.url,
                    onSaveExport: { onSaveExport?() },
                    onRename: { newStem in
                        guard let onRename else { return false }
                        return await onRename(newStem)
                    },
                    onConvertToZip: { onConvertToZip?() },
                    onDelete: { onDeleteFile?() }
                )
            }
        }
    }

    /// Outline star (untinted) when not favourited; filled gold star in a
    /// soft tinted circle when it is — the filled state needs to read as
    /// a persistent status at a glance, not just a pressed-button state.
    private var favouriteButton: some View {
        Button {
            onToggleFavourite?()
        } label: {
            Image(systemName: entry.metadata.isFavourite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.metadata.isFavourite ? Color.dsPremiumGoldEnd : Color.dsTextTertiary)
                // 28pt, not the 44pt `DSSize.minimumTouchTarget` other
                // row buttons use — see `body`'s comment on why (fits a
                // stacked star+kebab column inside the row's own natural
                // height instead of forcing it taller).
                .frame(width: 28, height: 28)
                .background(
                    entry.metadata.isFavourite ? Color.dsPremiumGoldEnd.opacity(0.12) : Color.clear,
                    in: Circle()
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.metadata.isFavourite ? "Remove from Favourites" : "Add to Favourites")
        .sensoryFeedback(.selection, trigger: entry.metadata.isFavourite)
    }

    private var accessibilityLabel: String {
        var parts = [entry.document.name, entry.metadata.status.displayName]
        if entry.metadata.remindAt != nil {
            parts.append("has reminder")
        }
        if entry.metadata.isFavourite {
            parts.append("favourite")
        }
        return parts.joined(separator: ", ")
    }
}

/// Kebab (ellipsis) menu carrying 5 file-row actions — Rename, Save to
/// Device, Convert to ZIP, Share, Toggle Favourite. Extracted from
/// `DocumentCard` so the exact same control can drop into other file-row
/// surfaces later (picker rows in Convert/Merge/Split) without
/// duplicating the menu layout.
///
/// "Edit" is intentionally NOT here — tapping the row itself already
/// opens the editor, a menu duplicate was redundant.
///
/// Actions live in a hand-built bottom sheet inside a `.fullScreenCover`
/// — matches Apple's HIG bottom-sheet vocabulary (Wallet, Files.app,
/// Apple Music queue): flush with the screen bottom, rounded top
/// corners only, `36×5pt` drag indicator centered above the rows, and
/// a subtle black scrim behind. `.sheet` couldn't be used because
/// (a) `.presentationDetents` values don't respond to `@State` updates
/// so we can't auto-fit content, (b) iOS enforces a minimum sheet
/// height above our content, and (c) `.presentationBackground(.clear)`
/// still leaves a system material slab under the card. `.fullScreenCover`
/// gives us total control over what's on-screen. The card slide/fade is
/// a SwiftUI `.transition` driven by a `cardIsPresented` toggle —
/// `.fullScreenCover`'s own present/dismiss doesn't drive inner
/// transitions.
///
/// Rename uses an alert with a `TextField` (iOS-native "small text input"
/// idiom, same as Notes / Files rename). Users edit only the STEM; the
/// original extension is preserved automatically so they can't
/// accidentally break the file. Collisions surface as a toast from the
/// parent (`LibraryView`) and re-open the alert with the typed name
/// preserved so the user can adjust.
///
/// `Share` uses a custom `ActivityView` (`UIActivityViewController`
/// wrapper) rather than `ShareLink` so the actions sheet can dismiss
/// cleanly before the share sheet appears — a `ShareLink` inside the
/// sheet leaves the sheet visible behind the share sheet.
struct FileActionsMenu: View {
    let shareURL: URL
    let onSaveExport: () -> Void
    /// Returns `true` when the rename succeeded (alert dismisses); `false`
    /// on collision or invalid input (alert re-opens with typed name so
    /// the user can retry).
    let onRename: (String) async -> Bool
    let onConvertToZip: () -> Void
    /// Fires only after the user confirms the destructive alert below —
    /// never call this straight from the row tap.
    let onDelete: () -> Void

    @State private var isActionsSheetPresented = false
    /// Toggled inside the full-screen overlay to drive the card's own
    /// slide-up transition — the presentation flag alone couldn't do
    /// that because it enters via SwiftUI's fullScreenCover system
    /// transition (instant fade with our clear background), and we want
    /// the CARD to slide up while the overlay itself just appears.
    @State private var cardIsPresented = false
    /// Two-phase share: tap Share → close actions sheet → present system
    /// share sheet via `ActivityView`. Chained through this flag so both
    /// are one user-perceived action (a `ShareLink` inside the sheet
    /// would leave it visible behind the share sheet — ugly on both idioms).
    @State private var isSharePresented = false
    @State private var isRenameAlertPresented = false
    /// Native destructive `.alert`, not another custom bottom sheet —
    /// deleting a file is a stop-and-confirm moment (CLAUDE.md:
    /// destructive actions always require a confirmation dialog), and
    /// stacking a second custom sheet on top of the one that's mid-
    /// dismiss would be the wrong weight for that. Opened after the
    /// same ~350ms delay pattern as Rename/Share, once the actions
    /// sheet has finished animating away.
    @State private var isDeleteConfirmationPresented = false
    /// Draft filename stem the user is typing in the rename alert.
    /// Prefilled with the current stem when the alert opens; kept across
    /// re-opens on collision so the user can adjust rather than retype.
    @State private var renameStem: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reads the app-scoped toast presenter injected at the scene root
    /// (`Word_OfficeApp.body`). Only used by the Share flow — every
    /// other kebab action toasts from `LibraryView` (the parent that
    /// owns the action-callback closures), so the share sheet is the
    /// one spot that needs its own toaster handle down here in the
    /// menu subview.
    @Environment(DSToastPresenter.self) private var toaster

    var body: some View {
        Button {
            if reduceMotion {
                isActionsSheetPresented = true
            } else {
                withAnimation(.smooth(duration: 0.28)) {
                    isActionsSheetPresented = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActionsSheetPresented ? Color.dsBrandPrimary : Color.dsTextTertiary)
                // 28pt (was 44pt `DSSize.minimumTouchTarget`) — shared by
                // both `DocumentCard` (list) and `DocumentTile` (grid);
                // the list row now stacks this under the favourite star
                // in a fixed-height overlay column, so it needs to match
                // that button's 28pt. Grid's tile has a fixed 152pt
                // height regardless, so this is a no-op change there.
                .frame(width: 28, height: 28)
                .background(
                    isActionsSheetPresented ? Color.dsBrandPrimarySubtle : Color.clear,
                    in: Circle()
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        // Haptic on the SHEET open (a genuine user tap on the ellipsis)
        // rather than on `isFavourite`. The prior `.sensoryFeedback
        // (trigger: isFavourite)` fired for any background reload that
        // flipped the flag — F12 in code review — including debounced
        // scanner refreshes and sync-driven metadata upserts.
        .sensoryFeedback(.selection, trigger: isActionsSheetPresented) { _, new in new }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isActionsSheetPresented)
        // `.fullScreenCover` + clear background — the ONLY way to
        // eliminate the dead space below the card. Every `.sheet` +
        // `.presentationBackground(.clear)` combination still left a
        // visible material blur / dimmed slab below the card, because
        // iOS's sheet chrome renders a system material behind the
        // presentation-background layer that no SwiftUI modifier can
        // remove. `.fullScreenCover` gives us the whole screen with
        // nothing on it except what we draw, so we can render just the
        // card + a tap-catcher scrim above the safe area and there's
        // literally no chrome to leak through.
        .fullScreenCover(isPresented: $isActionsSheetPresented) {
            actionsOverlay
                // iOS 16.4+ removes the cover's own default material fill.
                // Combined with our clear content stack above, the cover
                // is genuinely transparent — Library rows show through.
                .presentationBackground(Color.clear)
        }
        .sheet(isPresented: $isSharePresented) {
            ActivityView(items: [shareURL]) {
                // Only fires when the user actually completes a share
                // (system reports `completed == true`) — cancelling
                // the share sheet leaves this silent, per HIG. Toast
                // is `.success` (green) to match the other
                // "operation completed" toasts across Library rather
                // than `.info` — sharing successfully IS a completed
                // action, even if the app doesn't persist anything
                // itself.
                toaster.show(.success, title: "Your document was shared successfully", filename: shareURL.lastPathComponent)
            }
            .ignoresSafeArea()
        }
        .alert("Rename", isPresented: $isRenameAlertPresented) {
            TextField("Name", text: $renameStem)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") {
                // SwiftUI Alert dismisses on ANY button tap regardless of
                // this closure's return value. An empty/whitespace-only
                // input would close the alert with no toast, no rename,
                // no re-open (code review F4). Send an empty stem to the
                // parent so `.invalidName` reaches the toast + re-open
                // path below, giving the user visible feedback.
                let trimmed = renameStem.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    let ok = await onRename(trimmed)
                    if !ok {
                        // Collision, invalid, or filesystem error: parent
                        // already toasted; re-open the alert with the
                        // typed name preserved so the user can adjust one
                        // letter instead of retyping from scratch. Small
                        // delay lets the alert's own dismiss animation
                        // finish first.
                        try? await Task.sleep(for: .milliseconds(300))
                        renameStem = trimmed
                        isRenameAlertPresented = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            // Full sentence with an explicit subject — the previous
            // "Keeps the .pdf extension." was flagged as reading like a
            // subject-less fragment in English. Says the same thing but
            // as a complete, natural clause.
            let ext = shareURL.pathExtension
            if !ext.isEmpty {
                Text("The file will keep its .\(ext) extension.")
            }
        }
        .alert("Delete “\(shareURL.lastPathComponent)”?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            // Names the actual permanent loss (not just "can't be undone")
            // — reads as a real warning, not boilerplate. No trailing
            // period on short UI copy (house rule).
            Text("This file will be permanently deleted and can't be recovered")
        }
    }

    // MARK: - Cover body

    /// Full-screen overlay hosting a bottom-anchored sheet card. Matches
    /// Apple's HIG bottom-sheet pattern (Wallet / Apple Music "Now
    /// Playing" queue / Files.app share):
    ///   • Sheet flush with the bottom edge — no gap under the last row,
    ///     only rounded TOP corners, flat bottom cut by the screen.
    ///   • Small drag indicator at the top center.
    ///   • Semi-transparent scrim behind so the background dims but is
    ///     still visible for context.
    /// `VStack + Spacer` anchors the sheet — earlier `ZStack(alignment:
    /// .bottom)` produced the "floating mid-screen" position the user
    /// flagged because the ZStack sizing didn't fill the full cover
    /// area on iOS 26.
    private var actionsOverlay: some View {
        ZStack {
            // Scrim — dimmed background, tap dismisses. `black.opacity`
            // matches Apple's own sheet backdrop.
            Color.black.opacity(cardIsPresented ? 0.28 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissMenu() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if cardIsPresented {
                    actionsSheet
                        .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear {
            guard !cardIsPresented else { return }
            if reduceMotion {
                cardIsPresented = true
            } else {
                withAnimation(.smooth(duration: 0.32)) {
                    cardIsPresented = true
                }
            }
        }
    }

    /// The bottom sheet itself — rounded top only, flush bottom, small
    /// drag indicator centered above the actions card. Sheet fill
    /// extends into the safe area so no gap shows below the last row.
    private var actionsSheet: some View {
        VStack(spacing: 0) {
            // Drag indicator — `36×5pt` is the Apple HIG standard size
            // (see UIKit `UISheetPresentationController` reference impl).
            // Fill tint uses the DS `dsTextTertiary` token at 50%
            // opacity so it reads as a subtle handle, not a control.
            Capsule()
                .fill(Color.dsTextTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.sm)
                .accessibilityHidden(true)

            actionsCard
                .padding(.horizontal, DSSpacing.md)
                // sm (12) between the last row and the safe-area edge —
                // safe area itself is filled by the sheet background
                // (ignoresSafeArea) so the sheet reads flush with the
                // screen bottom. Apple sheets use similar tight gap.
                .padding(.bottom, DSSpacing.sm)
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

    /// Two-phase dismiss: animate the card out first, then teardown the
    /// fullScreenCover once the transition has finished. Otherwise the
    /// card would disappear instantly the moment the presentation flag
    /// flips (system fullScreenCover dismiss doesn't drive the inner
    /// `.transition`).
    private func dismissMenu() {
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.24)
        withAnimation(animation) { cardIsPresented = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            isActionsSheetPresented = false
        }
    }

    /// The rows themselves — no card frame around them anymore, because
    /// the parent `actionsSheet` provides the bottom-anchored rounded-
    /// top background (Apple bottom-sheet pattern). Hairline dividers
    /// between rows still indent past the icon column (iOS Settings
    /// convention).
    private var actionsCard: some View {
        VStack(spacing: 0) {
            actionRow(
                title: "Rename",
                systemImage: "pencil"
            ) {
                // Prefill the alert's field with the current stem so the
                // user isn't renaming from a blank slate. Delay presenting
                // the alert until AFTER the sheet's dismiss animation
                // completes — same 350 ms pattern as the Share flow.
                renameStem = shareURL.deletingPathExtension().lastPathComponent
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isRenameAlertPresented = true
                }
            }
            rowDivider
            actionRow(
                title: "Save to Device",
                systemImage: "square.and.arrow.down",
                action: onSaveExport
            )
            rowDivider
            actionRow(
                title: "Convert to ZIP",
                systemImage: "doc.zipper",
                action: onConvertToZip
            )
            rowDivider
            actionRow(
                title: "Share",
                systemImage: "square.and.arrow.up"
            ) {
                // Sheet dismisses after this block runs; wait one dismiss
                // animation (~350 ms) so the share sheet slides up onto
                // a settled screen instead of racing the actions sheet's
                // exit.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isSharePresented = true
                }
            }
            rowDivider
            // Favourite toggle moved out to a standalone icon on the row
            // itself (`DocumentCard.favouriteButton` / the grid tile's
            // equivalent) — this slot is "Delete File" instead, an
            // action that had no home anywhere in the app before.
            // Destructive red (CLAUDE.md: destructive actions get a red
            // fill/outline), and doesn't delete on tap — opens the
            // confirmation `.alert` above; `onDelete` only fires from
            // that alert's "Delete" button.
            actionRow(
                title: "Delete File",
                systemImage: "trash",
                iconColor: Color.dsStatusError,
                titleColor: Color.dsStatusError
            ) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isDeleteConfirmationPresented = true
                }
            }
        }
    }

    /// Hairline separator between rows — indented past the icon column
    /// (leading inset = card horizontal padding + icon container width +
    /// icon-text spacing) so dividers only rule the text area. iOS
    /// Settings / Mail row convention.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.dsBorderSubtle.opacity(0.7))
            .frame(height: 0.5)
            .padding(.leading, DSSpacing.md + 30 + DSSpacing.sm)
    }

    private func actionRow(
        title: String,
        systemImage: String,
        iconColor: Color = Color.dsBrandPrimary,
        titleColor: Color = Color.dsTextPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            // `dismissMenu()` animates the card out first, then tears
            // down the full-screen cover — a raw
            // `isActionsSheetPresented = false` would kill the
            // presentation instantly and skip the slide-down.
            dismissMenu()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                actionRowIcon(systemImage: systemImage, tint: iconColor)
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(titleColor)
                Spacer(minLength: DSSpacing.md)
            }
            .padding(.horizontal, DSSpacing.md)
            // sm (12) vertical — with the 30pt tinted icon container the
            // row is now ~54pt on its own, so less outer padding keeps the
            // grouped card compact.
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionRowButtonStyle())
    }

    /// Tinted rounded-square icon container — iOS Settings row idiom:
    /// SF Symbol sits inside a soft brand-tinted background so the icon
    /// column reads as a coherent visual gutter instead of thin bare
    /// glyphs. `iconColor.opacity(0.12)` gives just enough separation
    /// from the white card without competing with the text.
    private func actionRowIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

/// Subtle brand-tinted press feedback for action rows — `.buttonStyle
/// (.plain)` alone gave no visual on tap, which read as "dead" on such
/// a prominent surface. Fast easeOut so the tint disappears before the
/// sheet finishes dismissing.
private struct ActionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.dsSurfacePressed : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


/// Thin `UIActivityViewController` bridge so the Share row inside our
/// custom popover can present the system share sheet as a proper sheet
/// (a `ShareLink` inside a popover would leave the source popover
/// visible behind the share sheet — awkward on both iPhone and iPad).
///
/// Session 19 (2026-09-09) — `onCompleted` fires only when the user
/// actually completes a share action (`completed == true` in
/// UIActivityViewController's completion handler). Cancel path stays
/// silent per HIG — dismissing the share sheet is user intent, not a
/// completed action worth confirming.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var onCompleted: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            if completed { onCompleted() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sub-components

/// Renders the full-color asset icon (Word / Excel / PowerPoint / PDF) for
/// office document rows; falls back to the SF-Symbol tinted `DSDocumentTypeBadge`
/// for text/markdown/hwp kinds that don't have a dedicated asset yet.
/// Shared by `DocumentCard` (list rows) and `DocumentGrid` (2-col tiles) so
/// both surfaces show the same icon set.
struct DocumentKindIcon: View {
    let kind: DocumentKind

    var body: some View {
        if let assetName = Self.assetName(for: kind) {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
        } else {
            DSDocumentTypeBadge(kind: kind)
        }
    }

    private static func assetName(for kind: DocumentKind) -> String? {
        switch kind {
        case .docx, .doc:  "DocumentIconWord"
        case .xlsx, .xls:  "DocumentIconSpreadsheet"
        case .pptx, .ppt:  "DocumentIconPresentation"
        case .pdf:         "DocumentIconPDF"
        default:           nil
        }
    }
}

private struct StatusPill: View {
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

private struct ReminderChip: View {
    let date: Date

    private var isDue: Bool { date <= Date() }

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: isDue ? "bell.badge.fill" : "bell")
                .font(.system(size: 10, weight: .semibold))
            // `format: .relative(presentation: .named)` — static, not the
            // live-updating `style: .relative` variant. Reminders near the
            // deadline (< 1 min) would otherwise tick per second in the
            // chip. Same rationale as `DSFileRow` + `DocumentCard`'s
            // modified-at text.
            Text(date, format: .relative(presentation: .named))
                .font(DSFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isDue ? Color.dsStatusWarning : Color.dsTextTertiary)
    }
}

// MARK: - Preview

private struct DocumentCardPreview: View {
    var body: some View {
        let now = Date()
        List {
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Quarterly Report.docx",
                    url: URL(fileURLWithPath: "/tmp/Quarterly Report.docx"),
                    modifiedAt: now.addingTimeInterval(-3600),
                    kind: .docx
                ),
                metadata: DocumentMetadata(id: "1", status: .draft, lastOpenedAt: now, lastModifiedAt: now),
                downloadState: .local
            ))
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Contract.pdf",
                    url: URL(fileURLWithPath: "/tmp/Contract.pdf"),
                    modifiedAt: now.addingTimeInterval(-86400),
                    kind: .pdf
                ),
                metadata: DocumentMetadata(
                    id: "2",
                    status: .signed,
                    lastOpenedAt: now,
                    lastModifiedAt: now,
                    remindAt: now.addingTimeInterval(-1800)
                ),
                downloadState: .local
            ))
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Budget.xlsx",
                    url: URL(fileURLWithPath: "/tmp/Budget.xlsx"),
                    modifiedAt: now.addingTimeInterval(-172800),
                    kind: .xlsx
                ),
                metadata: DocumentMetadata(id: "3", status: .sent, lastOpenedAt: now, lastModifiedAt: now),
                downloadState: .local
            ))
        }
        .listStyle(.plain)
    }
}

#Preview {
    DocumentCardPreview()
}
