import SwiftUI

/// Two-row tabbed toolbar for Excel/Word; single row for PPT/PDF.
/// Row 1 (44 pt): tab labels + ≡ format button pinned right.
/// Row 2 (44 pt): scrollable action buttons for the active tab.
///                Color-picker buttons are PINNED outside the ScrollView.
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
        case insert = "Insert"
    }

    private enum WordTab: String, CaseIterable {
        case home      = "Home"
        case paragraph = "Paragraph"
        case insert    = "Insert"
    }

    // MARK: - Inputs & state

    let kind: FileKind
    let onCommand: (String) -> Void

    @State private var excelTab: ExcelTab = .home
    @State private var wordTab:  WordTab  = .home
    @State private var fontColor:     Color = .black
    @State private var fillColor:     Color = Color(red: 1.0, green: 0.92, blue: 0.23)
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
            // Undo / Redo pinned at leading edge — always visible regardless of active tab.
            undoRedoCluster
            vDivider()

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
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var undoRedoCluster: some View {
        HStack(spacing: 0) {
            Button { onCommand("undo") } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Undo")

            Button { onCommand("redo") } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Redo")
        }
    }

    // MARK: - Excel content row (row 2)

    /// Color pickers are PINNED outside the ScrollView so the scroll's pan gesture
    /// cannot intercept their taps.
    private var excelContentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {

                    switch excelTab {
                    case .home:
                        iconBtn("bold",           label: "Bold",          cmd: "bold")
                        iconBtn("italic",         label: "Italic",        cmd: "italic")
                        iconBtn("underline",      label: "Underline",     cmd: "underline")
                        iconBtn("strikethrough",  label: "Strikethrough", cmd: "strikeout")
                        vDivider()
                        textBtn("A+", label: "Increase font size", cmd: "font-size-inc")
                        textBtn("A−", label: "Decrease font size", cmd: "font-size-dec")
                        vDivider()
                        textBtn("Σ",  label: "AutoSum",              cmd: "auto-sum")
                        iconBtn("eraser",          label: "Clear cell",   cmd: "clear-cell")
                        iconBtn("tablecells", label: "All borders", cmd: "border-all")

                    case .number:
                        textBtn("$",   label: "Currency",     cmd: "number-currency")
                        textBtn(",",   label: "Thousands",    cmd: "number-comma")
                        textBtn("%",   label: "Percent",      cmd: "number-percent")
                        vDivider()
                        textBtn(".0↑", label: "More decimal", cmd: "number-decimal-inc")
                        textBtn(".0↓", label: "Less decimal", cmd: "number-decimal-dec")
                        vDivider()
                        chipBtn("Date", label: "Date format", cmd: "number-date")
                        chipBtn("Time", label: "Time format", cmd: "number-time")
                        chipBtn("Text", label: "Text format", cmd: "number-text")

                    case .align:
                        iconBtn("text.alignleft",        label: "Left",   cmd: "cell-align-left")
                        iconBtn("text.aligncenter",      label: "Center", cmd: "cell-align-center")
                        iconBtn("text.alignright",       label: "Right",  cmd: "cell-align-right")
                        vDivider()
                        chipBtn("Wrap",    label: "Wrap text",       cmd: "wrap-text")
                        chipBtn("Merge",   label: "Merge cells",     cmd: "merge-center")
                        chipBtn("Unmerge", label: "Unmerge cells",   cmd: "merge-unmerge")
                        vDivider()
                        iconBtn("rectangle.topthird.inset.filled",    label: "Top",    cmd: "cell-valign-top")
                        iconBtn("rectangle.center.inset.filled",      label: "Middle", cmd: "cell-valign-middle")
                        iconBtn("rectangle.bottomthird.inset.filled", label: "Bottom", cmd: "cell-valign-bottom")

                    case .data:
                        // Filter first — most used Data action
                        iconBtn("line.3.horizontal.decrease.circle",
                                label: "Toggle AutoFilter", cmd: "filter-toggle")
                        vDivider()
                        // Sort
                        chipBtn("A→Z", label: "Sort A to Z", cmd: "sort-asc")
                        chipBtn("Z→A", label: "Sort Z to A", cmd: "sort-desc")
                        vDivider()
                        // Insert / delete rows
                        chipBtn("Row ↑", label: "Insert row above", cmd: "row-insert-above")
                        chipBtn("Row ↓", label: "Insert row below", cmd: "row-insert-below")
                        chipBtn("Row −", label: "Delete row",       cmd: "row-delete")
                        vDivider()
                        // Insert / delete columns
                        chipBtn("Col ←", label: "Insert column to the left",  cmd: "col-insert-left")
                        chipBtn("Col →", label: "Insert column to the right", cmd: "col-insert-right")
                        chipBtn("Col −", label: "Delete column",              cmd: "col-delete")
                        vDivider()
                        chipBtn("Freeze", label: "Freeze rows/columns at current cell", cmd: "freeze-panes")
                        vDivider()
                        chipBtn("Dedup",  label: "Remove duplicate rows", cmd: "remove-dup")

                    case .insert:
                        chipBtn("Table",   label: "Insert table",         cmd: "insert-table")
                        iconBtn("photo",   label: "Insert image",         cmd: "insert-image")
                        chipBtn("Chart",   label: "Insert chart",         cmd: "insert-chart")
                        chipBtn("Shape",   label: "Insert shape",         cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",           label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble",    label: "Comment",       cmd: "insert-comment")
                    }
                }
                .padding(.horizontal, 4)
            }
            // Trailing fade — hints that more buttons are available via scroll.
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24)
                }
            }

            // Color pickers pinned here — outside ScrollView so gesture is never blocked.
            if excelTab == .home {
                nativeColorBtn(icon: "character",   label: "Font color",
                               color: $fontColor, cmd: "font-color")
                nativeColorBtn(icon: "paintbucket.fill", label: "Fill color",
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
                        iconBtn("bold",          label: "Bold",          cmd: "bold")
                        iconBtn("italic",        label: "Italic",        cmd: "italic")
                        iconBtn("underline",     label: "Underline",     cmd: "underline")
                        iconBtn("strikethrough", label: "Strikethrough", cmd: "strikeout")
                        vDivider()
                        // Paragraph styles — directly accessible without opening Format sheet
                        chipBtn("Normal", label: "Normal style", cmd: "style:Normal")
                        chipBtn("Title",  label: "Title style",  cmd: "style:Title")
                        chipBtn("H1",     label: "Heading 1",    cmd: "style:Heading 1")
                        chipBtn("H2",     label: "Heading 2",    cmd: "style:Heading 2")
                        chipBtn("H3",     label: "Heading 3",    cmd: "style:Heading 3")

                    case .paragraph:
                        iconBtn("text.alignleft",    label: "Left",    cmd: "align-left")
                        iconBtn("text.aligncenter",  label: "Center",  cmd: "align-center")
                        iconBtn("text.alignright",   label: "Right",   cmd: "align-right")
                        iconBtn("text.alignjustify", label: "Justify", cmd: "align-justify")
                        vDivider()
                        iconBtn("list.bullet", label: "Bullet list",   cmd: "list-bullet")
                        iconBtn("list.number", label: "Numbered list", cmd: "list-numbered")
                        vDivider()
                        iconBtn("increase.indent", label: "Indent",   cmd: "indent-increase")
                        iconBtn("decrease.indent", label: "Outdent",  cmd: "indent-decrease")

                    case .insert:
                        iconBtn("photo",          label: "Insert image",   cmd: "insert-image")
                        chipBtn("Table",          label: "Insert table",   cmd: "insert-table")
                        chipBtn("Shape",          label: "Insert shape",   cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",           label: "Hyperlink",      cmd: "insert-link")
                        iconBtn("text.bubble",    label: "Comment",        cmd: "insert-comment")
                    }
                }
                .padding(.horizontal, 4)
            }

            if wordTab == .home {
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
                    iconBtn("bold",           label: "Bold",          cmd: "bold")
                    iconBtn("italic",         label: "Italic",        cmd: "italic")
                    iconBtn("underline",      label: "Underline",     cmd: "underline")
                    iconBtn("strikethrough",  label: "Strikethrough", cmd: "strikeout")
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

    // MARK: - Native color picker

    /// ColorPicker is the base layer at FULL opacity so UIKit always registers taps.
    /// Our icon + colored-bar overlay sits on top with .background(.bar) to cover
    /// the system swatch visually, and .allowsHitTesting(false) to pass taps through.
    private func nativeColorBtn(
        icon: String,
        label: String,
        color: Binding<Color>,
        cmd: String
    ) -> some View {
        ColorPicker(label, selection: color, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44, height: 44)
            .overlay {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                    Rectangle()
                        .fill(color.wrappedValue)
                        .frame(width: 18, height: 3)
                        .cornerRadius(1.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.bar)       // covers ColorPicker's own swatch UI
                .allowsHitTesting(false) // taps fall through to ColorPicker
            }
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

    /// Chip-style button (Date/Time/Text, A→Z/Z→A, paragraph styles).
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
