import SwiftUI

/// Bottom-anchored toast card — success/error/info icon on the leading edge,
/// a title and optional filename subtitle stacked to the right. Rendered by
/// `Word_OfficeApp`'s top overlay when `DSToastPresenter.current` is set.
///
/// Icon design: solid full-color SF Symbol at 22pt, tinted with the semantic
/// status color — same Apple system-banner / Files-app "Copied" pattern users
/// recognise from iOS. Deliberately NOT wrapped in a tinted rounded-rect
/// badge (the `DSDocumentTypeBadge` / `SettingsRowIcon` recipe) because that
/// convention is reserved for PERSISTENT chrome (settings rows, document
/// type stamps, tool cards). Toasts are transient system messages — the
/// familiar iOS toast icon idiom reads faster and doesn't dilute the
/// badge language.
///
/// Layout: `HStack(alignment: .top, …)` so the icon anchors to the title's
/// first line rather than centering across the whole card. Matters when
/// `title` wraps to 2 lines (allowed since Session 19's polite-copy pass)
/// alongside a filename subtitle — a centered icon would drift down into
/// the filename row and look mis-aligned; the top anchor keeps it visually
/// paired with the primary message.
///
/// Filename truncates in the middle (`.middle` truncation) — for a long
/// path like `"Q4 report (final draft, v3 revised).docx"` the extension
/// stays visible ("…revised).docx"), which is more identifying than a
/// trailing truncation that keeps the leading "Q4 report (final…" and
/// hides the type.
struct DSToast: View {
    let item: DSToastPresenter.Item
    let onTap: () -> Void

    var body: some View {
        // `Button` (not `.onTapGesture`) so VoiceOver focus, press-highlight,
        // and the `.isButton` trait come for free — the skill's core
        // accessibility principle. `.buttonStyle(.plain)` prevents the
        // system's default filled-blue chrome so the capsule background
        // shows through unchanged.
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(2)
                    if let filename = item.filename {
                        Text(filename)
                            .font(DSFont.caption)
                            .foregroundStyle(Color.dsTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: DSSpacing.xs)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.dsBorderSubtle))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
            // `.contentShape` on Capsule so the tap target follows the visible
            // pill shape, not the bounding rect — same reason `.background(_:in:)`
            // uses Capsule as the fill shape.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to dismiss")
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.style {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.dsStatusSuccess)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.dsStatusError)
        case .info:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
        }
    }
}

// MARK: - Toast host modifier

/// Adds a top-anchored toast overlay bound to the given `DSToastPresenter`.
/// Apply once at the scene root (`Word_OfficeApp`) AND once inside every
/// sheet that could otherwise cover the scene-root overlay — sheets are
/// presented above their presenter's overlays in SwiftUI, so a toast fired
/// while a sheet is up is invisible to the user unless the sheet also
/// hosts its own toast overlay. Applies to `EditorSheet` (auto-opened
/// after Convert/Merge/Split/Scan success from either Library or Tools tab)
/// and to `LibraryAddButton`'s FAB scan sheet.
///
/// Explicit `presenter` param (not `@Environment`) because the modifier's
/// enclosing view isn't always inside the `.environment(_:)` chain — the
/// scene-root call sits above the injection site — so passing the shared
/// instance directly is the unambiguous option.
extension View {
    func toastHost(_ presenter: DSToastPresenter) -> some View {
        modifier(ToastHostModifier(presenter: presenter))
    }
}

private struct ToastHostModifier: ViewModifier {
    let presenter: DSToastPresenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let item = presenter.current {
                DSToast(item: item) { presenter.dismiss() }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(item.id)
            }
        }
    }
}

#Preview("Success — no filename") {
    DSToast(
        item: .init(title: "Saved", filename: nil, style: .success),
        onTap: {}
    )
    .padding()
}

#Preview("Success — with filename") {
    DSToast(
        item: .init(title: "Converted", filename: "Q4 Report.docx", style: .success),
        onTap: {}
    )
    .padding()
}

#Preview("Error") {
    DSToast(
        item: .init(title: "Conversion failed", filename: nil, style: .error),
        onTap: {}
    )
    .padding()
}
