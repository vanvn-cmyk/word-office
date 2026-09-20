# Phase 0 (MVP) — Logic xử lý code cho từng tính năng (v2 — cập nhật theo MVP cuối cùng, 27/08/2026)

**File riêng, không đè lên `Phase0-Implementation-Logic.md` gốc** — bản gốc vẫn giữ nguyên để dùng lại. File này phản ánh đúng scope **MVP 11 hạng mục cuối cùng** trong `product-strategy-master.md` — đã qua nhiều vòng đổi ý trong ngày 27/08/2026 (xem `product-strategy-changelog.md` nếu cần lịch sử đầy đủ). **Core loop MVP thật là "Tủ hồ sơ" (habit loop dựa trên Zeigarnik effect), KHÔNG phải AI** — MVP hiện **hoàn toàn không có tính năng AI nào**, cả AI tóm tắt lẫn AI tạo văn bản đều đẩy ra Phase sau.

## Khác biệt so với bản gốc (`Phase0-Implementation-Logic.md`)

| Thay đổi | Chi tiết |
|---|---|
| **Ra khỏi MVP → Phase 1** | Autosave/crash-recovery (§2 bản gốc), Apple Pencil (§6.2 bản gốc), Compress (§8.1/8.2 phần compress bản gốc) — logic 3 mục này giữ nguyên trong file gốc, không cần viết lại. **AI tóm tắt tài liệu** — từng vào MVP rồi bị đẩy tạm lại về Phase 1 (27/08, quyết định lại) — logic vẫn giữ nguyên, chuyển thành **Phụ lục A** cuối file |
| **Ra khỏi MVP → Phase 2** | **AI tạo văn bản từ mô tả (chat-to-document)** — không còn là core loop MVP nữa. Logic đã viết đầy đủ ở **Phụ lục B** cuối file (viết khi tính năng còn ở MVP) — giữ lại làm tài liệu tham khảo cho Phase 2, công sức thiết kế (DocumentBuilder, clause library, backend proxy) vẫn dùng lại được nguyên khi tới lúc |
| **Vào MVP, mới so với bản gốc** | **Core loop "Tủ hồ sơ"** (trang chủ tủ hồ sơ + trạng thái tài liệu, tự đặt nhắc trong app, bước cấp quyền 1 lần cho File Provider) — logic mới ở mục 10, chưa từng có ở bản gốc vì đây là ý mới phát sinh sau — đây là MVP item mới duy nhất, không phải AI |
| **Không đổi** | Core editing, layout adaptive, Files provider + AirPrint, iPad multi-pane (trừ Pencil), OCR, Merge/Split (trừ Compress), Note/comment, E-signature + watermark — copy nguyên logic từ bản gốc, chỉ đánh số lại |
| **Viết lại (mục 4, Add file)** | Bản gốc mô tả "Add file" như 1 nút chọn file thủ công. **Viết lại thành luồng chính: cấp quyền 1 lần cho 1 thư mục → tự động quét/import toàn bộ tài liệu có sẵn**, mở app là dùng ngay — nút chọn file thủ công cũ lùi thành luồng phụ (4.5). Đây chính là cơ chế tạo Aha moment cho core loop mục 10 |

Ký hiệu giữ nguyên: `[SDK]` = có sẵn trong SDK license, `[NATIVE]` = framework Apple có sẵn, `[TỰ BUILD]` = không có ở đâu cả, phải viết logic riêng.

---

## 1. Core editing DOCX/XLSX/PPTX + xem/convert PDF `[SDK]`

**Kiến trúc**: 1 lớp `DocumentSessionManager` bọc quanh SDK, không để UI gọi thẳng SDK — để sau này đổi SDK (nếu cần) không phải sửa toàn bộ call site (bài học từ Word Office: mọi thứ đi qua `iKameSDKCore`, không gọi Adjust/Firebase trực tiếp).

```
DocumentSessionManager
├── init(licenseKey:) → gọi 1 lần ở app launch, trước khi mở bất kỳ file nào
├── openDocument(url: URL) -> DocumentSession
│     ├── xác định file type từ UTI (không tin đuôi file — .docx có thể bị đổi tên)
│     ├── route theo type:
│     │     .wordprocessing → SDK.openWordSession(url)
│     │     .spreadsheet    → SDK.openSheetSession(url)
│     │     .presentation   → SDK.openSlideSession(url)
│     │     .pdf            → SDK.openPDFSession(url)   ← module riêng, không qua Word wrapper (bài học: Word Office gọi PDF module thẳng, không lồng qua sodk)
│     └── trả về DocumentSession (wrap session gốc của SDK + thêm state riêng: dirty flag, lastSavedAt, autosaveTimer)
├── presentViewController(for: DocumentSession) -> UIViewController
│     └── present view controller "all-in-one" của SDK — nhưng bọc trong 1 UIHostingController/container riêng
│         để sau này thay UI mặc định bằng UI tự build (giống hướng A1 làm) mà không đổi lớp session
├── **newDocument(from: GeneratedContent) -> DocumentSession** ← điểm nối với Phụ lục B (AI tạo văn bản, Phase 2)
│         tạo session MỚI (chưa gắn file thật) từ nội dung AI sinh ra — dùng CHUNG interface DocumentSession
│         với file mở từ đĩa, để mọi logic edit/save/export/sign phía dưới không cần biết tài liệu đến từ đâu
└── closeDocument(_ session:) → flush autosave, release session, xoá temp file nếu convert
```

**Convert PDF (từ Word/Excel/PPT sang PDF)**: hầu hết SDK loại này có API `exportAs(.pdf)` trên session đã mở — không cần thêm engine riêng. Nếu SDK không hỗ trợ convert Excel/PPT→PDF trực tiếp, fallback: render từng trang qua `UIPrintPageRenderer`/`drawRect` vào `UIGraphicsPDFRenderer` (native, không cần SDK).

**Điểm cần chú ý**: cả 2 đối thủ hỗ trợ .hwp/.hwpx (Hancom) miễn phí ở tầng SDK — kiểm tra SDK bạn chọn có cùng UTI này không, nếu có thì thêm vào danh sách `UTImportedTypeDeclarations` gần như miễn phí (thêm UTI, không thêm logic).

---

## 2. Kiến trúc layout adaptive (size classes / NavigationSplitView) `[NATIVE]`

**Logic chính**: 1 `RootView` duy nhất, KHÔNG có 2 codebase iPhone/iPad riêng — chọn layout theo `horizontalSizeClass`:

```swift
struct RootView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        if sizeClass == .regular {          // iPad (hầu hết context), iPhone Pro Max landscape, iPhone Fold khi mở
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()               // Folder/Recent/Cloud sources
            } content: {
                DocumentListView()
            } detail: {
                DocumentEditorView()
            }
        } else {                            // iPhone compact, HOẶC iPad đang ở Split View/Slide Over hẹp
            NavigationStack {
                DocumentListView()
                    .navigationDestination(for: Document.self) { DocumentEditorView(doc: $0) }
            }
        }
    }
}
```

**Đây chính là logic chạy trên iPad, không phải code iPhone "hy vọng chạy được"** — `sizeClass == .regular` là nhánh mà iPad rơi vào ở hầu hết trường hợp, nên `NavigationSplitView` mới là UI thật hiển thị trên iPad; nhánh `NavigationStack` chỉ dành cho iPhone.

**2 điều cần biết trước khi test trên iPad thật, để không nhầm là bug:**
- **iPad không phải lúc nào cũng `.regular`** — khi ở multitasking (Split View chia đôi màn hình với app khác, hoặc Slide Over), `horizontalSizeClass` của app có thể tụt về `.compact` dù đang chạy trên iPad. Code trên đã tự fallback đúng sang `NavigationStack` — đây là hành vi đúng, không phải bug.
- **iPad mini vẫn là `.regular`** ở hầu hết orientation — size class không tính theo kích thước màn hình vật lý, mà Apple gán theo thiết bị + context, nên không cần logic riêng cho iPad mini.

**Vì sao đây là "đầu tư không mất gì"**: `NavigationSplitView` tự co về 1-cột khi `sizeClass` là `.compact` — không cần viết logic riêng cho Fold, chỉ cần đảm bảo state (document đang mở, selection) sống ở 1 nguồn chung (`@Observable` view model ở `RootView`, không sở hữu bởi view con) để khi size class đổi giữa chừng (xoay ngang/dọc, mở/gập Fold, vào/ra Split View) không mất state.

**Điểm cần chú ý**: đừng để `DocumentSessionManager` (mục 1) sống trong view — sống ở tầng `RootView`/App-level singleton, để đổi layout không kill session đang mở.

---

## 3. Files app provider `[TỰ BUILD]` + AirPrint `[SDK/NATIVE]`

### Files app provider — **0/2 đối thủ có, cơ hội thật nhưng chi phí kỹ thuật cao hơn các mục khác**

Đây không phải "Add file" (mở file từ Files app vào app bạn) — đây là làm cho app của bạn **xuất hiện như 1 vị trí duyệt được** trong chính app Files, giống Dropbox/iCloud. Files app không nói chuyện trực tiếp với app chính của bạn — nó nói chuyện với 1 **target riêng biệt** (`File Provider Extension`) mà hệ điều hành tự khởi động thành process riêng khi cần, kể cả lúc app chính đang đóng.

### 3.1 — Bộ khung extension (target riêng, `com.apple.fileprovider-nonui`)

```
FileProviderExtension (process riêng, sandbox riêng — KHÔNG share memory với app chính)
└── NSFileProviderReplicatedExtension  ← protocol bắt buộc implement, Files app gọi các hàm này
      ├── enumerator(for: containerItemIdentifier) -> NSFileProviderEnumerator
      │     Files app gọi hàm này khi user mở/cuộn vào 1 thư mục — trả về danh sách item (file/folder) trong đó
      ├── item(for: identifier) -> NSFileProviderItem
      │     metadata 1 item cụ thể: tên, size, ngày sửa, loại (docx/pdf...), icon, có phải folder không
      ├── fetchContents(for: identifier, completionHandler:)
      │     Files app gọi khi user THỰC SỰ mở file đó (preview/share/mở app khác) — lúc này mới đọc nội dung thật
      ├── createItem / modifyItem / deleteItem
      │     user thao tác TRONG Files app (đổi tên, xoá, kéo file vào) → extension phải ghi thay đổi đó
      │     vào cùng 1 nguồn dữ liệu mà app chính đang đọc — nếu không app chính mở lên sẽ không thấy thay đổi
      └── fetchThumbnails(for: identifiers, completionHandler:)
            Files app hiển thị lưới ảnh — cần trả thumbnail nhanh, KHÔNG mở full document để render (quá chậm với PDF/PPTX lớn)
```

### 3.2 — Nguồn dữ liệu dùng chung (bài toán 2 process không share memory)

App chính và extension là **2 tiến trình khác nhau hoàn toàn** — không gọi hàm/biến chéo nhau được. Mọi thứ phải đi qua đĩa, qua 1 App Group container.

*(Chi tiết đầy đủ mục này giữ nguyên như §4 bản gốc — không đổi.)*

### 3.3 — AirPrint `[SDK/NATIVE]`

Cả 2 đối thủ gọi thẳng `ARDKPrintPageRenderer`/`UIPrintPageRenderer` — nằm trong nhóm core mà cả 2 app cùng gọi, chi phí kỹ thuật thấp vì API iOS có sẵn.

---

## 4. Add file — Local + iCloud `[NATIVE]`, gần như miễn phí

**Luồng chính KHÔNG phải "user tự bấm Add từng file"** — đó chỉ là luồng phụ (4.5). Luồng chính: **app xin quyền 1 lần, rồi tự quét/import toàn bộ tài liệu có sẵn** — user mở app lên là đã thấy tủ hồ sơ đầy, dùng ngay, không phải thao tác gì thêm. Đây chính là bước tạo ra Aha moment của core loop MVP (mục 10) — không có bước cấp quyền này thì "Tủ hồ sơ" ngày đầu vẫn trống trơn.

### 4.1 — Luồng chính: cấp quyền 1 lần → tự động quét & import

```swift
// Bước 1 — xin quyền, CHỈ 1 LẦN (thường ở onboarding hoặc lần đầu mở app)
let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
picker.delegate = self
present(picker, animated: true)

func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let folderURL = urls.first else { return }
    guard folderURL.startAccessingSecurityScopedResource() else { return }
    let bookmark = try? folderURL.bookmarkData(options: .minimalBookmark)
    saveBookmarkPermanently(bookmark)   // UserDefaults/Keychain — dùng lại mỗi lần app mở, không hỏi lại
    folderURL.stopAccessingSecurityScopedResource()
    scanAndImportAll(from: folderURL)   // Bước 2, chạy ngay sau khi có quyền
}

// Bước 2 — quét toàn bộ thư mục đã cấp quyền, import những gì đúng định dạng hỗ trợ
func scanAndImportAll(from folderURL: URL) {
    guard folderURL.startAccessingSecurityScopedResource() else { return }
    defer { folderURL.stopAccessingSecurityScopedResource() }
    let supported: Set<UTType> = [.docx, .xlsx, .pptx, .pdf, .hwp]
    let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
    let matches = (contents ?? []).filter { url in supported.contains(where: { $0.matches(url) }) }
    Task { await importBatch(matches) }   // xem 4.3 — xử lý lỗi từng file riêng
}

// Mỗi lần mở app sau đó: resolve lại bookmark, re-scan để bắt file mới thêm vào thư mục từ lần trước
func resolveBookmarkAndRescan() {
    guard let data = loadSavedBookmark() else { return }   // chưa từng cấp quyền → hiện CTA "Cấp quyền" (xem mục 10.3)
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
        return showReauthorizeCTA()   // bookmark hỏng/bị revoke — không im lặng để tủ hồ sơ trống
    }
    if isStale { /* refresh bookmark, vẫn dùng được url lần này */ }
    scanAndImportAll(from: url)
}
```

**Điểm cần chú ý**: đây KHÔNG phải "Add file" theo nghĩa cổ điển (chọn từng file) — là chọn **1 thư mục gốc**, giữ quyền truy cập dài hạn qua bookmark, rồi tự quét lại mỗi lần app mở để bắt cả file mới user thêm vào thư mục đó sau này (qua Files app, AirDrop lưu vào đúng thư mục...) mà không cần mở lại app để "add" thủ công.

### 4.2 — iCloud Drive: file quét được không đồng nghĩa file đã có trên máy

Khi quét thấy 1 file từ iCloud Drive, file đó **có thể chỉ là placeholder** (chưa tải nội dung thật về máy). Import thẳng placeholder này vào sandbox sẽ ra file 0 byte hoặc lỗi khi SDK mở.

```swift
func importAndCopyToLocalStorage(_ url: URL) {
    var isDownloaded = false
    if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
        isDownloaded = values.ubiquitousItemDownloadingStatus == .current
    }
    if !isDownloaded {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        waitForDownload(url) { completedURL in copyToSandbox(completedURL) }
    } else {
        copyToSandbox(url)
    }
}
```

**Cách chờ tải xong đúng cách**: dùng `NSMetadataQuery` theo dõi `NSMetadataUbiquitousItemPercentDownloadedKey`/`NSMetadataUbiquitousItemDownloadingStatusKey` thay vì poll thủ công bằng timer. **Với quét tự động (4.1)**: không chờ tải hết mọi placeholder ngay lúc quét (chậm nếu thư mục nhiều file) — hiện tài liệu trong tủ hồ sơ ngay với trạng thái "Đang tải từ iCloud", tải xong thì cập nhật, không block toàn bộ danh sách chờ 1 file chậm nhất.

### 4.3 — Import nhiều file cùng lúc: xử lý lỗi từng file riêng, không fail cả batch

```swift
func importBatch(_ urls: [URL]) async {
    var succeeded: [Document] = []
    var failed: [(URL, Error)] = []
    for url in urls {
        do { succeeded.append(try await importSingle(url)) }
        catch { failed.append((url, error)) }
    }
    if !failed.isEmpty { showBatchResultBanner(succeeded: succeeded.count, failed: failed) }
}
```

**Với quét tự động (4.1)**: banner lỗi chỉ hiện nếu số file lỗi đáng kể — quét lần đầu mà spam banner lỗi cho từng file linh tinh (file tạm, file khoá bằng app khác...) làm hỏng đúng cảm giác "mở app là dùng ngay" mà cơ chế này nhắm tới.

### 4.4 — File trùng tên

Không tự động ghi đè khi trùng tên — tự thêm hậu tố "(2)", "(3)"... theo tên còn trống gần nhất. Áp dụng cả khi quét tự động lẫn add thủ công (4.5).

**Điểm cần chú ý**: import Local (`asCopy: true`) không có vấn đề placeholder như iCloud — đừng áp dụng chung 1 luồng chờ-tải cho cả 2 nguồn, sẽ làm quét Local chậm vô cớ.

### 4.5 — Add file thủ công (bổ sung, KHÔNG phải luồng chính)

Vẫn cần giữ 1 nút "Add file" thủ công cho trường hợp file nằm **ngoài** thư mục đã cấp quyền ở 4.1 (vd nhận qua Mail/Zalo rồi Share ra, hoặc user chủ động chọn từ nơi khác):

```swift
let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.docx, .xlsx, .pptx, .pdf, .hwp])
picker.allowsMultipleSelection = true
picker.delegate = self
present(picker, animated: true)

func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    for url in urls {
        guard url.startAccessingSecurityScopedResource() else { continue }
        defer { url.stopAccessingSecurityScopedResource() }
        documentManager.importAndCopyToLocalStorage(url)
    }
}
```

**Điểm cần chú ý**: phải gọi `startAccessingSecurityScopedResource()` trước khi đọc file, và nên **copy vào sandbox riêng** thay vì giữ security-scoped bookmark dài hạn cho từng file lẻ — khác với 4.1 (giữ bookmark cho cả 1 thư mục là hợp lý, giữ bookmark cho hàng chục file lẻ rời rạc thì không, dễ rối và dễ bị revoke lặt vặt).

---

## 5. iPad multi-pane UI thật + keyboard shortcuts `[NATIVE + SDK]`

> **Apple Pencil đã chuyển sang Phase 1** (logic vẽ tay/Scribble/double-tap giữ nguyên ở §6.2 bản gốc, dùng lại khi tới Phase 1, không cần viết lại).

### 5.1 — Multi-pane bên trong editor (không chỉ ở app-shell)

Đã có kiến trúc app-shell ở mục 2 (`NavigationSplitView` — sidebar/list/detail). Phần riêng ở đây là **multi-pane bên trong chính màn hình editor** — muốn có outline/TOC panel + trang đang sửa hiện song song trên iPad, không dùng nguyên view-controller "all-in-one" của SDK, phải tự bọc lại:

```swift
struct DocumentEditorSplitView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var outlineVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sizeClass == .regular && outlineVisible {
                OutlineSidebar(entries: session.tocEntries)
                    .frame(width: 260)
                Divider()
            }
            SDKEditorViewControllerWrapper(session: session)   // UIViewControllerRepresentable, KHÔNG present full-screen
        }
    }
}
```

**Điểm cần chú ý**: nhúng view controller của SDK qua `UIViewControllerRepresentable` (không `present()`) để nó chia sẻ không gian màn hình với outline panel — 1 số SDK khoá cứng full-screen, phải hỏi vendor support trước khi cam kết hướng UI này.

### 5.2 — Keyboard shortcuts: routing, không tự implement lại hành vi

```swift
.keyboardShortcut("s", modifiers: .command)   // Save
.keyboardShortcut("b", modifiers: .command)   // Bold
.keyboardShortcut("f", modifiers: .command)   // Find
```

Map trực tiếp qua API editing command của SDK (`session.applyStyle(.bold)`) — không tự implement bold/italic, chỉ tự làm lớp routing phím → lệnh SDK.

**Điểm cần chú ý — xung đột với keyboard handling nội bộ của SDK**: nếu view controller của SDK tự bắt `Cmd+B`/`Cmd+F` bên trong nó, `UIKeyCommand` bạn định nghĩa ở tầng app có thể **không bao giờ được gọi tới**. Cách kiểm tra: log lại xem action có được trigger không khi SDK view đang là first responder; nếu không, **không định nghĩa lại** phím đó ở tầng app.

**Discoverability**: giữ phím tắt trùng chuẩn hệ thống (Cmd+S/B/I/U/F/Z) để tự động xuất hiện trong menu "giữ Cmd" trên iPad/Mac Catalyst.

### 5.3 — Trackpad/con trỏ chuột (Magic Keyboard)

Vì persona (mục 3, `product-strategy-master.md`) gồm nhóm dùng iPad Pro + Magic Keyboard thay laptop, cần đảm bảo `DocumentEditorView`/`OutlineSidebar` có hover state rõ ràng (`.hoverEffect(.highlight)` hoặc `UIPointerInteraction`) — thiếu phần này thì trải nghiệm dùng trackpad cảm giác vẫn như "app cảm ứng ép dùng chuột".

---

## 6. OCR — scan giấy thành văn bản `[NATIVE]`, KHÔNG có ở SDK (đã xác nhận quét 627 class)

### 6.1 — 3 nguồn input, không chỉ camera (bổ sung 2026-09-01)

Ban đầu chỉ định camera-scan trực tiếp — mở rộng theo yêu cầu user thành **3 nguồn input**, cùng đổ vào chung 1 pipeline OCR (§6.2-6.4):

1. **Camera scan giấy thật** — dùng document scanner có sẵn, không tự làm camera:

```swift
let scanner = VNDocumentCameraViewController()
scanner.delegate = self
present(scanner, animated: true)

func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                   didFinishWith scan: VNDocumentCameraScan) {
    for pageIndex in 0..<scan.pageCount {
        let image = scan.imageOfPage(at: pageIndex)
        ocrQueue.enqueue(image, pageIndex: pageIndex)
    }
}
```

**Điểm cần chú ý**: dùng `VNDocumentCameraViewController` thay vì tự làm camera capture như A1 đang làm (chỉ chụp ảnh thường qua `BSImagePicker` rồi ghép PDF, không có edge-detection) — vừa rẻ hơn vừa chất lượng nhận diện tốt hơn hẳn.

2. **Ảnh có sẵn trong Thư viện ảnh** (chụp viết tay, chụp văn bản đánh máy...) — `PHPickerViewController`, mỗi ảnh chọn ra `CGImage`, đổ thẳng vào cùng `ocrQueue` như trên. Không cần code nhận diện riêng — dùng chung `VisionTextRecognizer`, Vision tự xử lý cả chữ in lẫn chữ viết tay (độ chính xác chữ viết tay thấp hơn chữ in — vẫn phải qua bộ lọc confidence §6.4 như thường).

3. **File PDF có sẵn (dạng ảnh scan, không có lớp chữ số)** — vd PDF cũ scan từ máy photocopy, khác với PDF đã có sẵn chữ số (trường hợp đó dùng thẳng `PDFPage.string`, không cần OCR — xem §7.4 "PDF → Word"). Phải tự phát hiện trước khi quyết định nhánh xử lý:

```swift
func needsOCR(_ pdfPage: PDFPage) -> Bool {
    let text = pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    return text?.isEmpty ?? true   // không có lớp chữ → phải OCR
}

// nếu cần OCR: render trang ra ảnh rồi đổ vào đúng pipeline camera-scan ở trên
let image = pdfPage.thumbnail(of: targetSize, for: .mediaBox)
ocrQueue.enqueue(image, pageIndex: i)
```

**Điểm cần chú ý — dùng CHUNG 1 pipeline cho cả 3 nguồn**: không viết 3 luồng OCR riêng — camera/Photos/PDF-scan đều quy về cùng `[CGImage]` rồi gọi đúng `OCRViewModel.recognize()` đã có, khác nhau chỉ ở bước lấy `CGImage` ban đầu.

### 6.2 — Xử lý nền, không block UI khi scan nhiều trang

```
OCRQueue (background, giới hạn concurrency ~2-3 trang cùng lúc — Vision khá nặng CPU)
├── mỗi trang: VNRecognizeTextRequest(recognitionLevel: .accurate, usesLanguageCorrection: true)
├── mỗi trang xong → update progress UI
└── toàn bộ xong → build output (6.5)
```

### 6.3 — Ngôn ngữ nhận diện — dễ bị bỏ sót ở app nhắm nhiều thị trường

```swift
request.recognitionLanguages = ["vi-VN", "en-US"]   // KHÔNG để mặc định chỉ "en-US"
let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)
```

**Cách chọn**: mặc định theo ngôn ngữ hệ thống của user + cho phép chọn tay trong UI trước khi scan.

### 6.4 — Độ tin cậy (confidence) — không im lặng khi nhận diện sai

```swift
for observation in results as! [VNRecognizedTextObservation] {
    guard let candidate = observation.topCandidates(1).first else { continue }
    if candidate.confidence < 0.5 { lowConfidenceBlocks.append(observation) }
}
```

Im lặng coi như đúng 100% là nguồn lỗi phổ biến nhất của tính năng OCR.

### 6.5 — 2 dạng output (thứ tự ưu tiên đổi lại 2026-09-01 — user cần "sửa được" là yêu cầu chính, không phải chỉ tìm/copy)

**(a) File .docx sửa được `[TỰ BUILD]` — output CHÍNH, vào MVP** (không còn là "đắt, để Phase sau" — đã rẻ đi nhiều vì tái dùng đúng `DOCXCodec.write()` đã có cho Editor, giống hệt cách "PDF → Word" ở §7.4 làm):

```swift
let text = ocrResult.blocks.map(\.text).joined(separator: "\n")   // OCRResult.fullText đã có sẵn
try DOCXCodec.write(AttributedString(text), to: outputURL)
```

Giới hạn thật (nói rõ cho user, đừng để kỳ vọng sai): chỉ ra được **chữ thuần**, KHÔNG giữ layout/bảng/vị trí như bản gốc — giống đúng giới hạn của "PDF → Word" §7.4.

**(b) PDF "searchable" `[NATIVE]` — output PHỤ, tuỳ chọn thêm** (giữ nguyên hình ảnh gốc, chỉ cần chọn/tìm/copy được chữ, không sửa nội dung): vẽ text nhận diện được đè lên ảnh scan, invisible (render mode "không tô màu, không vẽ"), dùng PDFKit/CGPDFContext, hoàn toàn native. Hợp cho trường hợp cần giữ đúng hình ảnh gốc (vd hồ sơ pháp lý) mà vẫn tìm được chữ.

Cho user chọn xuất (a), (b), hay cả 2 sau khi OCR xong — không ép 1 trong 2.

**Điểm cộng cho positioning**: pipeline OCR chạy 100% on-device (Vision không gọi mạng) — khác hẳn nhóm AI ở Phụ lục A (AI tóm tắt, Phase 1) và Phụ lục B (AI tạo văn bản, Phase 2), cả 2 đều chắc chắn phải gọi cloud. Đáng nhấn mạnh sự khác biệt này rõ trong UI.

---

## 7. Merge / Split / Convert — Word/PDF/PPT/Image `[TỰ BUILD]` (Convert Office→PDF dùng `[SDK]`), phần lớn không có ở SDK lẫn 2 đối thủ

> **2026-09-01: bổ sung §7.4 Convert** (Office↔PDF, Image↔PDF) theo yêu cầu mở rộng scope — 4 chiều convert mới, tái dùng engine đã có sẵn (SDK `exportAs`, `DOCXCodec`, `PDFKit`, `UIGraphicsPDFRenderer`), không cần viết engine mới. Xem §7.4.

> **Compress đã chuyển sang Phase 1** (logic nén ảnh nhúng PDF/DOCX/PPTX giữ nguyên ở §8.1/8.2 phần compress trong bản gốc, dùng lại khi tới Phase 1). **2026-08-31**: 4 file stub Compress còn sót lại trong codebase từ bản scaffold gốc (`PDFCompressing.swift`, `OfficeCompressing.swift`, `PDFKitCompressor.swift`, `OOXMLMediaCompressor.swift`) đã bị xoá để khớp đúng quyết định này — không file/type nào implement Compress tồn tại trong MVP nữa, tạo lại khi tới Phase 1.

### 7.1 — PDF: rẻ nhất, dùng `PDFKit` (native, độc lập với SDK license)

```swift
// Merge
let merged = PDFDocument()
for doc in inputDocs {
    for i in 0..<doc.pageCount { merged.insert(doc.page(at: i)!, at: merged.pageCount) }
}

// Split (theo range hoặc mỗi N trang 1 file)
let part = PDFDocument()
for i in range { part.insert(original.page(at: i)!, at: part.pageCount) }
```

### 7.2 — DOCX/PPTX: không có PDFKit tương đương, phải thao tác trực tiếp cấu trúc file

File ZIP chứa XML (chuẩn OOXML) — dùng XML parser thật, không string-concat/regex.

```
docx/pptx = ZIP chứa:
  word/document.xml (hoặc ppt/slides/slideN.xml — PPTX mỗi slide 1 file XML riêng)
  word/media/*  (ảnh nhúng)
  [Content_Types].xml, _rels/*  ← khai báo quan hệ giữa các phần, PHẢI cập nhật đồng bộ

Thư viện dùng: ZIPFoundation (unzip/zip) + XMLDocument (Foundation native)
```

**Merge (Word)**: parse `document.xml` cả 2 file bằng XMLDocument, lấy node con của `<w:body>` trong file B (trừ `<w:sectPr>`), append vào cuối `<w:body>` của A, gộp `media/` (đổi tên tránh trùng), **sửa lại `r:id` reference** (bẫy phổ biến nhất — id trùng nhau giữa 2 file làm ảnh vỡ), update `[Content_Types].xml` nếu cần, re-zip đúng thứ tự entry.

**Merge (PowerPoint)**: copy `ppt/slides/slideN.xml` từ B sang A (đổi số thứ tự), update `ppt/presentation.xml` + `_rels`, và **copy luôn slideLayout/slideMaster liên quan** nếu B dùng layout khác A (thiếu bước này slide đúng nội dung nhưng sai theme/font hoàn toàn).

**Split**: ngược lại của merge, cộng thêm bước dọn rác (xoá reference tới phần không còn dùng) để file mới không phình to.

### 7.3 — Vận hành: file lớn, chạy nền, và validate trước khi báo thành công

```
MergeSplitOperation
├── chạy trên background queue (không phải main thread)
├── progress callback theo %
├── giới hạn kích thước input hợp lý (cảnh báo nếu tổng >200MB)
└── SAU khi ghi xong: mở lại file vừa tạo bằng chính SDK/engine của app để xác nhận parse được
     (không chỉ tin "ghi file không lỗi" — file hợp lệ về cú pháp vẫn có thể sai quan hệ r:id)
```

**Điểm cần chú ý — bẫy hay gặp nhất**: quên đồng bộ `[Content_Types].xml`/`_rels/*` là nguyên nhân phổ biến nhất khiến file merge mở được trong app tự build (dễ dãi bỏ qua lỗi) nhưng **mở lỗi/báo hỏng trong Word/PowerPoint thật** — luôn test round-trip bằng Word/PowerPoint thật, không chỉ bằng chính SDK đang dùng.

### 7.4 — Convert: Office ⇄ PDF, Image ⇄ PDF `[TỰ BUILD + SDK]` (bổ sung 2026-09-01)

4 chiều convert mới, đứng riêng trong Tools (không cần mở editor). Cả 4 dùng chung `PDFToolsViewModel` — mỗi chiều là 1 method mới cùng pattern reentrancy-guard/progress với `merge()`/`split()` đã có, **không tạo ViewModel riêng**.

**Office (Word/Excel/PPT) → PDF `[SDK]`** — dùng lại đúng API đã ghi ở §1 (`DocumentSession.exportAs(.pdf)`), chỉ khác chỗ gọi: mở session ở chế độ "headless" (không `presentViewController`), export xong đóng session ngay — không phải mở cả editor rồi export như luồng chỉnh sửa thường. SDK không hỗ trợ export trực tiếp Excel/PPT thì dùng đúng fallback native đã ghi ở §1 (`UIPrintPageRenderer`/`UIGraphicsPDFRenderer`).

**PDF → Word `[TỰ BUILD]`** — KHÔNG giữ được định dạng/ảnh/bảng ở MVP, chỉ trích xuất text thuần, tái dùng đúng `DOCXCodec.write` đã có cho Editor (`Services/Implementations/Native/DOCXCodec.swift`) — không viết engine ghi DOCX mới. **Phải tự phát hiện PDF có lớp chữ số hay không trước** (đúng `needsOCR()` ở §6.1.3) — 2 nhánh khác hẳn nhau về chi phí, không được giả định mọi PDF đều có sẵn chữ:

```swift
var text = ""
for i in 0..<pdfDocument.pageCount {
    guard let page = pdfDocument.page(at: i) else { continue }
    if needsOCR(page) {
        // PDF scan cũ, không có lớp chữ — fallback OCR, dùng CHUNG pipeline §6
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        let result = try await recognizer.recognize(in: image, pageIndex: i, languages: languages)
        text += result.fullText + "\n\n"
    } else {
        text += (page.string ?? "") + "\n\n"   // đã có chữ số sẵn, không cần OCR — rẻ hơn nhiều
    }
}
try DOCXCodec.write(AttributedString(text), to: outputURL)
```

**Bắt buộc hiện banner cảnh báo trước khi convert** ("Chỉ giữ văn bản, mất định dạng/ảnh/bảng") — không được im lặng hạ chất lượng, đúng nguyên tắc §6.4/rule.md #6. Nhánh OCR nên hiện thêm cảnh báo phụ ("PDF này không có chữ số sẵn, đang nhận diện — có thể chậm hơn") vì tốn thời gian hơn hẳn nhánh đọc trực tiếp.

**PDF → Image `[NATIVE]`** — rẻ nhất trong 4 mục, thuần PDFKit, không cần thư viện thêm:

```swift
let page = pdfDocument.page(at: i)!
let image = page.thumbnail(of: targetSize, for: .mediaBox)
```

Cho chọn range trang (tái dùng UI stepper/chip đã có ở Split §7.1) hoặc "toàn bộ". Output PNG, 1 file/trang, đặt tên tránh trùng qua `FileManager+NonConflictingURL` đã có.

**Image → PDF `[NATIVE]`** — đối xứng OCR scan (§6) nhưng KHÔNG chạy Vision, chỉ vẽ ảnh gốc vào từng trang:

```swift
let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
try renderer.writePDF(to: outputURL) { ctx in
    for image in images {
        ctx.beginPage()
        image.draw(in: pageBounds)
    }
}
```

Nhận nhiều ảnh, sắp thứ tự bằng drag handle (tái dùng đúng UI list kéo-thả đã có ở Merge §7.1) — mỗi ảnh = 1 trang, không auto-crop/rotate ở MVP (để Phase sau nếu cần "quét từ ảnh có sẵn" giống camera scanner thật).

---

## 8. Note / comment dạng text (không cần Pencil) `[SDK, khả năng cao có sẵn]`

Nếu SDK cùng họ kiến trúc đã thấy (ribbon-based, có `Review`/`Annotate` ribbon controller riêng) — đây gần như chỉ là **bật 1 ribbon có sẵn + tự build UI danh sách comment**.

### 8.1 — Data model

```
Comment
├── id
├── anchorRange (vị trí trong text, hoặc bounding box nếu PDF annotation)
├── author, createdAt, body: String, resolved: Bool
└── replies: [Comment]   ← Word/PDF chuẩn hỗ trợ reply theo thread, không phải comment phẳng
```

### 8.2 — Persistence: bắt buộc kiểm chứng comment nằm THẬT trong file

Rủi ro dễ bị bỏ sót nhất: 1 số SDK "comment" thực chất chỉ lưu vào **database riêng của SDK**, không ghi ngược vào file .docx/.pdf chuẩn — mở file bằng Word/Acrobat thật ở máy khác sẽ **không thấy comment nào**.

```
Cách xác nhận trước khi build UI:
1. Thêm 1 comment test qua API SDK
2. Export/save file ra ngoài sandbox app
3. Mở file bằng Word/Acrobat thật (không phải bằng lại chính app/SDK)
4. Comment còn hiển thị đúng → an toàn để build tiếp
   Comment biến mất → SDK chỉ lưu annotation riêng, cần hỏi vendor hoặc tự viết XML comment (tốn công hơn nhiều)
```

**Điểm cần chú ý**: kiểm tra bước này **trước khi** build UI sidebar/thread — ảnh hưởng trực tiếp ước lượng effort của cả mục.

---

## 9. E-signature + watermark

### 9.1 — E-signature `[SDK, nếu chọn đúng SDK có PKI]` — 2 tầng

```
SignatureFlow
├── Tầng 1 — chữ ký vẽ tay (rẻ, làm trước):
│     PKCanvasView → xuất ra image → SDK.placeSignatureImage(at: position)
│     Giá trị: tương đương "chữ ký điện tử cơ bản", KHÔNG chứng minh được danh tính nếu có tranh chấp
├── Tầng 2 — ký số PKI thật (giá trị pháp lý cao hơn):
│     ├── import certificate (.p12) → Keychain (KHÔNG lưu private key ở đâu khác)
│     ├── SDK.signDocument(with: certificate) → verify được bằng Acrobat/tool chuẩn, không chỉ trong app
│     └── UI hiển thị trạng thái "Verified/Unverified" khi mở lại file đã ký
```

**Lưu ý không phải tư vấn pháp lý**: không tự khẳng định "chữ ký này có giá trị pháp lý" chung chung — mô tả đúng cơ chế kỹ thuật thay vì cam kết pháp lý.

**Verify khi mở lại file đã ký**:
```swift
let verifyResult = session.verifySignatures()
for sig in verifyResult {
    switch sig.status {
    case .valid: showBadge(.green, "Đã xác thực — \(sig.signerName)")
    case .modifiedAfterSigning: showBadge(.red, "File đã bị sửa sau khi ký")
    case .certificateExpired: showBadge(.orange, "Certificate hết hạn")
    case .unknown: showBadge(.gray, "Không xác thực được")
    }
}
```

### 9.2 — Watermark `[TỰ BUILD]` — không có ở SDK

```
WatermarkRenderer
├── input: text/image watermark + opacity + rotation + vị trí
├── PDF: vẽ đè lên mỗi trang qua CGPDFContext trước khi save (native)
├── Word/PPT: chèn textbox/shape vào slideMaster.xml (PPT) hoặc header.xml (Word) — áp dụng tự động toàn bộ trang/slide
└── Cân nhắc MVP: watermark chỉ áp dụng lúc export/share (không sửa file gốc) — giảm effort đáng kể
```

**Điểm cần chú ý**: watermark áp lúc export là lựa chọn hợp lý cho MVP — vừa giảm effort vừa an toàn hơn (user không lo watermark dính chết vào file gốc nếu chọn nhầm).

---

## 10. Core loop MVP — "Tủ hồ sơ" `[NATIVE + TỰ BUILD]` — chưa có ở bản gốc, ý mới hoàn toàn

Đây là core loop THẬT của MVP (không phải AI) — habit loop dựa trên hiệu ứng Zeigarnik: mở app → tủ hồ sơ tự đầy → thấy tài liệu dở dang → sửa/hoàn thiện → đổi trạng thái → cảm giác "dọn sạch". Chi tiết đầy đủ về hành vi + rủi ro chưa kiểm chứng: xem `product-strategy-master.md` mục 1.

### 10.1 — Trang chủ tủ hồ sơ: hợp nhất 2 nguồn dữ liệu thành 1 danh sách

```
DocumentLibrary
├── nguồn 1: quét tự động thư mục đã cấp quyền (mục 4.1) — nguồn chính, tự đầy ngay khi mở app
├── nguồn 2: file add thủ công (mục 4.5) — nguồn phụ, cho file nằm ngoài thư mục đã cấp quyền
└── merge 2 nguồn theo documentID bền vững (10.2) — tránh liệt kê trùng nếu 1 file vừa nằm trong
      thư mục đã cấp quyền vừa từng được add thủ công trước đó
```

### 10.2 — Trạng thái tài liệu: metadata riêng, KHÔNG sửa vào file gốc

```
DocumentMetadata (lưu local — Core Data/SQLite, KHÔNG phải ghi vào chính file .docx/.pdf)
├── documentID: String        ← bền vững qua các lần mở lại, KHÔNG dùng file path làm key
│     (path có thể đổi nếu file di chuyển trong thư mục đã cấp quyền — dùng file bookmark data
│     hoặc hash nội dung + tên file làm định danh ổn định hơn)
├── status: .draft | .reviewed | .signed | .sent    // Nháp → Đã xem lại → Đã ký → Đã gửi
├── lastOpenedAt, lastModifiedAt: Date
└── remindAt: Date?           ← dùng ở 10.4
```

**Điểm cần chú ý**: đổi trạng thái là hành động thủ công của user (chọn trong menu/swipe action), KHÔNG tự động suy luận từ hành vi (vd không tự chuyển "Đã xem lại" chỉ vì user mở file) — tự động suy luận sai trạng thái sẽ phá hỏng chính tín hiệu "còn nợ việc" mà cả core loop dựa vào.

### 10.3 — Cấp quyền 1 lần + tự động quét: xem mục 4.1

Toàn bộ code + luồng đã viết đầy đủ ở **mục 4.1** (permission picker chọn thư mục, lưu bookmark, tự quét/import, resolve lại + xử lý `isStale` mỗi lần mở app) — không lặp lại ở đây. Đây chính là bước tạo ra Aha moment của core loop: user cấp quyền 1 lần, những lần sau mở app tủ hồ sơ đã tự đầy sẵn, dùng ngay.

**Điểm cần chú ý riêng cho Tủ hồ sơ**: nếu bookmark bị revoke (xem cảnh báo ở 4.1) mà không có UI fallback rõ ràng ("Cấp lại quyền truy cập"), tủ hồ sơ sẽ im lặng trống rỗng — đúng kịch bản tệ nhất cho core loop này (aha moment biến mất, user tưởng app lỗi).

### 10.4 — Tự đặt nhắc trong app: KHÔNG dùng push notification

Quyết định sản phẩm đã chốt: chỉ nhắc **trong app**, không gửi notification khi app đóng (tránh cảm giác phản cảm với công cụ năng suất — xem `product-strategy-changelog.md`).

```
remindAt: Date?   // field optional trên DocumentMetadata (10.2), user tự đặt qua UI

Khi mở app:
    documents.filter { $0.remindAt != nil && $0.remindAt! <= Date() }
             .sort(theo remindAt tăng dần)
             → hiện nổi bật đầu danh sách tủ hồ sơ (không phải push, không phải local notification)
```

**Điểm cần chú ý**: không cần `UNUserNotificationCenter`/background task nào — toàn bộ logic chỉ chạy khi app đang mở, đơn giản hơn hẳn 1 hệ thống nhắc nhở thật, đúng với quyết định "chỉ in-app".

### 10.5 — "Cảm giác dọn sạch": thuần UI, không phải tính năng riêng

```
draftCount = documents.filter { $0.status == .draft }.count
// hiển thị số này rõ ràng ở trang chủ tủ hồ sơ, giảm dần khi user đổi trạng thái — không cần logic phụ trợ nào khác
```

**Rủi ro cần nhớ khi build (đã ghi ở `product-strategy-master.md` mục 7)**: toàn bộ core loop này giả định user có đủ tài liệu dở dang thường xuyên — giả thuyết CHƯA kiểm chứng. Không đầu tư thêm tính năng phụ trợ (gamification, streak...) cho tới khi có data thật xác nhận loop này chạy.

---

## Phụ lục A. AI tóm tắt tài liệu `[TỰ BUILD — tích hợp LLM API]` — Phase 1, đã thu hẹp scope, KHÔNG phải MVP

> **Không còn ở MVP** — đẩy tạm về Phase 1 (27/08, quyết định lại). Logic dưới đây giữ nguyên, chỉ đổi mốc thời gian áp dụng.

Tính năng AI thật đầu tiên, dự kiến Phase 1. **Đã thu hẹp so với tên gọi cũ** "AI tóm tắt/viết lại/hỏi-đáp" — chỉ còn đúng 1 việc: tóm tắt. Không viết lại đoạn văn, không hỏi-đáp nội dung file (2 việc đó không còn trong scope MVP). Vai trò trong core loop (mục 10): hỗ trợ bước "mở lại 1 tài liệu dở dang lâu ngày" — giúp user nhớ lại nội dung nhanh trước khi sửa tiếp, không phải cơ chế đứng riêng.

### A.1 — Input: trích xuất text từ DocumentSession đang mở, không phải file thô

```
session.extractPlainText() -> String   // API SDK cung cấp (hầu hết SDK có sẵn hàm export/extract text thuần)
```

Nếu SDK không có sẵn hàm này: fallback đọc qua cấu trúc XML (giống cách merge/split ở mục 7 đã parse `document.xml`), lấy text node, bỏ qua bước dựng lại định dạng — chỉ cần nội dung thô để tóm tắt, không cần giữ style.

### A.2 — Giới hạn độ dài trước khi gửi lên LLM

```
if text.count > maxTokenBudget {
    // Tài liệu dài: chunk theo section/heading (dùng lại outline/TOC đã có ở mục 5.1)
    // rồi tóm tắt từng chunk, gộp lại tóm tắt-của-tóm tắt (map-reduce đơn giản)
}
```

Không cắt cứng theo ký tự (character truncation) — cắt giữa câu/đoạn làm tóm tắt sai lệch nội dung phần cuối tài liệu.

### A.3 — Backend proxy, dùng chung kiến trúc với AI tạo văn bản (Phụ lục B)

Giống hệt lý do ở Phụ lục B.4: không nhúng API key thẳng vào app — lộ ra bằng đúng kiểu static analysis đã dùng để phân tích 2 đối thủ trong tài liệu này. Dùng **chung 1 backend proxy** (Cloud Function/thin API server, xác thực qua App Attest hoặc Firebase App Check) với AI tạo văn bản ở Phụ lục B — không xây 2 hệ thống riêng, kể cả khi cả 2 chưa build ngay, vẫn nên dựng backend đủ tổng quát để dùng lại được.

### A.4 — Hiển thị: side panel/sheet, KHÔNG chèn vào tài liệu

Khác hẳn AI tạo văn bản (Phụ lục B.5, stream thẳng vào canvas) — tóm tắt chỉ là tham khảo, không sửa nội dung file. Hiển thị trong 1 sheet/side panel riêng, có nút "Đóng", không có nút "Chèn vào tài liệu" (giữ đúng ranh giới: tính năng này không tự sinh/sửa nội dung tài liệu bằng AI).

### A.5 — Cache theo document + lastModified, không gọi lại API mỗi lần mở

```
SummaryCache[documentID + lastModifiedHash] -> cachedSummary
```

Tài liệu chưa đổi từ lần tóm tắt trước → trả cache, không gọi lại LLM (tiết kiệm chi phí — đây là tính năng phụ trợ, không đáng để tốn quota mỗi lần user mở lại 1 file cũ để xem tóm tắt).

### A.6 — Trigger UI: ưu tiên hiển thị khi tài liệu "Nháp" lâu ngày

Nút "Tóm tắt" có mặt ở mọi tài liệu, nhưng nổi bật hơn (badge/gợi ý chủ động) khi tài liệu đang ở trạng thái "Nháp" (mục 10.2) và đã lâu chưa mở lại — đây chính là điểm nối trực tiếp với core loop bước 3 ("mở lại tài liệu dở dang").

### A.7 — Lỗi/fallback: im lặng ẩn nút, không chặn luồng chính

Khác AI tạo văn bản (Phụ lục B.7, là action chính không thể lờ đi) — tóm tắt chỉ là tiện ích phụ: provider lỗi/timeout thì ẩn nút hoặc hiện "Không tóm tắt được lúc này", **không** chặn hay làm gián đoạn việc mở/sửa tài liệu.

---

## Phụ lục B. AI tạo văn bản từ mô tả (chat-to-document) `[TỰ BUILD — tích hợp LLM API]` — Phase 2, KHÔNG phải MVP

> **Không còn ở MVP.** Logic dưới đây viết từ lúc tính năng này còn là core loop MVP — giữ lại nguyên vẹn làm tài liệu tham khảo cho Phase 2, vì thiết kế (DocumentBuilder, clause library, backend proxy) vẫn dùng lại được y nguyên khi tới lúc, chỉ đổi mốc thời gian áp dụng. Đánh số lại B.1–B.8 để không lẫn với 10 mục MVP thật ở trên hoặc với Phụ lục A (AI tóm tắt, Phase 1).

Đây là USP trung tâm quyết định người dùng có lý do chọn app này thay vì mở Word trống hoặc chat AI riêng rồi copy-paste. Khác mọi mục còn lại trong MVP: không có logic tương tự nào ở bản gốc để tham khảo — toàn bộ viết mới.

### B.1 — Điểm kiến trúc quan trọng nhất: AI phải ghi ra một `DocumentSession` thật, không phải text thô

**Đây là rủi ro kỹ thuật lớn nhất của cả core loop.** Nếu bước này chỉ là dán text thô của LLM vào 1 `UITextView` không định dạng, toàn bộ premise "AI viết ngay trong bộ Office thật" sụp đổ — quay lại y hệt trải nghiệm mở ChatGPT rồi copy-paste vào Word mà core loop này định thay thế.

```
GeneratedContent (output của LLM, KHÔNG phải chuỗi prose tự do)
├── docType: .contract | .quote | .report | .letter | .other
├── blocks: [ContentBlock]   ← output có cấu trúc (JSON), không phải markdown tự do khó parse ổn định
│     ContentBlock = .heading(level, text) | .paragraph(runs: [TextRun]) | .table(rows) | .bulletList([String])
│     TextRun mang theo style tối thiểu (bold/italic) để map đúng sang <w:r>/run của SDK, không mất định dạng ngay từ bản nháp đầu
└── suggestedTitle: String

DocumentBuilder.build(from: GeneratedContent) -> DocumentSession
    session = DocumentSessionManager.newDocument(from: content)   // xem mục 1 — cùng interface DocumentSession
    for block in content.blocks {
        switch block {
        case .heading(let level, let text): session.insertHeading(text, level: level)
        case .paragraph(let runs):          session.insertParagraph(runs.map { toSDKRun($0) })
        case .table(let rows):              session.insertTable(rows)
        case .bulletList(let items):        session.insertBulletList(items)
        }
    }
    return session   // từ đây, MỌI logic ở mục 1 (edit/save/export) áp dụng y hệt 1 file mở từ đĩa
```

**Vì sao "Office là nền tảng/key"** (đúng câu định vị) **có ý nghĩa kiến trúc thật, không chỉ marketing**: nội dung AI sinh ra đi qua đúng 1 cửa (`DocumentBuilder` → `DocumentSession`) với file mở từ đĩa — không có 2 đường code riêng cho "tài liệu AI tạo" và "tài liệu mở thường". Editor, autosave (Phase 1), export, e-signature đều dùng chung, không viết lại.

### B.2 — Chọn loại tài liệu trước khi mô tả — thu hẹp prompt, giảm hallucination

```
Entry point "Tạo mới":
1. Chip chọn loại: Hợp đồng / Báo giá / Báo cáo / Khác
2. Ô mô tả tự do: "làm hợp đồng thuê nhà cho tôi, bên A tên X, bên B tên Y, giá 5tr/tháng..."
3. Gửi (docType đã chọn + mô tả) lên backend — docType quyết định system prompt + scaffold nào được dùng
```

**Vì sao không để AI tự đoán loại tài liệu từ mô tả tự do**: đoán sai loại → sai luôn cấu trúc/scaffold → sai ngay từ bước đầu core loop. Bắt chọn tay 1 chip rẻ hơn nhiều so với thêm 1 bước classify bằng chính LLM (tốn thêm 1 lượt gọi, thêm điểm có thể sai).

### B.3 — Hợp đồng/báo giá: dùng thư viện điều khoản đã kiểm, KHÔNG để AI tự bịa nội dung pháp lý từ đầu

**Điểm cần chú ý quan trọng nhất mục này về mặt rủi ro sản phẩm**: với `docType == .contract`, không nên để LLM tự do sinh toàn bộ câu chữ điều khoản pháp lý (đặt cọc, phạt vi phạm, chấm dứt hợp đồng...) — model có thể tạo ra điều khoản sai luật hiện hành hoặc mâu thuẫn nội bộ. Cách an toàn hơn:

```
ContractGenerationPrompt
├── clauseLibrary: [ClauseTemplate]   ← soạn sẵn, người thật review 1 lần (liên kết trực tiếp "vertical template
│     cho freelancer" đã lên kế hoạch ở Phase 1 — xây thư viện điều khoản này SỚM hơn Phase 1 một phần, vì
│     Phụ lục B cần nó ngay lúc đó (không phải đợi Phase 1 mới có))
├── system prompt: "Chọn điều khoản phù hợp từ danh sách sau, CHỈ điền field (tên, số tiền, ngày...) theo mô tả
│     người dùng, KHÔNG tự soạn điều khoản mới ngoài danh sách" + clauseLibrary liệt kê sẵn
└── output: ContentBlock trỏ tới đúng clause đã chọn + field đã điền, không phải văn bản tự do 100%
```

Với `docType == .report`/`.letter` (không mang tính pháp lý ràng buộc) thì để AI sinh tự do hơn — rủi ro thấp hơn nhiều nếu sai.

### B.4 — KHÔNG gọi LLM API trực tiếp từ app — backend proxy mỏng

Giống hệt lý do đã nêu ở AI tóm tắt (Phụ lục A.3, Phase 1) — nếu nhúng thẳng API key vào app, lấy được bằng đúng kiểu static analysis đã dùng để phân tích 2 đối thủ trong tài liệu này.

```
App → Backend riêng (Cloud Function/thin API server) → LLM provider
App xác thực với backend qua App Attest (native) hoặc Firebase App Check (ít công hơn cho MVP)
```

*(Toàn bộ kiến trúc quota/rate-limit/circuit-breaker — dùng chung 1 backend với AI tóm tắt ở Phụ lục A (Phase 1), không xây 2 hệ thống riêng.)*

### B.5 — Streaming thẳng vào canvas tài liệu, không phải vào 1 khung chat riêng

```swift
for try await block in aiService.streamGenerate(docType: docType, description: userInput) {
    documentBuilder.appendBlock(block, to: session)   // mỗi block xong là chèn ngay vào DocumentEditorView đang mở
    // cảm giác "tài liệu tự hiện ra trước mắt trong app Office thật" — đây chính là khoảnh khắc Aha của core loop,
    // KHÔNG hiện trong 1 bong bóng chat rồi mới "chèn vào tài liệu" ở bước sau (thêm 1 cú click = mất 1 nhịp aha)
}
```

**Điểm cần chú ý**: khác với AI tóm tắt (Phụ lục A, Phase 1) — nơi hiển thị kết quả trong 1 side panel là hợp lý — ở đây bắt buộc stream thẳng vào chính document canvas, vì bản thân việc "thấy tài liệu tự soạn ngay trong bộ Office thật" mới là điều khác biệt so với dùng ChatGPT rồi tự dán vào Word.

### B.6 — Sau khi tạo xong: đây chỉ là 1 DocumentSession bình thường

Không có logic edit riêng cho "tài liệu do AI tạo" — từ thời điểm `DocumentBuilder.build()` trả về, mọi thao tác (sửa chữ, format, export PDF, ký, watermark) dùng đúng logic đã có ở mục 1, 7, 9. Đây là điểm mạnh của kiến trúc "1 cửa" ở §B.1 — không phải build thêm 1 editor thứ hai riêng cho nội dung AI.

### B.7 — Xử lý lỗi/fallback

```
Generate thất bại (provider down, hết quota, mô tả quá mơ hồ để tạo nội dung có ý nghĩa):
    → KHÔNG trả về document rỗng im lặng
    → mô tả quá ngắn/mơ hồ → hỏi lại 1 câu làm rõ trước khi gọi LLM (rẻ hơn gọi rồi ra kết quả vô nghĩa)
    → hết quota → CTA nâng cấp Pro
    → provider timeout → cho phép retry thủ công, không tự động retry ngầm nhiều lần
```

### B.8 — Ngôn ngữ & văn phong

Roadmap không giới hạn 1 thị trường — system prompt cần theo ngôn ngữ mô tả đầu vào của user (không hardcode tiếng Việt), và với `docType == .contract`/`.quote` cần văn phong hành chính/kinh doanh đúng chuẩn ngôn ngữ đó (không dịch máy móc từ 1 template tiếng Anh gốc) — nếu MVP chỉ ưu tiên 1 thị trường trước, nên là thị trường có sẵn `clauseLibrary` (§B.3) được review kỹ, không mở rộng ngôn ngữ nhanh hơn tốc độ kiểm điều khoản.

---

## Tổng hợp effort — nhìn lại theo 3 nhóm (11 hạng mục MVP thật, cộng Phụ lục A/B tham khảo Phase 1/2)

| Nhóm | Tính năng | Vì sao |
|---|---|---|
| **Rẻ (native/SDK có sẵn, chỉ cần wire đúng)** | Core editing, AirPrint, OCR (Vision), layout adaptive, **Convert Office→PDF/PDF→Word/PDF→IMG/IMG→PDF (mục 7.4, bổ sung 2026-09-01)** | Framework Apple hoặc API SDK đã có, việc chính là kiến trúc gọi đúng chỗ — Convert tái dùng nguyên `exportAs` (SDK), `DOCXCodec`, `PDFKit`, `UIGraphicsPDFRenderer` đã có sẵn, không viết engine mới |
| **Trung bình (SDK có phần, tự build phần UI/wrap, hoặc thuần local)** | iPad multi-pane, Note/comment, E-signature, **Add file — cấp quyền + auto-scan (mục 4)**, **Core loop "Tủ hồ sơ" (mục 10)** | SDK cấp data/API gốc nhưng UI và logic nghiệp vụ phải tự làm; Add file/Tủ hồ sơ không cần SDK/backend nào nhưng nhiều phần nhỏ phải làm đúng (bookmark thư mục, xử lý `isStale`/revoke, key bền vững cho document) — dễ nhìn "rẻ" vì toàn API native nhưng dễ sai vặt nếu làm ẩu |
| **Đắt (không ai có sẵn, tự viết từ đầu)** | Files app provider, Merge/Split (Word/PPT), Watermark | Không SDK nào có sẵn — công sức dev thật, không "rẻ" như nghe tên gọi |

**MVP giờ không còn mục AI nào trong bảng effort** — cả AI tóm tắt (Phụ lục A) lẫn AI tạo văn bản (Phụ lục B) đều là Phase sau, không tính vào effort MVP. Nếu muốn tiết kiệm công sau này: backend proxy ở Phụ lục A.3 (AI tóm tắt) nên dựng đủ tổng quát ngay khi tới lúc, để phần lớn hạ tầng (App Attest/App Check, quota/rate-limit) dùng lại được nguyên khi tới Phụ lục B (AI tạo văn bản, Phase 2).

**Rủi ro lịch trình MVP thật**: mục 10 (Core loop "Tủ hồ sơ") phụ thuộc mục 3 (File Provider) xong trước — làm song song sớm với Core editing (mục 1) và Files provider (mục 3), không để tới cuối cùng mới bắt đầu, vì đây là core loop MVP thật.

---

*Kế thừa `Phase0-Implementation-Logic.md` gốc (accessed 27/08/2026) + `product-strategy-master.md` (roadmap MVP cuối cùng, cập nhật 27/08/2026 — xem `product-strategy-changelog.md` cho lịch sử đầy đủ các vòng đổi ý). Tên class SDK dùng minh hoạ theo pattern Artifex đã quan sát được — đổi theo API thật của SDK bạn chọn license. 3 mục chuyển sang Phase 1 (Autosave/crash-recovery, Apple Pencil, Compress) — xem lại logic chi tiết ở bản gốc khi tới lúc triển khai, không cần viết lại. 1 mục AI tóm tắt cũng đẩy về Phase 1 — logic giữ lại ở Phụ lục A. 1 mục chuyển sang Phase 2 (AI tạo văn bản từ mô tả) — logic đầy đủ giữ lại ở Phụ lục B.*
