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
            case "ppt", "pptx", "odp", "ppsx": self = .ppt
            case "pdf":                        self = .pdf
            default:                           self = .unknown
            }
        }
    }

    // MARK: - Tab enums

    private enum ExcelTab: String, CaseIterable {
        case home    = "Home"
        case insert  = "Insert"
        case formula = "Formula"
        case data    = "Data"
        case format  = "Format"
    }

    private enum WordTab: String, CaseIterable {
        case home      = "Home"
        case paragraph = "Paragraph"
        case insert    = "Insert"
    }

    private enum PPTTab: String, CaseIterable {
        case home   = "Home"
        case insert = "Insert"
        case slide  = "Slide"
    }

    // MARK: - Inputs & state

    let kind: FileKind
    /// Current/total slide number for PPT — nil for all other kinds.
    var slideInfo: (current: Int, total: Int)? = nil
    let onCommand: (String) -> Void

    @State private var excelTab: ExcelTab = .home
    @State private var wordTab:  WordTab  = .home
    @State private var pptTab:   PPTTab   = .home
    @State private var fontColor:          Color = .black
    @State private var fillColor:          Color = Color(red: 1.0, green: 0.92, blue: 0.23)
    @State private var wordFontColor:      Color = .black
    @State private var wordHighlightColor: Color = Color(red: 1.0, green: 0.93, blue: 0.0)
    @State private var pptFontColor:       Color = .black

    // MARK: - Body

    var body: some View {
        switch kind {
        case .excel:
            VStack(spacing: 0) {
                tabBarWithTrailing(tabs: ExcelTab.allCases, selected: $excelTab) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 0.5, height: 22)
                        .padding(.horizontal, 2)
                    iconBtn("minus.magnifyingglass", label: "Zoom out", cmd: "zoom-out")
                    iconBtn("plus.magnifyingglass",  label: "Zoom in",  cmd: "zoom-in")
                        .padding(.trailing, 4)
                }
                excelContentRow
                    .animation(.easeInOut(duration: 0.12), value: excelTab)
            }
        case .word:
            VStack(spacing: 0) {
                tabBar(tabs: WordTab.allCases, selected: $wordTab)
                wordContentRow
                    .animation(.easeInOut(duration: 0.12), value: wordTab)
            }
        case .ppt:
            VStack(spacing: 0) {
                tabBar(tabs: PPTTab.allCases, selected: $pptTab)
                pptContentRow
                    .animation(.easeInOut(duration: 0.12), value: pptTab)
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
        tabBarWithTrailing(tabs: tabs, selected: selected) { EmptyView() }
    }

    private func tabBarWithTrailing<T: RawRepresentable & Hashable, Trailing: View>(
        tabs: [T],
        selected: Binding<T>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View where T.RawValue == String {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs, id: \.self) { tab in
                        let isActive = selected.wrappedValue == tab
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selected.wrappedValue = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13,
                                              weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isActive
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            trailing()
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
                        fmtBtn(.bold,          cmd: "bold")
                        fmtBtn(.italic,        cmd: "italic")
                        fmtBtn(.underline,     cmd: "underline")
                        fmtBtn(.strikethrough, cmd: "strikeout")
                        vDivider()
                        textBtn("A+", label: "Increase font size", cmd: "font-size-inc")
                        textBtn("A−", label: "Decrease font size", cmd: "font-size-dec")
                        vDivider()
                        textBtn("Σ",  label: "AutoSum",    cmd: "auto-sum")
                        iconBtn("eraser",         label: "Clear cell",  cmd: "clear-cell")
                        iconBtn("tablecells",     label: "All borders", cmd: "border-all")

                    case .insert:
                        iconBtn("photo",       label: "Insert image",  cmd: "insert-image")
                        chipBtn("Chart",       label: "Insert chart",  cmd: "insert-chart")
                        chipBtn("Shape",       label: "Insert shape",  cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",        label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble", label: "Comment",       cmd: "insert-comment")

                    case .formula:
                        // AutoSum — the most common formula action
                        textBtn("Σ",    label: "AutoSum",  cmd: "auto-sum")
                        vDivider()
                        // Common functions — each starts formula-entry mode with =FUNC(
                        chipBtn("SUM",    label: "Insert SUM",     cmd: "formula-insert:SUM")
                        chipBtn("AVG",    label: "Insert AVERAGE", cmd: "formula-insert:AVERAGE")
                        chipBtn("CNT",    label: "Insert COUNT",   cmd: "formula-insert:COUNT")
                        chipBtn("MAX",    label: "Insert MAX",     cmd: "formula-insert:MAX")
                        chipBtn("MIN",    label: "Insert MIN",     cmd: "formula-insert:MIN")
                        vDivider()
                        chipBtn("IF",     label: "Insert IF",      cmd: "formula-insert:IF")
                        chipBtn("VLKP",   label: "Insert VLOOKUP", cmd: "formula-insert:VLOOKUP")
                        chipBtn("CONCAT", label: "Concatenate",    cmd: "formula-insert:CONCATENATE")

                    case .data:
                        iconBtn("line.3.horizontal.decrease.circle",
                                label: "Toggle AutoFilter", cmd: "filter-toggle")
                        vDivider()
                        chipBtn("A→Z", label: "Sort A to Z", cmd: "sort-asc")
                        chipBtn("Z→A", label: "Sort Z to A", cmd: "sort-desc")
                        vDivider()
                        chipBtn("Row ↑", label: "Insert row above",        cmd: "row-insert-above")
                        chipBtn("Row ↓", label: "Insert row below",        cmd: "row-insert-below")
                        chipBtn("Row −", label: "Delete row",              cmd: "row-delete")
                        vDivider()
                        chipBtn("Col ←", label: "Insert column left",      cmd: "col-insert-left")
                        chipBtn("Col →", label: "Insert column right",     cmd: "col-insert-right")
                        chipBtn("Col −", label: "Delete column",           cmd: "col-delete")
                        vDivider()
                        chipBtn("Freeze", label: "Freeze panes",           cmd: "freeze-panes")
                        vDivider()
                        chipBtn("Dedup",  label: "Remove duplicates",      cmd: "remove-dup")

                    case .format:
                        // Number formats
                        textBtn("$",   label: "Currency",        cmd: "number-currency")
                        textBtn(",",   label: "Thousands",       cmd: "number-comma")
                        textBtn("%",   label: "Percent",         cmd: "number-percent")
                        vDivider()
                        textBtn(".0↑", label: "More decimals",   cmd: "number-decimal-inc")
                        textBtn(".0↓", label: "Less decimals",   cmd: "number-decimal-dec")
                        vDivider()
                        chipBtn("Date", label: "Date format",    cmd: "number-date")
                        chipBtn("Time", label: "Time format",    cmd: "number-time")
                        chipBtn("Text", label: "Text format",    cmd: "number-text")
                        vDivider()
                        // Alignment
                        iconBtn("text.alignleft",   label: "Align left",   cmd: "cell-align-left")
                        iconBtn("text.aligncenter", label: "Align center", cmd: "cell-align-center")
                        iconBtn("text.alignright",  label: "Align right",  cmd: "cell-align-right")
                        vDivider()
                        chipBtn("Wrap",    label: "Wrap text",    cmd: "wrap-text")
                        chipBtn("Merge",   label: "Merge cells",  cmd: "merge-center")
                        chipBtn("Unmerge", label: "Unmerge",      cmd: "merge-unmerge")
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
            if excelTab == .home || excelTab == .format {
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
                        // Format
                        fmtBtn(.bold,          cmd: "bold")
                        fmtBtn(.italic,        cmd: "italic")
                        fmtBtn(.underline,     cmd: "underline")
                        fmtBtn(.strikethrough, cmd: "strikeout")
                        vDivider()
                        // Size
                        textBtn("A+", label: "Increase font size", cmd: "font-size-inc")
                        textBtn("A−", label: "Decrease font size", cmd: "font-size-dec")
                        vDivider()
                        // Script
                        chipBtn("x²", label: "Superscript", cmd: "superscript")
                        chipBtn("x₂", label: "Subscript",   cmd: "subscript")
                        vDivider()
                        // Clear
                        iconBtn("eraser", label: "Clear formatting", cmd: "clear-format")
                        vDivider()
                        // Alignment
                        iconBtn("text.alignleft",    label: "Left",    cmd: "align-left")
                        iconBtn("text.aligncenter",  label: "Center",  cmd: "align-center")
                        iconBtn("text.alignright",   label: "Right",   cmd: "align-right")
                        iconBtn("text.alignjustify", label: "Justify", cmd: "align-justify")
                        vDivider()
                        // Lists
                        iconBtn("list.bullet", label: "Bullet list",   cmd: "list-bullet")
                        iconBtn("list.number", label: "Numbered list", cmd: "list-numbered")
                        vDivider()
                        // Styles
                        chipBtn("Normal", label: "Normal style", cmd: "style:Normal")
                        chipBtn("H1",     label: "Heading 1",    cmd: "style:Heading 1")
                        chipBtn("H2",     label: "Heading 2",    cmd: "style:Heading 2")
                        chipBtn("H3",     label: "Heading 3",    cmd: "style:Heading 3")
                    case .paragraph:
                        iconBtn("increase.indent", label: "Indent",  cmd: "indent-increase")
                        iconBtn("decrease.indent", label: "Outdent", cmd: "indent-decrease")
                        vDivider()
                        lineSpacingBtn(1.0)
                        lineSpacingBtn(1.5)
                        lineSpacingBtn(2.0)
                        vDivider()
                        iconBtn("text.alignleft",    label: "Left",    cmd: "align-left")
                        iconBtn("text.aligncenter",  label: "Center",  cmd: "align-center")
                        iconBtn("text.alignright",   label: "Right",   cmd: "align-right")
                        iconBtn("text.alignjustify", label: "Justify", cmd: "align-justify")
                        vDivider()
                        chipBtn("Title", label: "Title style", cmd: "style:Title")
                        chipBtn("H4",    label: "Heading 4",   cmd: "style:Heading 4")
                        chipBtn("H5",    label: "Heading 5",   cmd: "style:Heading 5")
                    case .insert:
                        iconBtn("photo",         label: "Insert image",  cmd: "insert-image")
                        chipBtn("Table",         label: "Insert table",  cmd: "insert-table")
                        chipBtn("Chart",         label: "Insert chart",  cmd: "insert-chart")
                        chipBtn("Shape",         label: "Insert shape",  cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",          label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble",   label: "Comment",       cmd: "insert-comment")
                        iconBtn("bookmark",      label: "Bookmark",      cmd: "insert-bookmark")
                        vDivider()
                        chipBtn("Pg Break",      label: "Page break",    cmd: "insert-page-break")
                        chipBtn("Header",        label: "Header",        cmd: "insert-header")
                        chipBtn("Footer",        label: "Footer",        cmd: "insert-footer")
                        chipBtn("Footnote",      label: "Footnote",      cmd: "insert-footnote")
                    }
                }
                .padding(.horizontal, 4)
            }
            if wordTab == .home {
                nativeColorBtn(icon: "character",  label: "Font color",
                               color: $wordFontColor,      cmd: "font-color")
                nativeColorBtn(icon: "highlighter", label: "Highlight",
                               color: $wordHighlightColor, cmd: "highlight-color")
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - PPT content row (row 2)

    private var pptContentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    switch pptTab {

                    case .home:
                        fmtBtn(.bold,          cmd: "bold")
                        fmtBtn(.italic,        cmd: "italic")
                        fmtBtn(.underline,     cmd: "underline")
                        fmtBtn(.strikethrough, cmd: "strikeout")
                        vDivider()
                        textBtn("A+", label: "Increase font size", cmd: "font-size-inc")
                        textBtn("A−", label: "Decrease font size", cmd: "font-size-dec")
                        vDivider()
                        iconBtn("text.alignleft",   label: "Align left",   cmd: "align-left")
                        iconBtn("text.aligncenter", label: "Align center", cmd: "align-center")
                        iconBtn("text.alignright",  label: "Align right",  cmd: "align-right")
                        vDivider()
                        iconBtn("align.vertical.top",    label: "Align top",    cmd: "ppt-valign-top")
                        iconBtn("align.vertical.center", label: "Align middle", cmd: "ppt-valign-middle")
                        iconBtn("align.vertical.bottom", label: "Align bottom", cmd: "ppt-valign-bottom")
                        vDivider()
                        iconBtn("eraser", label: "Clear formatting", cmd: "clear-format")

                    case .insert:
                        iconBtn("photo",         label: "Insert image",  cmd: "insert-image")
                        chipBtn("Shape",         label: "Insert shape",  cmd: "insert-shape")
                        chipBtn("Chart",         label: "Insert chart",  cmd: "insert-chart")
                        vDivider()
                        iconBtn("link",          label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble",   label: "Comment",       cmd: "insert-comment")
                        vDivider()
                        chipBtn("Text Box",      label: "Insert text box", cmd: "ppt-insert-textbox")

                    case .slide:
                        chipBtn("+ Slide",   label: "Add slide",       cmd: "slide-add")
                        chipBtn("Duplicate", label: "Duplicate slide", cmd: "slide-duplicate")
                        chipBtn("Delete",    label: "Delete slide",    cmd: "slide-delete")
                        vDivider()
                        iconBtn("chevron.left",  label: "Previous slide", cmd: "slide-prev")
                        if let info = slideInfo {
                            Text("\(info.current)/\(info.total)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 36, minHeight: 44)
                                .padding(.horizontal, 2)
                        }
                        iconBtn("chevron.right", label: "Next slide",     cmd: "slide-next")
                        vDivider()
                        chipBtn("Blank",       label: "Blank layout",            cmd: "slide-layout:0")
                        chipBtn("Title",       label: "Title layout",            cmd: "slide-layout:1")
                        chipBtn("Content",     label: "Title+Content layout",    cmd: "slide-layout:2")
                        chipBtn("2 Content",   label: "Two Content layout",      cmd: "slide-layout:3")
                        chipBtn("Title Only",  label: "Title Only layout",       cmd: "slide-layout:5")
                        chipBtn("Centered",    label: "Centered Text layout",    cmd: "slide-layout:6")
                    }
                }
                .padding(.horizontal, 4)
            }
            if pptTab == .home {
                nativeColorBtn(icon: "character", label: "Font color",
                               color: $pptFontColor, cmd: "font-color")
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Single row (PDF / unknown)

    private var singleRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    iconBtn("arrow.uturn.backward", label: "Undo", cmd: "undo")
                    iconBtn("arrow.uturn.forward",  label: "Redo", cmd: "redo")
                    vDivider()
                    fmtBtn(.bold,          cmd: "bold")
                    fmtBtn(.italic,        cmd: "italic")
                    fmtBtn(.underline,     cmd: "underline")
                    fmtBtn(.strikethrough, cmd: "strikeout")
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

    /// Styled text button for B / I / U / S — mirrors competitor apps.
    private enum FmtStyle { case bold, italic, underline, strikethrough }

    @ViewBuilder
    private func fmtBtn(_ style: FmtStyle, cmd: String) -> some View {
        let accessLabel: String = {
            switch style {
            case .bold:          return "Bold"
            case .italic:        return "Italic"
            case .underline:     return "Underline"
            case .strikethrough: return "Strikethrough"
            }
        }()
        Button { onCommand(cmd) } label: {
            Group {
                switch style {
                case .bold:
                    Text("B")
                        .font(.system(size: 18, weight: .bold))
                case .italic:
                    Text("I")
                        .font(.system(size: 18, weight: .regular))
                        .italic()
                case .underline:
                    Text("U")
                        .font(.system(size: 18, weight: .regular))
                        .underline()
                case .strikethrough:
                    Text("S")
                        .font(.system(size: 18, weight: .regular))
                        .strikethrough()
                }
            }
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(accessLabel)
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

    /// Chip hiển thị icon giãn dòng + hệ số — rõ hơn "1×" thuần
    private func lineSpacingBtn(_ value: Double) -> some View {
        let display = value == 1.0 ? "1" : value == 1.5 ? "1.5" : "2"
        let accessibility = value == 1.0 ? "Single line spacing"
                          : value == 1.5 ? "1.5 line spacing"
                          : "Double line spacing"
        return Button { onCommand("line-spacing:\(value)") } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 9, weight: .medium))
                Text(display)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 7))
            .frame(minHeight: 44)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibility)
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
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
