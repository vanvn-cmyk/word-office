import SwiftUI

/// Two-row tabbed toolbar for Excel/Word; single row for PPT/PDF.
/// Row 1 (44 pt): tab labels + ≡ format button pinned right.
/// Row 2 (44 pt): scrollable action buttons for the active tab.
///                Color-picker buttons are PINNED outside the ScrollView
///                so they are never blocked by scroll gesture recognisers.
struct EditorTopToolbar: View {

    // MARK: - File kind

    enum FileKind {
        case word, excel, ppt, pdf, unknown
        init(ext: String) {
            switch ext.lowercased() {
            case "doc", "docx", "odt", "rtf": self = .word
            case "xls", "xlsx", "ods", "csv": self = .excel
            case "ppt", "pptx", "odp":        self = .ppt
            case "pdf":                        self = .pdf
            default:                           self = .unknown
            }
        }
    }

    // MARK: - Tab enums

    private enum ExcelTab: String, CaseIterable {
        case home   = "Home"
        case number = "Number"
        case align  = "Align"
        case data   = "Data"
    }

    private enum WordTab: String, CaseIterable {
        case home      = "Home"
        case paragraph = "Paragraph"
    }

    // MARK: - Inputs & state

    let kind: FileKind
    let onCommand: (String) -> Void
    let onFormat: () -> Void

    @State private var excelTab: ExcelTab = .home
    @State private var wordTab:  WordTab  = .home
    @State private var fontColor: Color   = .black
    @State private var fillColor: Color   = Color(white: 0.9)
    @State private var wordFontColor: Color = .black

    // MARK: - Body

    var body: some View {
        switch kind {
        case .excel:
            VStack(spacing: 0) {
                tabBar(tabs: ExcelTab.allCases, selected: $excelTab)
                excelContentRow
                    .animation(.easeInOut(duration: 0.12), value: excelTab)
            }
        case .word:
            VStack(spacing: 0) {
                tabBar(tabs: WordTab.allCases, selected: $wordTab)
                wordContentRow
                    .animation(.easeInOut(duration: 0.12), value: wordTab)
            }
        default:
            singleRow
        }
    }

    // MARK: - Tab bar (row 1)

    private func tabBar<T: RawRepresentable & Hashable>(
        tabs: [T],
        selected: Binding<T>
    ) -> some View where T.RawValue == String {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selected.wrappedValue = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.system(
                                size: 12,
                                weight: selected.wrappedValue == tab ? .semibold : .regular
                            ))
                            .foregroundStyle(
                                selected.wrappedValue == tab ? Color.primary : Color.secondary
                            )
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 40)
                        Rectangle()
                            .fill(selected.wrappedValue == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            vDivider()
            formatButton
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Excel content row (row 2)

    /// Excel Home pins color pickers OUTSIDE the ScrollView to avoid gesture conflict.
    private var excelContentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    switch excelTab {
                    case .home:
                        iconBtn("arrow.uturn.backward", label: "Undo",      cmd: "undo")
                        iconBtn("arrow.uturn.forward",  label: "Redo",      cmd: "redo")
                        vDivider()
                        iconBtn("bold",      label: "Bold",      cmd: "bold")
                        iconBtn("italic",    label: "Italic",    cmd: "italic")
                        iconBtn("underline", label: "Underline", cmd: "underline")
                        vDivider()
                        textBtn("Σ", label: "AutoSum", cmd: "auto-sum")

                    case .number:
                        textBtn("$",   label: "Currency",       cmd: "number-currency")
                        textBtn(",",   label: "Thousands",      cmd: "number-comma")
                        textBtn("%",   label: "Percent",        cmd: "number-percent")
                        vDivider()
                        textBtn(".0↑", label: "More decimal",   cmd: "number-decimal-inc")
                        textBtn(".0↓", label: "Less decimal",   cmd: "number-decimal-dec")
                        vDivider()
                        chipBtn("Date", label: "Date format",   cmd: "number-date")
                        chipBtn("Time", label: "Time format",   cmd: "number-time")
                        chipBtn("Text", label: "Text format",   cmd: "number-text")

                    case .align:
                        iconBtn("text.alignleft",        label: "Left",    cmd: "cell-align-left")
                        iconBtn("text.aligncenter",      label: "Center",  cmd: "cell-align-center")
                        iconBtn("text.alignright",       label: "Right",   cmd: "cell-align-right")
                        vDivider()
                        iconBtn("align.vertical.top",    label: "Top",     cmd: "cell-valign-top")
                        iconBtn("align.vertical.center", label: "Middle",  cmd: "cell-valign-middle")
                        iconBtn("align.vertical.bottom", label: "Bottom",  cmd: "cell-valign-bottom")
                        vDivider()
                        iconBtn("arrow.down.left",       label: "Wrap",    cmd: "wrap-text")
                        vDivider()
                        textBtn("⊞", label: "Merge cells",   cmd: "merge-center")
                        textBtn("⊟", label: "Unmerge cells", cmd: "merge-unmerge")

                    case .data:
                        chipBtn("A→Z", label: "Sort A to Z",   cmd: "sort-asc")
                        chipBtn("Z→A", label: "Sort Z to A",   cmd: "sort-desc")
                        vDivider()
                        iconBtn("line.3.horizontal.decrease.circle",
                                label: "Filter",               cmd: "filter-toggle")
                        vDivider()
                        iconBtn("magnifyingglass", label: "Find", cmd: "find")
                    }
                }
                .padding(.horizontal, 4)
            }

            // ── Color pickers pinned here for Home tab only ──────────────────
            // Outside the ScrollView: ColorPicker gesture is never blocked.
            if excelTab == .home {
                vDivider()
                nativeColorBtn(icon: "character",   label: "Font color",
                               color: $fontColor, cmd: "font-color")
                nativeColorBtn(icon: "paintbucket", label: "Fill color",
                               color: $fillColor, cmd: "fill-color")
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Word content row (row 2)

    private var wordContentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    switch wordTab {
                    case .home:
                        iconBtn("arrow.uturn.backward", label: "Undo",      cmd: "undo")
                        iconBtn("arrow.uturn.forward",  label: "Redo",      cmd: "redo")
                        vDivider()
                        iconBtn("bold",      label: "Bold",      cmd: "bold")
                        iconBtn("italic",    label: "Italic",    cmd: "italic")
                        iconBtn("underline", label: "Underline", cmd: "underline")

                    case .paragraph:
                        iconBtn("text.alignleft",    label: "Left",    cmd: "align-left")
                        iconBtn("text.aligncenter",  label: "Center",  cmd: "align-center")
                        iconBtn("text.alignright",   label: "Right",   cmd: "align-right")
                        iconBtn("text.alignjustify", label: "Justify", cmd: "align-justify")
                        vDivider()
                        iconBtn("list.bullet", label: "Bullet list",   cmd: "list-bullet")
                        iconBtn("list.number", label: "Numbered list", cmd: "list-numbered")
                    }
                }
                .padding(.horizontal, 4)
            }

            if wordTab == .home {
                vDivider()
                nativeColorBtn(icon: "character", label: "Font color",
                               color: $wordFontColor, cmd: "font-color")
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Single row (PPT / PDF / unknown)

    private var singleRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    iconBtn("arrow.uturn.backward", label: "Undo", cmd: "undo")
                    iconBtn("arrow.uturn.forward",  label: "Redo", cmd: "redo")
                    vDivider()
                    iconBtn("bold",      label: "Bold",      cmd: "bold")
                    iconBtn("italic",    label: "Italic",    cmd: "italic")
                    iconBtn("underline", label: "Underline", cmd: "underline")
                    if kind == .ppt {
                        vDivider()
                        iconBtn("text.aligncenter", label: "Center", cmd: "align-center")
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Shared format button

    private var formatButton: some View {
        Button(action: onFormat) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Format panel")
    }

    // MARK: - Native color picker (must be OUTSIDE ScrollView)

    private func nativeColorBtn(
        icon: String,
        label: String,
        color: Binding<Color>,
        cmd: String
    ) -> some View {
        ZStack {
            ColorPicker(label, selection: color, supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)          // > 0.01 threshold so UIKit allows hit-testing
                .frame(width: 40, height: 44)
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Rectangle()
                    .fill(color.wrappedValue)
                    .frame(width: 18, height: 3)
                    .cornerRadius(1.5)
            }
            .frame(width: 40, height: 44)
            .allowsHitTesting(false)
        }
        .frame(width: 40, height: 44)
        .accessibilityLabel(label)
        .onChange(of: color.wrappedValue) { _, newColor in
            onCommand("\(cmd):\(newColor.hexRGB)")
        }
    }

    // MARK: - Primitive components

    private func iconBtn(_ icon: String, label: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    /// Plain monospaced text button ($ % Σ ⊞ ⊟ .0↑ .0↓)
    private func textBtn(_ text: String, label: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 36, idealWidth: 44, maxWidth: 52, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    /// Chip-style button with subtle pill background — used for Date/Time/Text, A→Z/Z→A.
    /// Makes it visually clear these are interactive, not plain labels.
    private func chipBtn(_ text: String, label: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 7))
                .frame(minHeight: 44)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func vDivider() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 0.5, height: 22)
            .padding(.horizontal, 4)
    }
}

// MARK: - Color → #RRGGBB

private extension Color {
    var hexRGB: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
