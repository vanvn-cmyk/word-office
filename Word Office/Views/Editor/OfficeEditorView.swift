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

    @State private var errorMessage: String? = nil
    @State private var saveCount = 0
    @State private var isDirty = false
    @State private var editorVC: OfficeEditorViewController?
    @State private var slideProgress: (current: Int, total: Int) = (1, 1)
    @State private var slideThumbnails: [Int: UIImage] = [:]

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
                        onCommand: handleCommand
                    )

                    _OfficeWebView(
                        ref: ref,
                        onFileSaved: handleSave,
                        onError: handleError,
                        onReady: handleReady,
                        onDirtyChange: { isDirty = $0 },
                        onVCReady: { editorVC = $0 },
                        onFilterRequest: { items in
                            filterItems = items
                            showFilterSheet = true
                        },
                        onSlideChange: { c, t in slideProgress = (c, t) },
                        onSlideThumbnail: { num, data in
                            if let img = UIImage(data: data) {
                                slideThumbnails[num] = img
                            }
                        }
                    )

                    if fileKind == .ppt {
                        slideStrip
                    }

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
                // Native hyperlink insert sheet — insertHyperlink fires in onDismiss so the
                // WKWebView has fully regained focus before JS is evaluated.
                .sheet(isPresented: $showLinkSheet, onDismiss: {
                    if let link = pendingLink {
                        editorVC?.insertHyperlink(url: link.url, displayText: link.text)
                        pendingLink = nil
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
                        editorVC?.insertTable(rows: t.rows, cols: t.cols)
                        pendingTable = nil
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
        switch cmd {
        case "insert-image":        showImagePicker       = true
        case "insert-link":         showLinkSheet          = true
        case "insert-comment":      showCommentSheet       = true
        case "insert-table":        showTableSheet         = true
        case "insert-chart":        showChartSheet         = true
        case "insert-shape":        showShapeSheet         = true
        case "insert-symbol":       showSymbolSheet        = true
        // ppt-insert-textbox: _insertTextBox uses StartAddShape('textRect') + mouse simulation
        // to draw the box, then auto-double-clicks to enter text-edit mode immediately.
        // Direct APIs (asc_insertTextBox, asc_setShapePreset) crash on iOS.
        case "ppt-insert-textbox":  editorVC?.insertTextBox()
        case "word-find-replace":   showFindReplaceSheet   = true
        case "word-font-picker":    showFontPickerSheet    = true
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

    // MARK: - PPT slide strip

    private static let pptAccent = Color(red: 0.84, green: 0.22, blue: 0.18)

    /// Horizontal thumbnail strip below the PPT canvas.
    /// Each card is a 16:9 mini slide placeholder with a slide-number badge.
    /// Active card gets the PPT red border; strip auto-scrolls to keep it visible.
    private var slideStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...max(1, slideProgress.total), id: \.self) { num in
                        let isCurrent = num == slideProgress.current
                        Button { handleCommand("slide-goto:\(num)") } label: {
                            ZStack(alignment: .bottomTrailing) {
                                // 16:9 slide card — show real thumbnail if captured, else placeholder
                                if let thumb = slideThumbnails[num] {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 54)
                                        .clipped()
                                        .cornerRadius(5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(
                                                    isCurrent ? Self.pptAccent : Color.secondary.opacity(0.25),
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
                                                    isCurrent ? Self.pptAccent : Color.secondary.opacity(0.25),
                                                    lineWidth: isCurrent ? 2.5 : 1
                                                )
                                        )
                                }
                                // Number badge bottom-right
                                Text("\(num)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        isCurrent ? Self.pptAccent : Color.secondary.opacity(0.55),
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
            .onChange(of: slideProgress.current) { _, current in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(current, anchor: .center)
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
                    pillIconBtn("arrow.uturn.backward", cmd: "undo", label: "Undo")
                    pillIconBtn("arrow.uturn.forward",  cmd: "redo", label: "Redo")
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
                        pillIconBtn("text.bubble", cmd: "insert-comment", label: "Comment")
                    }
                    Button {
                        NotificationCenter.default.post(name: .editorSaveRequested, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
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

// MARK: - UIViewControllerRepresentable

private struct _OfficeWebView: UIViewControllerRepresentable {
    let ref: DocumentRef
    let onFileSaved: (Data, String) -> Void
    let onError: (String) -> Void
    let onReady: () -> Void
    let onDirtyChange: (Bool) -> Void
    let onVCReady: (OfficeEditorViewController) -> Void
    let onFilterRequest: ([NativeFilterItem]) -> Void
    let onSlideChange: (Int, Int) -> Void
    let onSlideThumbnail: (Int, Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> OfficeEditorViewController {
        let vc = OfficeEditorViewController()
        vc.onFileSaved = onFileSaved
        vc.onError = { msg in Task { @MainActor in onError(msg) } }
        vc.onReady = { Task { @MainActor in onReady() } }
        vc.onDirtyChange = { dirty in Task { @MainActor in onDirtyChange(dirty) } }
        vc.onFilterRequest = { items in Task { @MainActor in onFilterRequest(items) } }
        vc.onSlideChange = { c, t in Task { @MainActor in onSlideChange(c, t) } }
        vc.onSlideThumbnail = { num, data in Task { @MainActor in onSlideThumbnail(num, data) } }
        vc.openFile(at: ref.url)
        Task { @MainActor in onVCReady(vc) }
        return vc
    }

    func updateUIViewController(_ vc: OfficeEditorViewController, context: Context) {}

    final class Coordinator {}
}
