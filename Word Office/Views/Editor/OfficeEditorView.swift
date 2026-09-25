import SwiftUI
import UIKit
import Network
import PhotosUI

// UserDefaults key — set true the first time the editor fully loads (sdkjs cached).
private let kCacheReadyKey = "officeEditorCacheReady"

/// Bubbles the editor's unsaved-changes state up through the SwiftUI hierarchy
/// so EditorSheet can intercept the Done button without needing a direct binding.
struct EditorDirtyPreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct OfficeEditorView: View {
    let ref: DocumentRef

    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    @State private var errorMessage: String? = nil
    @State private var saveCount = 0
    @State private var isDirty = false
    @State private var editorVC: OfficeEditorViewController?
    @State private var slideProgress: (current: Int, total: Int) = (1, 1)
    @State private var slideThumbnails: [Int: UIImage] = [:]
    /// Incremented on every thumbnail update so PPTSlideStrip.== detects the change
    /// without comparing UIImage instances (which don't conform to Equatable).
    @State private var thumbnailVersion: Int = 0
    @State private var sheetNames: [String] = []
    @State private var activeSheetIndex: Int = 0
    @State private var currentExcelFont: String = "Font"
    @State private var currentWordFont:  String = "Font"
    @State private var currentPPTFont:   String = "Font"
    // Debounce tasks — font-change events fire on every cursor move; coalescing
    // to 80ms prevents rapid @State churn from re-running OfficeEditorView.body.
    @State private var excelFontTask: Task<Void, Never>?
    @State private var wordFontTask:  Task<Void, Never>?
    @State private var pptFontTask:   Task<Void, Never>?

    // Native photo insertion
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem? = nil

    // Native filter sheet (replaces ONLYOFFICE's web filter panel)
    @State private var filterItems: [NativeFilterItem] = []
    @State private var showFilterSheet = false

    // Native insert sheets
    @State private var showLinkSheet        = false
    @State private var showCommentSheet     = false
    @State private var showTableSheet       = false
    @State private var showChartSheet       = false
    @State private var showShapeSheet       = false
    @State private var showFindReplaceSheet = false
    @State private var showFontPickerSheet  = false
    @State private var pendingLink: (url: String, text: String)? = nil
    @State private var pendingComment: String? = nil
    @State private var pendingTable: (rows: Int, cols: Int)? = nil
    @State private var pendingChart: String? = nil
    @State private var pendingShape: String? = nil
    @State private var pendingFindReplace: (find: String, replace: String, replaceAll: Bool)? = nil
    @State private var pendingFont: String? = nil
    @State private var showSymbolSheet    = false
    @State private var pendingSymbol: String? = nil
    @State private var showTransitionSheet  = false
    @State private var showTextBoxSheet     = false
    @State private var pendingTextBox: String? = nil
    @State private var pptZoomReady = false

    private var fileKind: EditorTopToolbar.FileKind {
        EditorTopToolbar.FileKind(ext: ref.url.pathExtension)
    }

    var body: some View {
        Group {
            if let msg = errorMessage {
                ContentUnavailableView(
                    "Could Not Open Document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            } else {
                VStack(spacing: 0) {
                    EditorTopToolbar(
                        kind: fileKind,
                        slideInfo: fileKind == .ppt ? slideProgress : nil,
                        excelFontName: currentExcelFont,
                        wordFontName: currentWordFont,
                        pptFontName: currentPPTFont,
                        onCommand: handleCommand
                    )

                    ZStack {
                        _OfficeWebView(
                            ref: ref,
                            onFileSaved: handleSave,
                            onError: handleError,
                            onReady: handleReady,
                            onDirtyChange: { if $0 { isDirty = true } },
                            onInteraction: { isDirty = true },
                            onVCReady: { editorVC = $0 },
                            onFilterRequest: { items in
                                filterItems = items
                                showFilterSheet = true
                            },
                            onSlideChange: { c, t in
                                if t < slideProgress.total {
                                    // Slides were deleted: remove thumbnails for indices that no
                                    // longer exist. Do NOT removeAll() — that clears thumbnails for
                                    // slides that still exist and makes the strip flash blank.
                                    for idx in (t + 1)...max(t + 1, slideProgress.total) {
                                        slideThumbnails.removeValue(forKey: idx)
                                    }
                                    thumbnailVersion &+= 1
                                }
                                slideProgress = (c, t)
                            },
                            onSlideThumbnail: { num, data in
                                if let img = UIImage(data: data) {
                                    slideThumbnails[num] = img
                                    thumbnailVersion &+= 1
                                }
                            },
                            onSheetListChange: { names, idx in
                                sheetNames = names
                                activeSheetIndex = idx
                            },
                            onExcelFontChange: { name in
                                excelFontTask?.cancel()
                                excelFontTask = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(80))
                                    guard !Task.isCancelled else { return }
                                    currentExcelFont = name
                                }
                            },
                            onWordFontChange: { name in
                                wordFontTask?.cancel()
                                wordFontTask = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(80))
                                    guard !Task.isCancelled else { return }
                                    currentWordFont = name
                                }
                            },
                            onPPTFontChange: { name in
                                pptFontTask?.cancel()
                                pptFontTask = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(80))
                                    guard !Task.isCancelled else { return }
                                    currentPPTFont = name
                                }
                            },
                            onPPTZoomReady:    { pptZoomReady = true },
                            onDocSaved:        { toaster.show(.success, title: "Saved") }
                        )
                        if fileKind == .ppt && !pptZoomReady {
                            Color.dsBackgroundPrimary
                                .ignoresSafeArea()
                                .overlay {
                                    VStack(spacing: 16) {
                                        ProgressView().scaleEffect(1.2)
                                        Text("Getting your slides ready…")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                        }
                    }
                    .animation(.easeOut(duration: 0.35), value: pptZoomReady)

                    bottomStrip

                }
                // Native photo picker — triggered by "insert-image" command
                .photosPicker(
                    isPresented: $showImagePicker,
                    selection: $imagePickerItem,
                    matching: .images
                )
                .onChange(of: imagePickerItem) { _, item in
                    guard let item else { return }
                    Task { await sendPickedImage(item) }
                }
                // Native filter + sort sheet
                .sheet(isPresented: $showFilterSheet) {
                    NativeFilterView(
                        items: filterItems,
                        onSort: { ascending in
                            showFilterSheet = false
                            editorVC?.execEditorCommand(ascending ? "sort-asc" : "sort-desc")
                            // Cancel the hidden OO filter panel (no changes to values)
                            editorVC?.applyNativeFilter(selectedIds: [], cancel: true)
                        },
                        onCommit: { selectedIds, cancelled in
                            showFilterSheet = false
                            editorVC?.applyNativeFilter(selectedIds: selectedIds, cancel: cancelled)
                        }
                    )
                }
                // Native hyperlink insert sheet. onDismiss fires at the START of the
                // sheet's dismiss animation (~350ms before WKWebView is fully foregrounded).
                // The 400ms delay here + 200ms setTimeout inside _insertHyperlink = 600ms
                // total before the API fires, safely after the animation completes and the
                // editor cursor is restored. Without this delay, add_Hyperlink throws in
                // the catch block and the user sees "Link insert failed — please try again".
                .sheet(isPresented: $showLinkSheet, onDismiss: {
                    if let link = pendingLink {
                        let captured = link
                        pendingLink = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            editorVC?.insertHyperlink(url: captured.url, displayText: captured.text)
                        }
                    }
                }) {
                    NativeLinkView(
                        onCommit: { url, text in
                            pendingLink = (url, text)
                            showLinkSheet = false
                        },
                        onCancel: { showLinkSheet = false }
                    )
                }
                // Native comment insert sheet — addComment fires in onDismiss for the
                // same reason as link: WKWebView must fully regain focus first.
                .sheet(isPresented: $showCommentSheet, onDismiss: {
                    if let text = pendingComment {
                        editorVC?.addComment(text: text)
                        pendingComment = nil
                    }
                }) {
                    NativeCommentView(
                        onCommit: { text in
                            pendingComment = text
                            showCommentSheet = false
                        },
                        onCancel: { showCommentSheet = false }
                    )
                }
                // Native table insert sheet — safe path avoids _clickOOBtn (opens OO's
                // table dialog which crashes WKWebView on iOS). insertTable fires in
                // onDismiss after WKWebView regains focus.
                .sheet(isPresented: $showTableSheet, onDismiss: {
                    if let t = pendingTable {
                        let captured = t; pendingTable = nil
                        // 0.35s: give sheet dismiss animation + WKWebView focus restoration
                        // time to complete before calling insertTable (which needs an active cursor).
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            editorVC?.insertTable(rows: captured.rows, cols: captured.cols)
                        }
                    }
                }) {
                    NativeTableView(
                        onCommit: { rows, cols in
                            pendingTable = (rows, cols)
                            showTableSheet = false
                        },
                        onCancel: { showTableSheet = false }
                    )
                }
                // Native chart insert sheet — insertChart fires in onDismiss after WKWebView regains focus.
                .sheet(isPresented: $showChartSheet, onDismiss: {
                    if let chartType = pendingChart {
                        editorVC?.insertChart(type: chartType)
                        pendingChart = nil
                    }
                }) {
                    NativeChartView(
                        onCommit: { type in
                            pendingChart = type
                            showChartSheet = false
                        },
                        onCancel: { showChartSheet = false }
                    )
                }
                // Native shape insert sheet — insertShape fires in onDismiss after WKWebView regains focus.
                .sheet(isPresented: $showShapeSheet, onDismiss: {
                    if let shapeType = pendingShape {
                        editorVC?.insertShape(type: shapeType)
                        pendingShape = nil
                    }
                }) {
                    NativeShapeView(
                        onCommit: { type in
                            pendingShape = type
                            showShapeSheet = false
                        },
                        onCancel: { showShapeSheet = false }
                    )
                }
                // Native find & replace sheet
                .sheet(isPresented: $showFindReplaceSheet, onDismiss: {
                    if let fr = pendingFindReplace {
                        editorVC?.findAndReplace(find: fr.find, replace: fr.replace, replaceAll: fr.replaceAll)
                        pendingFindReplace = nil
                    }
                }) {
                    NativeFindReplaceView(
                        onDismissWebKeyboard: { editorVC?.dismissKeyboard() },
                        onCommit: { find, replace, replaceAll in
                            pendingFindReplace = (find, replace, replaceAll)
                            showFindReplaceSheet = false
                        },
                        onCancel: { showFindReplaceSheet = false }
                    )
                }
                // Native font picker sheet
                .sheet(isPresented: $showFontPickerSheet, onDismiss: {
                    if let font = pendingFont {
                        editorVC?.setFontFamily(font)
                        if fileKind == .excel { currentExcelFont = font }
                        if fileKind == .ppt   { currentPPTFont   = font }
                        pendingFont = nil
                    }
                }) {
                    NativeFontPickerView(
                        onCommit: { font in
                            pendingFont = font
                            showFontPickerSheet = false
                        },
                        onCancel: { showFontPickerSheet = false }
                    )
                }
                // Symbol / special character picker — fires insertSymbol in onDismiss so
                // WKWebView has fully regained focus before JS is evaluated.
                .sheet(isPresented: $showSymbolSheet, onDismiss: {
                    if let sym = pendingSymbol {
                        editorVC?.insertSymbol(sym)
                        pendingSymbol = nil
                    }
                }) {
                    NativeSymbolPickerView(
                        onCommit: { sym in
                            pendingSymbol = sym
                            showSymbolSheet = false
                        },
                        onCancel: { showSymbolSheet = false }
                    )
                }
                // Native text box insert sheet — insertTextBoxWithText fires in onDismiss
                // so WKWebView has fully regained focus before JS is evaluated.
                .sheet(isPresented: $showTextBoxSheet, onDismiss: {
                    let text = pendingTextBox ?? ""
                    pendingTextBox = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        editorVC?.insertTextBoxWithText(text)
                    }
                }) {
                    NativeTextBoxView(
                        onCommit: { text in
                            pendingTextBox = text
                            showTextBoxSheet = false
                        },
                        onCancel: { showTextBoxSheet = false }
                    )
                }
                .sheet(isPresented: $showTransitionSheet) {
                    SlideTransitionSheet { type in
                        editorVC?.execEditorCommand("ppt-apply-transition:\(type)")
                    }
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.dsBackgroundElevated)
                }
            }
        }
        .preference(key: EditorDirtyPreferenceKey.self, value: isDirty)
        .navigationTitle(fileKind == .word ? "" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorNavPill }
        .task { await checkNetworkOnFirstLaunch() }
        .onReceive(NotificationCenter.default.publisher(for: .editorSaveRequested)) { _ in
            editorVC?.execEditorCommand("save")
        }
    }

    // MARK: - Command routing

    private func handleCommand(_ cmd: String) {
        // Dismiss any active WKWebView keyboard before showing a sheet.
        // OO's editor holds the keyboard as first responder; if we don't resign it
        // before the sheet appears iOS creates conflicting layout constraints between
        // the keyboard placeholder and the sheet's input view (UIConstraintBasedLayout
        // "accessoryView.bottom" vs "inputView.top" warning).
        switch cmd {
        case "insert-image", "insert-link", "insert-comment",
             "insert-table", "insert-chart", "insert-shape",
             "insert-symbol", "word-font-picker", "excel-font-picker", "ppt-font-picker":
            // webView.endEditing(true) is more reliable than UIApplication.resignFirstResponder
            // for WKWebView: it explicitly ends editing on WKContentView regardless of what
            // the current first responder is, preventing the sheet's TextFields from competing
            // with WKWebView for keyboard ownership.
            // word-find-replace is excluded: NativeFindReplaceView's onDismissWebKeyboard
            // closure fires AFTER sheet animation so WKWebView can't reclaim during slide-in.
            editorVC?.dismissKeyboard()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        default: break
        }
        // Mark the document dirty for any command that modifies content.
        // Pure view/navigation commands are excluded so browsing slides or
        // adjusting zoom does not arm the Discard alert unnecessarily.
        let isViewCmd = cmd == "zoom-in" || cmd == "zoom-out"
            || cmd == "slide-prev" || cmd == "slide-next"
            || cmd.hasPrefix("slide-goto:") || cmd.hasPrefix("word-page-")
            || cmd == "ppt-present" || cmd == "ppt-notes-toggle" || cmd == "print"
            || cmd == "save"
        if !isViewCmd { isDirty = true }

        switch cmd {
        case "insert-image":        showImagePicker       = true
        case "insert-link":         showLinkSheet          = true
        case "insert-comment":      showCommentSheet       = true
        case "insert-table":        showTableSheet         = true
        case "insert-chart":        showChartSheet         = true
        case "insert-shape":        showShapeSheet         = true
        case "insert-symbol":       showSymbolSheet        = true
        case "ppt-insert-textbox":  editorVC?.execEditorCommand(cmd)
        case "word-find-replace":   showFindReplaceSheet   = true
        case "word-font-picker", "excel-font-picker", "ppt-font-picker": showFontPickerSheet = true
        case "ppt-transition-picker": showTransitionSheet = true
        case "print":               editorVC?.printDocument()
        default:                    editorVC?.execEditorCommand(cmd)
        }
    }

    // MARK: - Image insertion

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        defer { imagePickerItem = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }

        // Resize aggressively for Word (memory is tighter than Excel/PPT in WKWebView).
        // Max 1200px / 400 KB for Word; 1600px / 600 KB for Excel & PPT.
        let isWord = fileKind == .word
        let maxPx: CGFloat = isWord ? 1200 : 1600
        let targetBytes = isWord ? 400_000 : 600_000

        // Decode + resize + compress off the main thread — camera photos (12MP) can
        // take 500ms+ which visibly freezes the editor UI if done on MainActor.
        let imageData: Data = await Task.detached(priority: .userInitiated) {
            guard let src = UIImage(data: raw) else { return raw }
            let scale = min(maxPx / src.size.width, maxPx / src.size.height, 1.0)
            let size  = CGSize(width: (src.size.width * scale).rounded(),
                               height: (src.size.height * scale).rounded())
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: fmt)
                .image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
            var q: CGFloat = 0.75
            var out = resized.jpegData(compressionQuality: q) ?? raw
            while out.count > targetBytes && q > 0.30 {
                q -= 0.10
                out = resized.jpegData(compressionQuality: q) ?? out
            }
            return out
        }.value

        editorVC?.insertImage(data: imageData, mimeType: "image/jpeg")
    }

    // MARK: - Ready / network

    private func handleReady() {
        UserDefaults.standard.set(true, forKey: kCacheReadyKey)
    }

    @MainActor
    private func checkNetworkOnFirstLaunch() async {
        guard !UserDefaults.standard.bool(forKey: kCacheReadyKey) else { return }
        let isOnline = await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
        if !isOnline {
            errorMessage = "An internet connection is required to download the editor engine (~86 MB). After downloading once, editing works fully offline."
        }
    }

    // MARK: - Bottom strip (slide strip for PPT, sheet strip for Excel)

    @ViewBuilder
    private var bottomStrip: some View {
        if fileKind == .ppt {
            PPTSlideStrip(
                current: slideProgress.current,
                total: slideProgress.total,
                thumbnailVersion: thumbnailVersion,
                thumbnails: slideThumbnails,
                accent: OfficeEditorView.pptAccent,
                onTap: { num in handleCommand("slide-goto:\(num)") }
            ).equatable()
        } else if fileKind == .excel {
            sheetStrip
        }
    }

    // MARK: - PPT slide strip

    static let pptAccent = Color(red: 0.84, green: 0.22, blue: 0.18)

    // MARK: - Excel sheet strip

    /// Horizontal sheet tab strip below the Excel canvas.
    /// Shows all sheet names; active tab is highlighted. Tap to navigate, long-press for rename/delete.
    /// A "+" button at the leading end adds a new sheet.
    private var sheetStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Add sheet button
                    Button {
                        handleCommand("sheet-add")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add sheet")

                    Divider().frame(height: 20)

                    ForEach(Array(sheetNames.enumerated()), id: \.offset) { index, name in
                        let isActive = index == activeSheetIndex
                        Text(name)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.accentColor : .primary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.accentColor.opacity(0.12))
                                    }
                                }
                                .padding(.horizontal, 4)
                            )
                            .overlay(alignment: .bottom) {
                                if isActive {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                        .padding(.horizontal, 8)
                                }
                            }
                            // Single-tap → switch sheet; long-press context menu → Rename/Delete
                            .onTapGesture(count: 1) {
                                handleCommand("sheet-goto:\(index)")
                            }
                            .contextMenu {
                                Button("Rename") {
                                    handleCommand("sheet-rename")
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    handleCommand("sheet-delete")
                                }
                            }
                            .accessibilityLabel(name)
                            .accessibilityHint(isActive ? "Active sheet. Double-tap to rename." : "Tap to switch. Double-tap to rename.")
                            .id(index)
                    }

                    Spacer().frame(width: 8)
                }
                .padding(.leading, 4)
            }
            .frame(height: 44)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .onChange(of: activeSheetIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    // MARK: - Nav pill (Word + Excel)

    @ToolbarContentBuilder
    private var editorNavPill: some ToolbarContent {
        if fileKind == .word || fileKind == .excel || fileKind == .ppt {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    if fileKind == .ppt {
                        // PPT has no tab-bar trailing zoom, so keep it here.
                        // PPT's auto-fit APIs (asc_setZoomType, zoomFitToPage) are known to
                        // blank the canvas on this ONLYOFFICE build; asc_setZoom(current±10)
                        // avoids that path, so manual step zoom is the safe approach.
                        pillIconBtn("minus.magnifyingglass", cmd: "zoom-out", label: "Zoom out")
                        pillIconBtn("plus.magnifyingglass",  cmd: "zoom-in",  label: "Zoom in")
                        ShareLink(item: ref.url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Share")
                    } else {
                        // Word/Excel: zoom already lives in the tab-bar trailing area.
                        pillIconBtn("printer",    cmd: "print",          label: "Print")
                        Spacer().frame(width: 6)
                    }
                    Button {
                        if ref.kind.isOnlyOfficeEditable {
                            // Dismiss WKWebView keyboard before showing status picker sheet.
                            // Without this, the sheet presentation races with keyboard
                            // dismiss animation → garbled layout (keyboard + sheet overlap).
                            editorVC?.dismissKeyboard()
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                            )
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                NotificationCenter.default.post(name: .editorDoneRequested, object: nil)
                            }
                        } else {
                            // PDF / other: save then close (no status picker).
                            NotificationCenter.default.post(name: .editorSaveRequested, object: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                NotificationCenter.default.post(name: .editorDoneRequested, object: nil)
                            }
                        }
                    } label: {
                        Text("Done").fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func pillIconBtn(_ icon: String, cmd: String, label: String) -> some View {
        Button { handleCommand(cmd) } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Save / error

    private var saveBadge: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding([.top, .trailing], 12)
    }

    private func handleSave(data: Data, fileName: String) {
        Task {
            let dest = ref.url
            let accessing = dest.startAccessingSecurityScopedResource()
            defer { if accessing { dest.stopAccessingSecurityScopedResource() } }

            var writeError: Error?
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            coordinator.coordinate(
                writingItemAt: dest, options: .forReplacing,
                error: &coordError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }

            let finalError = writeError ?? coordError
            if let err = finalError {
                await MainActor.run {
                    errorMessage = "Could not save \"\(fileName)\": \(err.localizedDescription)"
                }
            } else {
                await MainActor.run {
                    saveCount += 1

                }
            }
        }
    }

    private func handleError(_ message: String) {
        if message.contains("editor engine could not load") {
            UserDefaults.standard.set(false, forKey: kCacheReadyKey)
        }
        Task { @MainActor in errorMessage = message }
    }
}

// MARK: - PPT slide strip

/// Isolated slide thumbnail strip.
///
/// Conforms to `Equatable` with a custom `==` that ignores the `onTap` closure
/// (closures aren't Equatable) and skips deep-comparing the `thumbnails` dictionary
/// (UIImage isn't Equatable). Instead it uses `thumbnailVersion` — a counter
/// incremented each time a new thumbnail arrives — to detect real changes.
/// Combined with `.equatable()` at the call site, SwiftUI skips `body` entirely
/// whenever `current`, `total`, and `thumbnailVersion` are all unchanged, preventing
/// unrelated @State flips in OfficeEditorView (isDirty, font names, etc.) from
/// causing the strip to redraw.
private struct PPTSlideStrip: View, Equatable {
    let current: Int
    let total: Int
    let thumbnailVersion: Int
    let thumbnails: [Int: UIImage]
    let accent: Color
    let onTap: (Int) -> Void

    static func == (lhs: PPTSlideStrip, rhs: PPTSlideStrip) -> Bool {
        lhs.current == rhs.current &&
        lhs.total == rhs.total &&
        lhs.thumbnailVersion == rhs.thumbnailVersion
        // accent is a static constant — never changes
        // onTap and thumbnails are excluded: closure non-Equatable; UIImage non-Equatable
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...max(1, total), id: \.self) { num in
                        let isCurrent = num == current
                        Button { onTap(num) } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let thumb = thumbnails[num] {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 54)
                                        .clipped()
                                        .cornerRadius(5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(
                                                    isCurrent ? accent : Color.secondary.opacity(0.25),
                                                    lineWidth: isCurrent ? 2.5 : 1
                                                )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                        .frame(width: 96, height: 54)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(
                                                    isCurrent ? accent : Color.secondary.opacity(0.25),
                                                    lineWidth: isCurrent ? 2.5 : 1
                                                )
                                        )
                                }
                                Text("\(num)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        isCurrent ? accent : Color.secondary.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 3)
                                    )
                                    .padding(4)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(num)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 74)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .onChange(of: current) { _, curr in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(curr, anchor: .center)
                }
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable

private struct _OfficeWebView: UIViewControllerRepresentable {
    let ref: DocumentRef
    let onFileSaved: (Data, String) -> Void
    let onError: (String) -> Void
    let onReady: () -> Void
    let onDirtyChange: (Bool) -> Void
    var onInteraction: () -> Void = {}
    let onVCReady: (OfficeEditorViewController) -> Void
    let onFilterRequest: ([NativeFilterItem]) -> Void
    let onSlideChange: (Int, Int) -> Void
    let onSlideThumbnail: (Int, Data) -> Void
    var onWordPageChange: (Int, Int) -> Void = { _, _ in }
    let onSheetListChange: ([String], Int) -> Void
    let onExcelFontChange: (String) -> Void
    let onWordFontChange:  (String) -> Void
    let onPPTFontChange:   (String) -> Void
    var onPPTZoomReady: () -> Void = {}
    var onDocSaved: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        vc.onReady = { Task { @MainActor in onReady() } }
        vc.onDirtyChange = { dirty in Task { @MainActor in onDirtyChange(dirty) } }
        vc.onInteraction = { Task { @MainActor in onInteraction() } }
        vc.onFilterRequest = { items in Task { @MainActor in onFilterRequest(items) } }
        vc.onSlideChange = { c, t in Task { @MainActor in onSlideChange(c, t) } }
        vc.onSlideThumbnail = { num, data in Task { @MainActor in onSlideThumbnail(num, data) } }
        vc.onWordPageChange = { c, t in Task { @MainActor in onWordPageChange(c, t) } }
        vc.onSheetListChange = { names, idx in Task { @MainActor in onSheetListChange(names, idx) } }
        vc.onExcelFontChange = { name in Task { @MainActor in onExcelFontChange(name) } }
        vc.onWordFontChange  = { name in Task { @MainActor in onWordFontChange(name)  } }
        vc.onPPTFontChange   = { name in Task { @MainActor in onPPTFontChange(name)   } }
        vc.onPPTZoomReady    = { Task { @MainActor in onPPTZoomReady() } }
        vc.onDocSaved        = { Task { @MainActor in onDocSaved() } }
        vc.openFile(at: ref.url)
        Task { @MainActor in onVCReady(vc) }
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}

// MARK: - Slide Transition Sheet

private struct SlideTransitionSheet: View {
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: Int? = nil

    private struct Transition {
        let name: String
        let icon: String
        let type: Int
    }

    private let transitions: [Transition] = [
        .init(name: "None",    icon: "slash.circle",                         type: 0),
        .init(name: "Fade",    icon: "circle.dotted",                        type: 1),
        .init(name: "Push",    icon: "arrow.right.square",                   type: 2),
        .init(name: "Wipe",    icon: "rectangle.leadinghalf.filled",         type: 3),
        .init(name: "Split",   icon: "arrow.left.and.line.vertical.and.arrow.right", type: 4),
        .init(name: "Cover",   icon: "square.on.square",                     type: 6),
        .init(name: "Zoom",    icon: "arrow.up.left.and.arrow.down.right",   type: 8),
        .init(name: "Random",  icon: "shuffle",                              type: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Slide Transition")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.md)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.sm), count: 4),
                      spacing: DSSpacing.sm) {
                ForEach(transitions, id: \.type) { t in
                    let isSelected = selectedType == t.type
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selectedType = t.type }
                        onSelect(t.type)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                    } label: {
                        VStack(spacing: DSSpacing.xs) {
                            ZStack {
                                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                                    .fill(isSelected ? Color.dsBrandPrimarySubtle : Color.dsBackgroundSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault,
                                                lineWidth: isSelected ? 2 : 1
                                            )
                                    )
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.dsBrandPrimary)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Image(systemName: t.icon)
                                        .font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(Color.dsBrandPrimary)
                                }
                            }
                            .frame(height: 60)

                            Text(t.name)
                                .font(DSFont.caption)
                                .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextSecondary)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.lg)

            Text("Plays when presenting slides")
                .font(DSFont.caption)
                .foregroundStyle(Color.dsTextTertiary)
                .padding(.top, DSSpacing.md)

            Spacer(minLength: 0)
        }
    }
}
