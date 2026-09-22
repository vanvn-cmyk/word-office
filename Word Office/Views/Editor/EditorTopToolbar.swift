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
        case review    = "Review"
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
    /// Current/total page number for Word — nil for all other kinds.
    var wordPageInfo: (current: Int, total: Int)? = nil
    /// Current font name for Excel — shown in the Font picker button.
    var excelFontName: String = "Font"
    /// Current font name for Word — shown in the Font picker chip.
    var wordFontName: String = "Font"
    let onCommand: (String) -> Void

    @State private var excelTab: ExcelTab = .home
    @State private var wordTab:  WordTab  = .home
    @State private var pptTab:   PPTTab   = .home
    @State private var fontColor:               Color = .black
    @State private var fillColor:               Color = Color(red: 1.0, green: 0.92, blue: 0.23)
    @State private var wordFontColor:           Color = .black
    @State private var wordHighlightColor:      Color = Color(red: 1.0, green: 0.93, blue: 0.0)
    @State private var pptFontColor:            Color = .black
    @State private var wordTrackChangesActive:  Bool  = false

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
                tabBarWithTrailing(tabs: WordTab.allCases, selected: $wordTab) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 0.5, height: 22)
                        .padding(.horizontal, 2)
                    iconBtn("minus.magnifyingglass", label: "Zoom out", cmd: "zoom-out")
                    iconBtn("plus.magnifyingglass",  label: "Zoom in",  cmd: "zoom-in")
                        .padding(.trailing, 4)
                }
                wordContentRow
                    .animation(.easeInOut(duration: 0.12), value: wordTab)
            }
        case .ppt:
            VStack(spacing: 0) {
                pptTabBar
                pptContentRow
                    .animation(.easeInOut(duration: 0.12), value: pptTab)
            }
        default:
            singleRow
        }
    }

    // MARK: - PPT tab bar (fixed 3-col, red accent, slide counter)

    /// Red accent matching PowerPoint's brand color.
    private static let pptAccent = Color(red: 0.84, green: 0.22, blue: 0.18)

    /// Custom PPT tab bar — fixed three equal columns (no scroll needed) with filled
    /// active-state pill and a persistent slide counter at the trailing edge.
    private var pptTabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(PPTTab.allCases, id: \.self) { tab in
                    let active = pptTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { pptTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                active ? Self.pptAccent : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: slideInfo != nil ? 4 : 10))

            if let info = slideInfo {
                Text("\(info.current)/\(info.total)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                    .padding(.trailing, 10)
            }
        }
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
                        chipBtn(
                            String(excelFontName.prefix(11)) + (excelFontName.count > 11 ? "…" : ""),
                            label: "Font face", cmd: "excel-font-picker"
                        )
                        vDivider()
                        iconBtn("arrow.uturn.backward", label: "Undo", cmd: "undo")
                        iconBtn("arrow.uturn.forward",  label: "Redo", cmd: "redo")
                        vDivider()
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
                        chipBtn("Table",       label: "Insert table",  cmd: "insert-table")
                        chipBtn("Shape",       label: "Insert shape",  cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",        label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble", label: "Comment",       cmd: "insert-comment")
                        vDivider()
                        chipBtn("Symbol",      label: "Insert symbol", cmd: "insert-symbol")

                    case .formula:
                        // AutoSum
                        textBtn("Σ",      label: "AutoSum",           cmd: "auto-sum")
                        vDivider()
                        // Aggregate
                        chipBtn("SUM",    label: "SUM",               cmd: "formula-insert:SUM")
                        chipBtn("AVG",    label: "AVERAGE",           cmd: "formula-insert:AVERAGE")
                        chipBtn("CNT",    label: "COUNT",             cmd: "formula-insert:COUNT")
                        chipBtn("CNTA",   label: "COUNTA",            cmd: "formula-insert:COUNTA")
                        chipBtn("MAX",    label: "MAX",               cmd: "formula-insert:MAX")
                        chipBtn("MIN",    label: "MIN",               cmd: "formula-insert:MIN")
                        chipBtn("MEDIAN", label: "MEDIAN",            cmd: "formula-insert:MEDIAN")
                        chipBtn("STDEV",  label: "STDEV",             cmd: "formula-insert:STDEV")
                        vDivider()
                        // Conditional aggregate
                        chipBtn("SUMIF",  label: "SUMIF",             cmd: "formula-insert:SUMIF")
                        chipBtn("CNTIF",  label: "COUNTIF",           cmd: "formula-insert:COUNTIF")
                        chipBtn("AVRIF",  label: "AVERAGEIF",         cmd: "formula-insert:AVERAGEIF")
                        vDivider()
                        // Logical
                        chipBtn("IF",     label: "IF",                cmd: "formula-insert:IF")
                        chipBtn("IFERR",  label: "IFERROR",           cmd: "formula-insert:IFERROR")
                        chipBtn("AND",    label: "AND",               cmd: "formula-insert:AND")
                        chipBtn("OR",     label: "OR",                cmd: "formula-insert:OR")
                        chipBtn("NOT",    label: "NOT",               cmd: "formula-insert:NOT")
                        vDivider()
                        // Lookup
                        chipBtn("VLKP",   label: "VLOOKUP",           cmd: "formula-insert:VLOOKUP")
                        chipBtn("HLKP",   label: "HLOOKUP",           cmd: "formula-insert:HLOOKUP")
                        chipBtn("INDEX",  label: "INDEX",             cmd: "formula-insert:INDEX")
                        chipBtn("MATCH",  label: "MATCH",             cmd: "formula-insert:MATCH")
                        vDivider()
                        // Math
                        chipBtn("ROUND",  label: "ROUND",             cmd: "formula-insert:ROUND")
                        chipBtn("ABS",    label: "ABS",               cmd: "formula-insert:ABS")
                        chipBtn("SQRT",   label: "SQRT",              cmd: "formula-insert:SQRT")
                        chipBtn("INT",    label: "INT",               cmd: "formula-insert:INT")
                        chipBtn("MOD",    label: "MOD",               cmd: "formula-insert:MOD")
                        chipBtn("POWER",  label: "POWER",             cmd: "formula-insert:POWER")
                        vDivider()
                        // Text
                        chipBtn("CONCAT", label: "CONCATENATE",       cmd: "formula-insert:CONCATENATE")
                        chipBtn("LEFT",   label: "LEFT",              cmd: "formula-insert:LEFT")
                        chipBtn("RIGHT",  label: "RIGHT",             cmd: "formula-insert:RIGHT")
                        chipBtn("MID",    label: "MID",               cmd: "formula-insert:MID")
                        chipBtn("LEN",    label: "LEN",               cmd: "formula-insert:LEN")
                        chipBtn("TRIM",   label: "TRIM",              cmd: "formula-insert:TRIM")
                        chipBtn("UPPER",  label: "UPPER",             cmd: "formula-insert:UPPER")
                        chipBtn("LOWER",  label: "LOWER",             cmd: "formula-insert:LOWER")
                        chipBtn("FIND",   label: "FIND",              cmd: "formula-insert:FIND")
                        chipBtn("SUBST",  label: "SUBSTITUTE",        cmd: "formula-insert:SUBSTITUTE")
                        chipBtn("TEXT",   label: "TEXT",              cmd: "formula-insert:TEXT")
                        vDivider()
                        // Date & time
                        chipBtn("TODAY",  label: "TODAY",             cmd: "formula-insert:TODAY")
                        chipBtn("NOW",    label: "NOW",               cmd: "formula-insert:NOW")
                        chipBtn("DATE",   label: "DATE",              cmd: "formula-insert:DATE")
                        chipBtn("YEAR",   label: "YEAR",              cmd: "formula-insert:YEAR")
                        chipBtn("MONTH",  label: "MONTH",             cmd: "formula-insert:MONTH")
                        chipBtn("DAY",    label: "DAY",               cmd: "formula-insert:DAY")
                        chipBtn("DAYS",   label: "DAYS",              cmd: "formula-insert:DAYS")
                        Spacer().frame(width: 32)

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
                        iconBtn("text.alignleft",        label: "Align left",   cmd: "cell-align-left")
                        iconBtn("text.aligncenter",      label: "Align center", cmd: "cell-align-center")
                        iconBtn("text.alignright",       label: "Align right",  cmd: "cell-align-right")
                        iconBtn("align.vertical.top",    label: "Align top",    cmd: "cell-valign-top")
                        iconBtn("align.vertical.center", label: "Align middle", cmd: "cell-valign-middle")
                        iconBtn("align.vertical.bottom", label: "Align bottom", cmd: "cell-valign-bottom")
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
            // Page counter pinned on the left — always visible regardless of scroll position
            if let info = wordPageInfo {
                Button { onCommand("word-page-prev") } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(info.current > 1 ? .primary : Color.secondary.opacity(0.3))
                .disabled(info.current <= 1)
                .accessibilityLabel("Previous page")
                Text("\(info.current)/\(info.total)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                Button { onCommand("word-page-next") } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(info.current < info.total ? .primary : Color.secondary.opacity(0.3))
                .disabled(info.current >= info.total && info.total > 1)
                .accessibilityLabel("Next page")
                vDivider()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    switch wordTab {
                    case .home:
                        // Font name chip first — mirrors Excel Home tab pattern
                        chipBtn(
                            String(wordFontName.prefix(11)) + (wordFontName.count > 11 ? "…" : ""),
                            label: "Font face", cmd: "word-font-picker"
                        )
                        vDivider()
                        // Format — B next to font chip as requested
                        fmtBtn(.bold,          cmd: "bold")
                        fmtBtn(.italic,        cmd: "italic")
                        fmtBtn(.underline,     cmd: "underline")
                        fmtBtn(.strikethrough, cmd: "strikeout")
                        vDivider()
                        iconBtn("arrow.uturn.backward", label: "Undo", cmd: "undo")
                        iconBtn("arrow.uturn.forward",  label: "Redo", cmd: "redo")
                        vDivider()
                        textBtn("A+", label: "Increase font size", cmd: "font-size-inc")
                        textBtn("A−", label: "Decrease font size", cmd: "font-size-dec")
                        vDivider()
                        // Script
                        chipBtn("x²", label: "Superscript", cmd: "superscript")
                        chipBtn("x₂", label: "Subscript",   cmd: "subscript")
                        vDivider()
                        // Clear & Text case
                        iconBtn("eraser",       label: "Clear formatting", cmd: "clear-format")
                        chipBtn("Aa",           label: "Text case",        cmd: "text-case")
                        vDivider()
                        // Alignment + styles adjacent (no divider between them)
                        iconBtn("text.alignleft",    label: "Left",    cmd: "align-left")
                        iconBtn("text.aligncenter",  label: "Center",  cmd: "align-center")
                        iconBtn("text.alignright",   label: "Right",   cmd: "align-right")
                        iconBtn("text.alignjustify", label: "Justify", cmd: "align-justify")
                        vDivider()
                        // Lists
                        iconBtn("list.bullet", label: "Bullet list",   cmd: "list-bullet")
                        iconBtn("list.number", label: "Numbered list", cmd: "list-numbered")
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
                        chipBtn("Normal", label: "Normal",    cmd: "style:Normal")
                        chipBtn("H1",     label: "Heading 1", cmd: "style:Heading 1")
                        chipBtn("H2",     label: "Heading 2", cmd: "style:Heading 2")
                        chipBtn("H3",     label: "Heading 3", cmd: "style:Heading 3")
                        chipBtn("H4",     label: "Heading 4", cmd: "style:Heading 4")
                        chipBtn("H5",     label: "Heading 5", cmd: "style:Heading 5")
                        chipBtn("Title",  label: "Title",     cmd: "style:Title")
                    case .insert:
                        iconBtn("photo",         label: "Insert image",  cmd: "insert-image")
                        chipBtn("Table",         label: "Insert table",  cmd: "insert-table")
                        chipBtn("Shape",         label: "Insert shape",  cmd: "insert-shape")
                        vDivider()
                        // Table row / column operations (active when cursor is inside a table)
                        chipBtn("Row +",  label: "Add row below",    cmd: "table-row-add")
                        chipBtn("Row −",  label: "Delete row",       cmd: "table-row-del")
                        chipBtn("Col +",  label: "Add column right", cmd: "table-col-add")
                        chipBtn("Col −",  label: "Delete column",    cmd: "table-col-del")
                        vDivider()
                        iconBtn("link",          label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble",   label: "Comment",       cmd: "insert-comment")
                        vDivider()
                        chipBtn("Symbol",        label: "Insert symbol", cmd: "insert-symbol")
                        vDivider()
                        chipBtn("Pg Break",      label: "Page break",    cmd: "insert-page-break")
                        chipBtn("Header",        label: "Header",        cmd: "insert-header")
                        chipBtn("Footer",        label: "Footer",        cmd: "insert-footer")
                        chipBtn("Footnote",      label: "Footnote",      cmd: "insert-footnote")
                    case .review:
                        // Find & Replace
                        iconBtn("magnifyingglass", label: "Find & Replace", cmd: "word-find-replace")
                        vDivider()
                        // Track Changes — active chip shows current state
                        activeChipBtn("Track",    label: "Track Changes",     cmd: "track-changes",    isActive: $wordTrackChangesActive)
                        iconBtn("checkmark",      label: "Accept change",     cmd: "review-accept")
                        iconBtn("xmark",          label: "Reject change",     cmd: "review-reject")
                        chipBtn("Acc All",        label: "Accept all changes", cmd: "review-accept-all")
                        chipBtn("Rej All",        label: "Reject all changes", cmd: "review-reject-all")
                        vDivider()
                        // Document info
                        chipBtn("Words",   label: "Word count",  cmd: "word-count")
                        chipBtn("Spell",   label: "Spell check", cmd: "spell-check")
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
                        // Undo / Redo — first so thumb can reach while keyboard is open
                        iconBtn("arrow.uturn.backward", label: "Undo", cmd: "undo")
                        iconBtn("arrow.uturn.forward",  label: "Redo", cmd: "redo")
                        vDivider()
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
                        iconBtn("list.bullet", label: "Bullet list",   cmd: "list-bullet")
                        iconBtn("list.number", label: "Numbered list", cmd: "list-numbered")
                        vDivider()
                        iconBtn("eraser", label: "Clear formatting", cmd: "clear-format")

                    case .insert:
                        iconBtn("photo",         label: "Insert image",  cmd: "insert-image")
                        chipBtn("Table",         label: "Insert table",  cmd: "insert-table")
                        chipBtn("Shape",         label: "Insert shape",  cmd: "insert-shape")
                        vDivider()
                        iconBtn("link",          label: "Hyperlink",     cmd: "insert-link")
                        iconBtn("text.bubble",   label: "Comment",       cmd: "insert-comment")
                        vDivider()
                        chipBtn("Text Box",      label: "Insert text box", cmd: "ppt-insert-textbox")
                        chipBtn("Symbol",        label: "Insert symbol",   cmd: "insert-symbol")

                    case .slide:
                        // Slide management
                        accentChipBtn("+ Slide",   label: "Add slide",       cmd: "slide-add")
                        chipBtn("Duplicate",       label: "Duplicate slide", cmd: "slide-duplicate")
                        destructiveChipBtn("Delete", label: "Delete slide",  cmd: "slide-delete")
                        vDivider()
                        // Navigation — counter is in the tab bar, so just prev/next here
                        iconBtn("chevron.left",  label: "Previous slide", cmd: "slide-prev")
                        iconBtn("chevron.right", label: "Next slide",     cmd: "slide-next")
                        vDivider()
                        // Layouts
                        layoutChipBtn("Blank",   icon: "rectangle",                   cmd: "slide-layout:0")
                        layoutChipBtn("Title",   icon: "rectangle.topthird.inset.filled", cmd: "slide-layout:1")
                        layoutChipBtn("Content", icon: "rectangle.split.2x1",          cmd: "slide-layout:2")
                        layoutChipBtn("2 Col",   icon: "rectangle.split.3x1",          cmd: "slide-layout:3")
                        layoutChipBtn("Title Only", icon: "rectangle.topthird.inset.filled", cmd: "slide-layout:5")
                        layoutChipBtn("Center",  icon: "text.aligncenter",             cmd: "slide-layout:6")
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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 7))
                .frame(minHeight: 44)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    /// Toggle chip — shows accent fill when `isActive` is true, toggling on each tap.
    private func activeChipBtn(
        _ text: String, label: String, cmd: String, isActive: Binding<Bool>
    ) -> some View {
        Button {
            isActive.wrappedValue.toggle()
            onCommand(cmd)
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive.wrappedValue ? .white : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isActive.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .frame(minHeight: 44)
                .padding(.horizontal, 2)
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

    /// Chip with the PPT red accent fill — used for primary actions like "+ Slide".
    private func accentChipBtn(_ text: String, label: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Self.pptAccent, in: RoundedRectangle(cornerRadius: 7))
                .frame(minHeight: 44)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Chip tinted red for destructive slide actions (Delete).
    private func destructiveChipBtn(_ text: String, label: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.pptAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Self.pptAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                .frame(minHeight: 44)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Layout chip with a small SF Symbol preview above the label.
    private func layoutChipBtn(_ text: String, icon: String, cmd: String) -> some View {
        Button { onCommand(cmd) } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                Text(text)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 46, minHeight: 44)
            .padding(.horizontal, 4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(text) layout")
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
