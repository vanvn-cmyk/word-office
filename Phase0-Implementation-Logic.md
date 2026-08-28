# Phase 0 (MVP) — Logic xử lý code cho từng tính năng

Giả định kiến trúc: **license 1 SDK thương mại xử lý document** (Artifex Smart Office SDK hoặc tương đương như PSPDFKit/Nutrient) — cùng mô hình 2 đối thủ đã phân tích đang dùng (session-based document open + view-controller present + ribbon config). Logic dưới đây viết theo pattern chung của loại SDK này (tên class minh hoạ theo Artifex, đổi tên theo SDK thật bạn chọn), kết hợp framework native của Apple ở phần SDK không cung cấp.

Ký hiệu: `[SDK]` = phần chắc chắn có sẵn trong SDK license (đã xác nhận qua teardown), `[NATIVE]` = framework Apple có sẵn, `[TỰ BUILD]` = không có ở đâu cả, phải viết logic riêng.

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
└── closeDocument(_ session:) → flush autosave, release session, xoá temp file nếu convert
```

**Convert PDF (từ Word/Excel/PPT sang PDF)**: hầu hết SDK loại này có API `exportAs(.pdf)` trên session đã mở — không cần thêm engine riêng. Nếu SDK không hỗ trợ convert Excel/PPT→PDF trực tiếp, fallback: render từng trang qua `UIPrintPageRenderer`/`drawRect` vào `UIGraphicsPDFRenderer` (native, không cần SDK).

**Điểm cần chú ý**: cả 2 đối thủ hỗ trợ .hwp/.hwpx (Hancom) miễn phí ở tầng SDK — kiểm tra SDK bạn chọn có cùng UTI này không, nếu có thì thêm vào danh sách `UTImportedTypeDeclarations` gần như miễn phí (thêm UTI, không thêm logic).

---

## 2. Autosave + crash-recovery `[TỰ BUILD]` (SDK không lộ ra logic này, phải tự viết lớp bọc)

**Logic autosave** (interval + change-triggered, không chỉ 1 trong 2):

```
DocumentSession.onContentChanged { 
    dirty = true
    debounceTimer.reset(2s)   // gõ liên tục thì không save mỗi ký tự
}

debounceTimer.onFire {
    if dirty {
        saveToStagingFile()   // KHÔNG ghi đè file gốc trực tiếp
        dirty = false
    }
}

// Ngoài debounce, có timer cứng độc lập (phòng debounce bị reset liên tục do gõ không ngừng)
hardIntervalTimer(every: 30s) { if dirty { saveToStagingFile() } }
```

**Vì sao ghi vào staging file, không ghi đè file gốc**: nếu app crash giữa lúc ghi, file gốc phải còn nguyên vẹn. Flow chuẩn:

```
saveToStagingFile():
    write to  <original>.autosave.tmp
    fsync()
    atomically rename → <original> (chỉ khi write thành công 100%)
```

**Crash-recovery ở lần mở app tiếp theo**:

```
appDidFinishLaunching():
    scan document-storage directory tìm file *.autosave.tmp còn sót
    → nếu có: nghĩa là lần trước app bị kill giữa chừng save (crash hoặc bị hệ điều hành kill)
    → show banner "Khôi phục bản chưa lưu?" thay vì tự động ghi đè (tránh mất bản người dùng cố ý không lưu)
```

**Điểm cần chú ý**: đúng review thật bạn dẫn ("crash mất 4 giờ làm việc") thường xảy ra vì app ghi đè trực tiếp file gốc khi save → crash giữa chừng làm hỏng cả file gốc lẫn bản đang sửa. Pattern staging-file + atomic rename ở trên giải quyết đúng root cause đó, không phải chỉ "save thường xuyên hơn".

---

## 3. Kiến trúc layout adaptive (size classes / NavigationSplitView) `[NATIVE]`

**Logic chính**: 1 `RootView` duy nhất, KHÔNG có 2 codebase iPhone/iPad riêng — chọn layout theo `horizontalSizeClass`:

```swift
struct RootView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    // .all = hiện cả 3 cột, .doubleColumn = ẩn sidebar giữ content+detail (mặc định nên dùng cái này —
    // tối đa không gian cho editor ngay khi mở app, đúng tinh thần "made for iPad, not scaled from iPhone"),
    // .detailOnly = chỉ hiện editor

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

**Vì sao đây là "đầu tư không mất gì" như đã ghi trong roadmap**: `NavigationSplitView` tự co về 1-cột khi `sizeClass` là `.compact` — không cần viết logic riêng cho Fold, chỉ cần đảm bảo state (document đang mở, selection) sống ở 1 nguồn chung (`@Observable` view model ở `RootView`, không sở hữu bởi view con) để khi size class đổi giữa chừng (xoay ngang/dọc, mở/gập Fold, vào/ra Split View) không mất state.

**Điểm cần chú ý**: đừng để `DocumentSessionManager` (mục 1) sống trong view — sống ở tầng `RootView`/App-level singleton, để đổi layout không kill session đang mở.

---

## 4. Files app provider `[TỰ BUILD]` + AirPrint `[SDK/NATIVE]`

### Files app provider — **0/2 đối thủ có, cơ hội thật nhưng chi phí kỹ thuật cao hơn các mục khác trong bảng gốc**

Đây không phải "Add file" (mở file từ Files app vào app bạn) — đây là làm cho app của bạn **xuất hiện như 1 vị trí duyệt được** trong chính app Files, giống Dropbox/iCloud. Files app không nói chuyện trực tiếp với app chính của bạn — nó nói chuyện với 1 **target riêng biệt** (`File Provider Extension`) mà hệ điều hành tự khởi động thành process riêng khi cần, kể cả lúc app chính đang đóng.

### 4.1 — Bộ khung extension (target riêng, `com.apple.fileprovider-nonui`)

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

### 4.2 — Nguồn dữ liệu dùng chung (bài toán 2 process không share memory)

App chính và extension là **2 tiến trình khác nhau hoàn toàn** — không gọi hàm/biến chéo nhau được. Mọi thứ phải đi qua đĩa, qua 1 App Group container:

```
App Group container (group.com.yourapp.shared)
├── /Documents/  ← file thật (.docx/.pdf/...) — cả app chính lẫn extension đều đọc/ghi đúng chỗ này
└── /Metadata.sqlite (hoặc CoreData/Realm) ← index nhẹ: id, tên, size, ngày sửa, itemIdentifier
      (không nên bắt extension phải mở full document để lấy metadata mỗi lần Files app hỏi — chậm)
```

**Vì sao cần lớp metadata riêng, không đọc trực tiếp filesystem mỗi lần**: `enumerator()` bị Files app gọi rất thường xuyên (mỗi lần user cuộn/mở sidebar) — nếu mỗi lần đều phải mở file thật để lấy tên/size thì rất chậm, đặc biệt với PPTX/PDF nặng. Giữ 1 bảng index nhẹ, chỉ `fetchContents` mới đụng vào file thật.

### 4.3 — 2 chiều đồng bộ: sửa trong Files app phải phản ánh vào app chính, và ngược lại

Đây là phần dễ bug nhất — 2 luồng cần xử lý riêng:

**Luồng A — user sửa TRONG Files app (đổi tên, xoá, kéo thả)**
```
Files app gọi extension.renameItem(...) 
    → extension ghi đổi tên file thật trong App Group container + update Metadata.sqlite
    → gọi NSFileProviderManager.signalEnumerator(for: .rootContainer) 
      để báo Files app "list đã đổi, refresh lại UI"
    → app chính KHÔNG tự biết ngay lập tức (đang chạy process khác) — cần lắng nghe thay đổi
      qua NSFilePresenter (đăng ký theo dõi đúng file/folder trong App Group) hoặc đơn giản hơn:
      re-scan Metadata.sqlite mỗi lần app chính active trở lại (applicationDidBecomeActive)
```

**Luồng B — user sửa TRONG app chính (đang gõ, vừa save xong)**
```
DocumentSessionManager.save() hoàn tất
    → ghi file (đã có ở mục 2 — staging file + atomic rename)
    → update Metadata.sqlite (App Group)
    → gọi NSFileProviderManager(for: providerDomain)?.signalEnumerator(for: .rootContainer)
      để báo Files app "có thay đổi, refresh nếu đang mở"
```

**Điểm cần chú ý — xung đột (conflict)**: nếu Files app đang cho user "kéo file ra ngoài để sửa" (ví dụ mở bằng app khác rồi lưu lại) đúng lúc app chính cũng đang autosave, cần `NSFileCoordinator` bọc quanh MỌI thao tác đọc/ghi vào App Group container (kể cả từ app chính) — không tự ý `FileManager.write()` thẳng, vì đó chính là cơ chế OS dùng để tránh 2 process ghi đè nhau cùng lúc.

### 4.4 — Đăng ký domain (bước dễ quên, không có thì Files app không hiện app bạn)

**Mental model**: viết extension (mục 4.1) chỉ là viết "bộ luật trả lời câu hỏi" — enumerator/item/fetchContents. iOS không tự suy ra "app này muốn xuất hiện trong Files" chỉ vì bundle có 1 target extension khai báo đúng `NSExtensionPointIdentifier`. Phải có **1 lệnh riêng, gọi từ code app chính** (không phải trong extension) để nói với hệ điều hành "kích hoạt location này" — đó là `NSFileProviderManager.add(domain:)`. Trước khi lệnh này chạy thành công lần đầu, extension coi như "ngủ" — không hàm nào trong đó được OS gọi tới, dù code hoàn toàn đúng.

**Đây là lý do dễ debug sai hướng**: code xong hết `enumerator()`/`item()`/`fetchContents()`, build chạy, Files app không hiện gì → rất dễ ngồi soi lại logic enumerator tưởng nó sai, nhưng thật ra hàm đó **chưa từng được gọi lần nào** vì domain chưa đăng ký — 2 việc hoàn toàn tách biệt, không có lỗi/log nào liên kết chúng lại để gợi ý bạn nhìn đúng chỗ.

```swift
// Gọi ở app chính — 1 LẦN duy nhất (không phải mỗi lần app mở), thường ngay sau lần launch đầu tiên
// hoặc sau khi user chủ động bật tính năng này trong Settings.
func registerFileProviderDomainIfNeeded() async throws {
    let existing = try await NSFileProviderManager.domains()
    guard !existing.contains(where: { $0.identifier == .init("main") }) else {
        return   // đã đăng ký từ trước — gọi add() lần 2 với cùng identifier sẽ báo lỗi domain trùng
    }

    let domain = NSFileProviderDomain(identifier: .init("main"), displayName: "Tên App Của Bạn")
    try await NSFileProviderManager.add(domain)
    // domain giờ mới thật sự "sống" — Files app bắt đầu gọi enumerator() của extension từ đây
}
```

**3 điều hay gây lỗi khi làm phần này:**
- **Gọi trùng nhiều lần** → `add()` báo lỗi domain đã tồn tại — luôn check `NSFileProviderManager.domains()` trước (như code trên), không gọi vô điều kiện mỗi lần app launch.
- **Thiếu App Group entitlement khớp giữa app chính và extension target** → `add()` fail âm thầm hoặc extension không đọc được dữ liệu dù domain đã đăng ký thành công — kiểm tra App Group ID phải **giống hệt ký tự** ở cả 2 target trong Xcode Signing & Capabilities.
- **Gỡ app cài lại lúc dev** → domain cũ có thể còn sót ở registry hệ thống gây trạng thái lạ (extension "sống" nhưng dữ liệu App Group đã mất) — dùng `NSFileProviderManager.remove(domain:)` để dọn sạch trước khi test lại từ đầu.

**Điểm cần chú ý**: extension chạy process riêng, không share memory với app chính — mọi thay đổi phải qua file trên đĩa (App Group container) hoặc `NSFileCoordinator`, không qua notification/delegate như Action/Share extension thông thường. Đây là lý do chi phí kỹ thuật cao hơn 2 loại extension kia (Word Office/A1 đều chỉ làm Action/Share/Widget — không app nào làm loại này, đúng như đã xác nhận).

### 4.5 — Thumbnail + "working set" (hiệu năng khi Files app hiển thị lưới file)

**Vấn đề**: Files app mặc định hiển thị dạng lưới ảnh (grid), gọi `fetchThumbnails(for: [nhiều identifier cùng lúc], ...)` mỗi khi user cuộn. Nếu hàm này mở full document (qua SDK) để render preview mỗi lần — app sẽ lag nặng, đặc biệt file PPTX/PDF nhiều trang.

```
fetchThumbnails(for identifiers, completionHandler):
    với mỗi identifier:
        // ưu tiên 1: đã có thumbnail cache sẵn (tự tạo lúc save document lần đầu, lưu .jpg nhỏ cạnh file trong App Group)
        if let cached = readCachedThumbnail(identifier) { return cached }
        // ưu tiên 2: chưa có cache — trả nil ngay, KHÔNG block chờ render
        //            rồi render nền (background) 1 lần, lưu cache lại cho lần enumerator tiếp theo
        completionHandler(nil, nil)
        renderThumbnailInBackground(identifier) { data in saveCachedThumbnail(identifier, data) }
```

**Logic tạo cache đúng chỗ**: sinh thumbnail ngay lúc `DocumentSessionManager.save()` (mục 1) thành công — không đợi tới lúc Files app hỏi mới tạo. Vậy lúc `fetchThumbnails` được gọi, gần như luôn có cache sẵn, không phải render on-demand.

**"Working set" — khái niệm dễ nhầm**: File Provider hỗ trợ 2 chế độ — item chỉ có *metadata* (chưa tải nội dung, hiện icon xám mờ kiểu "chưa tải về" giống file iCloud chưa download) vs item đã *materialized* (nội dung có sẵn cục bộ). Vì app của bạn lưu file cục bộ hoàn toàn (không phải cloud-sync như Dropbox), **mọi item nên luôn ở trạng thái materialized ngay** — không cần implement logic "tải khi cần" phức tạp như app cloud-storage thật phải làm.

### 4.6 — Compliance: entitlement + App Review + Privacy Manifest

Đây là phần **bắt buộc tuân thủ**, không làm đúng thì build fail, TestFlight fail, hoặc bị App Review từ chối:

**Entitlement (Xcode → Signing & Capabilities)**
| Việc phải làm | Ở target nào | Hậu quả nếu thiếu/sai |
|---|---|---|
| Bật capability **"File Provider"** | Extension target | Extension không được OS coi là File Provider hợp lệ, `add(domain:)` fail |
| Bật **App Groups**, cùng 1 group ID | CẢ app chính lẫn extension | 2 process không đọc chung được App Group container — extension trả list rỗng dù app chính có file |
| App Group ID phải **giống hệt ký tự** ở cả 2 target | — | Lỗi âm thầm, không có log rõ ràng — lỗi hay gặp nhất khi mới làm |
| (Nếu dùng thêm background sync thật) capability **Background Modes** | Extension target | Bỏ qua nếu app chỉ lưu local, không cần cho MVP |

**Privacy Manifest (`PrivacyInfo.xcprivacy`) — bắt buộc từ khi Apple siết chính sách 2024**

File Provider extension chắc chắn động tới **file-timestamp API** (đọc ngày sửa/tạo file để trả `item.contentModificationDate`) — Apple yêu cầu khai báo lý do sử dụng trong `PrivacyInfo.xcprivacy`, thiếu thì **App Store Connect từ chối build ngay từ bước upload**, không cần đợi tới App Review:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
      <string>C617.1</string>
      <!-- "Hiển thị ngày giờ file cho user, chỉ với file do chính app tạo ra hoặc user đưa vào app" — đúng use-case File Provider -->
    </array>
  </dict>
</array>
```

**App Review — không cần Apple duyệt riêng trước (khác 1 số capability khác)**, nhưng cần đảm bảo:
- Extension phải **hoạt động thật**, không phải hình thức — Apple từng từ chối app có File Provider nhưng enumerator trả rỗng/lỗi khi test.
- Xử lý **lỗi mượt, không crash** khi Files app gọi liên tục lúc mạng chậm/App Group tạm khoá (Apple test bằng cách stress-test enumerator, không phải chỉ mở 1 lần).
- Nên bật **Domain Testing Mode** (`NSFileProviderManager.enableTestingMode` khi debug) để tự stress-test enumerator/thumbnail trước khi submit, mô phỏng đúng cách Apple sẽ thử.

### AirPrint — rẻ, cả 2 đối thủ đã có

```
DocumentEditorView.onPrintTapped():
    let printInfo = UIPrintInfo(dutyCycle: .high)
    printInfo.outputType = .general
    let controller = UIPrintInteractionController.shared
    controller.printPageRenderer = sdkSession.printPageRenderer  // [SDK] cấp sẵn nếu SDK có API render-to-print (cả 2 đối thủ dùng đúng class kiểu này)
    controller.present(animated: true)
```

---

## 5. Add file — Local + iCloud `[NATIVE]`, gần như miễn phí

### 5.1 — Luồng import cơ bản

```swift
let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.docx, .xlsx, .pptx, .pdf, .hwp])
picker.allowsMultipleSelection = true
picker.delegate = self
present(picker, animated: true)

// delegate:
func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    for url in urls {
        guard url.startAccessingSecurityScopedResource() else { continue }
        defer { url.stopAccessingSecurityScopedResource() }
        documentManager.importAndCopyToLocalStorage(url)   // copy vào sandbox app, không giữ reference tới file ngoài (tránh mất quyền truy cập sau khi user xoá/di chuyển file gốc)
    }
}
```

**Điểm cần chú ý** (không phải từ đối thủ, mà lỗi thường gặp): phải gọi `startAccessingSecurityScopedResource()` trước khi đọc file từ `UIDocumentPickerViewController`, và nên **copy vào sandbox riêng** thay vì giữ security-scoped bookmark dài hạn — bookmark hết hạn/bị revoke âm thầm là nguồn lỗi "file bị mất" phổ biến.

### 5.2 — iCloud Drive: file trong picker không đồng nghĩa file đã có trên máy

Đây là chỗ hay bị bỏ sót nhất: khi user chọn 1 file từ iCloud Drive trong picker, file đó **có thể chỉ là placeholder** (icon có đám mây, chưa tải nội dung thật về máy — người dùng bật "Optimize storage" thì iOS tự đẩy file ít dùng lên cloud, giữ lại metadata thôi). Copy thẳng placeholder này vào sandbox sẽ ra file 0 byte hoặc lỗi khi SDK mở.

```swift
func importAndCopyToLocalStorage(_ url: URL) {
    var isDownloaded = false
    if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
        isDownloaded = values.ubiquitousItemDownloadingStatus == .current
    }

    if !isDownloaded {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // hiện progress UI "Đang tải từ iCloud..." — KHÔNG copy ngay, phải chờ tải xong
        waitForDownload(url) { completedURL in
            copyToSandbox(completedURL)
        }
    } else {
        copyToSandbox(url)
    }
}
```

**Cách chờ tải xong đúng cách**: dùng `NSMetadataQuery` theo dõi `NSMetadataUbiquitousItemPercentDownloadedKey`/`NSMetadataUbiquitousItemDownloadingStatusKey` trên đúng file đó thay vì poll thủ công bằng timer — tránh vừa tốn pin vừa dễ miss timing (query có callback đúng lúc trạng thái đổi).

### 5.3 — Import nhiều file cùng lúc: xử lý lỗi từng file riêng, không fail cả batch

```swift
func importBatch(_ urls: [URL]) async {
    var succeeded: [Document] = []
    var failed: [(URL, Error)] = []

    for url in urls {
        do {
            let doc = try await importSingle(url)   // mỗi file có timeout riêng (ví dụ file iCloud tải quá lâu)
            succeeded.append(doc)
        } catch {
            failed.append((url, error))   // 1 file lỗi (corrupt, format lạ, tải iCloud fail) không chặn các file còn lại
        }
    }

    if !failed.isEmpty {
        showBatchResultBanner(succeeded: succeeded.count, failed: failed)
        // liệt kê rõ file nào lỗi + lý do — không chỉ "Import thất bại" chung chung
    }
}
```

### 5.4 — File trùng tên

```
importSingle(url):
    tên gốc = url.lastPathComponent
    nếu đã tồn tại file cùng tên trong storage:
        → KHÔNG tự động ghi đè (có thể là 2 file khác nhau trùng tên tình cờ)
        → tự thêm hậu tố "(2)", "(3)"... theo tên còn trống gần nhất
        → (tuỳ chọn nâng cao sau MVP: so sánh nội dung/hash trước, nếu giống hệt thì hỏi "File đã có sẵn, mở bản cũ?")
```

**Điểm cần chú ý**: import Local (`UIDocumentPickerViewController` với `asCopy: true`) không có vấn đề placeholder như iCloud — chỉ iCloud Drive mới cần logic 5.2. Đừng áp dụng chung 1 luồng chờ-tải cho cả 2 nguồn, sẽ làm import Local chậm vô cớ vì check `ubiquitousItemDownloadingStatusKey` trên file local luôn trả về giá trị không áp dụng, tốn 1 nhịp gọi thừa.

---

## 6. iPad multi-pane UI thật + Apple Pencil + keyboard shortcuts `[NATIVE + SDK]`

### 6.1 — Multi-pane bên trong editor (không chỉ ở app-shell)

Đã có kiến trúc app-shell ở mục 3 (`NavigationSplitView` — sidebar/list/detail). Phần riêng ở đây là **multi-pane bên trong chính màn hình editor** — 2 đối thủ không ai làm rõ multi-pane thật ở cấp này (0/2 xác nhận), nhưng A1 có tự build lại navigation layer bên trong document (`ARDKContainerViewController` thay UI mặc định SDK) — nghĩa là muốn có outline/TOC panel + trang đang sửa hiện song song trên iPad, **không dùng nguyên view-controller "all-in-one" của SDK**, phải tự bọc lại:

```swift
struct DocumentEditorSplitView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var outlineVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sizeClass == .regular && outlineVisible {
                OutlineSidebar(entries: session.tocEntries)   // SDK cấp data (kiểu SODKTocEntry) — UI tự build
                    .frame(width: 260)
                Divider()
            }
            SDKEditorViewControllerWrapper(session: session)   // UIViewControllerRepresentable, KHÔNG present full-screen
        }
    }
}
```

**Điểm cần chú ý**: nhúng view controller của SDK qua `UIViewControllerRepresentable` (không `present()`) để nó chia sẻ không gian màn hình với outline panel — hầu hết SDK loại "all-in-one" (như `SODKBasicDocumentViewController`) được thiết kế để present full-screen mặc định, cần test kỹ nó có chịu bị nhúng làm 1 view con hay không trước khi cam kết hướng UI này (1 số SDK khoá cứng full-screen, phải hỏi vendor support trước khi build).

### 6.2 — Apple Pencil: vẽ tay vs Scribble (nhập chữ bằng viết tay) là 2 việc khác nhau

**Vẽ/đánh dấu tay** (annotate, tương đương `DrawRibbon` đã thấy ở SDK Artifex): hook `PKCanvasView` (PencilKit, native) chồng lên trang nếu SDK không expose đủ pressure-sensitivity/double-tap-to-switch-tool:

```swift
let canvas = PKCanvasView()
canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
canvas.drawingPolicy = .pencilOnly   // ngón tay vẫn dùng để cuộn trang, không bị nhầm thành nét vẽ
```

**Double-tap Pencil** (chuyển nhanh bút↔tẩy — hành vi hệ thống, không tự vẽ UI riêng):
```swift
let pencilInteraction = UIPencilInteraction()
pencilInteraction.delegate = self
view.addInteraction(pencilInteraction)

func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    currentTool = currentTool == .pen ? .eraser : .pen   // theo đúng preferredTapAction user đã set trong Settings hệ thống
}
```

**Scribble (viết tay thành chữ vào ô nhập liệu)**: đây KHÔNG tự động có nếu SDK dùng custom text-rendering riêng (rất có thể, vì editor Word cần layout engine riêng, không phải `UITextView` chuẩn) — Scribble chỉ hoạt động trên view implement đúng `UITextInput` protocol. Cần hỏi rõ vendor SDK: nếu editor text view của họ không expose `UITextInput`, Scribble sẽ không chạy ở vùng soạn thảo chính (có thể vẫn chạy ở các ô input phụ như tên file, tìm kiếm — những chỗ dùng `UITextField`/`UITextView` chuẩn của bạn tự build).

### 6.3 — Keyboard shortcuts: routing, không tự implement lại hành vi

```swift
.keyboardShortcut("s", modifiers: .command)   // Save
.keyboardShortcut("b", modifiers: .command)   // Bold
.keyboardShortcut("f", modifiers: .command)   // Find
```
Map trực tiếp qua API editing command của SDK (`session.applyStyle(.bold)` kiểu vậy) — không tự implement bold/italic, chỉ tự làm lớp routing phím → lệnh SDK.

**Điểm cần chú ý — xung đột với keyboard handling nội bộ của SDK**: nếu view controller của SDK tự bắt `Cmd+B`/`Cmd+F` bên trong nó (rất có thể, vì bản thân nó đã có ribbon Bold/Find), `UIKeyCommand`/`.keyboardShortcut` bạn định nghĩa ở tầng app có thể **không bao giờ được gọi tới** — first responder chain sẽ ưu tiên response gần nhất (bên trong SDK) trước khi bubble lên app. Cách kiểm tra: log lại xem action của bạn có được trigger không khi SDK view đang là first responder; nếu không, chỉ cần **không định nghĩa lại** phím đó ở tầng app (để nguyên cho SDK tự xử lý) thay vì cố ép override.

**Discoverability**: giữ phím tắt trùng chuẩn hệ thống (Cmd+S/B/I/U/F/Z) để tự động xuất hiện trong menu "giữ Cmd" trên iPad/Mac Catalyst — không cần tự vẽ bảng phím tắt riêng.

### 6.4 — Trackpad/con trỏ chuột (Magic Keyboard) — persona anchor dùng thật

Vì persona chính (mục 2) là dân pro dùng iPad Pro + Magic Keyboard thay laptop, cần đảm bảo `DocumentEditorView`/`OutlineSidebar` có hover state rõ ràng (`.hoverEffect(.highlight)` trên SwiftUI, hoặc `UIPointerInteraction` ở UIKit) — thiếu phần này thì trải nghiệm dùng trackpad cảm giác vẫn như "app cảm ứng ép dùng chuột", đúng thứ roadmap đang muốn tránh ("không phải app iPhone phóng to").

---

## 7. OCR — scan giấy thành văn bản `[NATIVE]`, KHÔNG có ở SDK (đã xác nhận quét 627 class)

### 7.1 — Luồng scan: dùng document scanner có sẵn, không tự làm camera

```swift
let scanner = VNDocumentCameraViewController()   // native, có sẵn UI quét giấy chuẩn kiểu Notes app —
scanner.delegate = self                          // auto edge-detection + perspective-correction + xoá bóng/glare
present(scanner, animated: true)

func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                   didFinishWith scan: VNDocumentCameraScan) {
    for pageIndex in 0..<scan.pageCount {
        let image = scan.imageOfPage(at: pageIndex)   // đã crop/deskew sẵn, không cần tự xử lý
        ocrQueue.enqueue(image, pageIndex: pageIndex)
    }
}
```

**Điểm cần chú ý**: dùng `VNDocumentCameraViewController` thay vì tự làm camera capture như A1 đang làm (A1 chỉ chụp ảnh thường qua `BSImagePicker` rồi ghép PDF, không có edge-detection) — vừa rẻ hơn (0 dòng UI tự viết) vừa chất lượng nhận diện tốt hơn hẳn vì ảnh đầu vào đã sạch trước khi đưa vào OCR.

### 7.2 — Xử lý nền, không block UI khi scan nhiều trang

```
OCRQueue (background, xử lý tuần tự hoặc giới hạn concurrency ~2-3 trang cùng lúc — Vision khá nặng CPU)
├── mỗi trang: 
│     let request = VNRecognizeTextRequest(recognitionLevel: .accurate, usesLanguageCorrection: true)
│     request.recognitionLanguages = detectedOrUserSelectedLanguages   // xem 7.3
│     handler = VNImageRequestHandler(cgImage: page.cgImage)
│     try handler.perform([request])
├── mỗi trang xong → update progress UI ("Đang nhận diện trang 2/5")
└── toàn bộ xong → build output (7.5)
```

### 7.3 — Ngôn ngữ nhận diện — dễ bị bỏ sót ở app nhắm nhiều thị trường

`VNRecognizeTextRequest` cần biết trước ngôn ngữ để nhận diện chính xác (không tự động đa ngôn ngữ hoàn hảo). Vì roadmap không giới hạn 1 thị trường, cần:

```swift
request.recognitionLanguages = ["vi-VN", "en-US"]   // KHÔNG để mặc định chỉ "en-US" — sai hoàn toàn với tài liệu tiếng Việt

// Lấy danh sách ngôn ngữ hỗ trợ thật của thiết bị/OS version đang chạy, không hardcode:
let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: VNRecognizeTextRequestRevision3)
```

**Cách chọn**: mặc định theo ngôn ngữ hệ thống của user + cho phép chọn tay trong UI trước khi scan (không cố auto-detect ngôn ngữ từ ảnh — không chính xác và tốn thêm 1 pass xử lý).

### 7.4 — Độ tin cậy (confidence) — không im lặng khi nhận diện sai

```swift
for observation in results as! [VNRecognizedTextObservation] {
    guard let candidate = observation.topCandidates(1).first else { continue }
    if candidate.confidence < 0.5 {
        lowConfidenceBlocks.append(observation)   // đánh dấu để UI highlight vùng nghi ngờ sai
    }
}
```

Sau khi OCR xong, nếu output là "tạo file .docx sửa được" (7.5b), nên highlight nhẹ các đoạn confidence thấp để user tự soát lại — im lặng coi như đúng 100% là nguồn lỗi phổ biến nhất của tính năng OCR (chữ viết tay, ảnh mờ, font lạ).

### 7.5 — 2 dạng output, khác nhau về độ phức tạp

**(a) PDF "searchable"** (rẻ hơn — chỉ cần chọn được/tìm được chữ, không cần sửa được):
```
với mỗi trang:
    vẽ ảnh scan vào PDF page (như bình thường)
    vẽ ĐÈ text nhận diện được lên đúng vị trí bounding box, nhưng invisible
    (CGContext: set text rendering mode Tr 3 — "không tô màu, không vẽ" — text vẫn select/copy/search được dù mắt không thấy)
    → dùng PDFKit/CGPDFContext, hoàn toàn native
```

**(b) File .docx sửa được** (đắt hơn — cần dựng lại cấu trúc văn bản thật):
```
gom các text block theo thứ tự đọc (trên-xuống, trái-qua-phải theo bounding box)
→ build <w:p>/<w:r> XML tương ứng (xem cấu trúc OOXML ở mục 8)
→ KHÔNG giữ được layout gốc chính xác (bảng, cột, font) — chỉ ra được văn bản thuần
→ cân nhắc: MVP chỉ cần (a), để (b) cho phase sau nếu user thật sự cần "sửa được" chứ không chỉ "tìm được"
```

**Điểm cộng cho positioning "on-device"**: toàn bộ pipeline OCR này chạy 100% on-device (Vision framework không gọi mạng) — khớp trực tiếp và củng cố pillar 2 ("documents never leave your device"), khác hẳn nhóm AI ở mục 11 (chắc chắn phải gọi cloud). Đáng nhấn mạnh sự khác biệt này rõ trong UI/marketing: OCR = an toàn tuyệt đối, AI = có gửi đi (và phải xin phép rõ ràng).

---

## 8. Merge / Split / Compress — Word/PDF/PPT `[TỰ BUILD]`, không có ở SDK lẫn 2 đối thủ

Đây là mục tốn công thật nhất trong MVP vì phải viết riêng theo từng định dạng. **Trước khi tự build**: kiểm tra SDK cuối cùng bạn license — nếu không phải Artifex (ví dụ PSPDFKit/Nutrient) có thể đã có sẵn API merge/split/compress riêng cho PDF (khác Artifex, SDK này KHÔNG có) — phần PDF dưới đây chỉ cần làm nếu SDK không cấp sẵn. Phần Word/PPT thì gần như chắc chắn phải tự làm ở mọi SDK thương mại loại này.

### 8.1 — PDF: rẻ nhất, dùng `PDFKit` (native, độc lập với SDK license)

```swift
// Merge
let merged = PDFDocument()
for doc in inputDocs {
    for i in 0..<doc.pageCount { merged.insert(doc.page(at: i)!, at: merged.pageCount) }
}

// Split (theo range hoặc mỗi N trang 1 file)
let part = PDFDocument()
for i in range { part.insert(original.page(at: i)!, at: part.pageCount) }

// Compress — PDFKit không nén trực tiếp, phải re-render:
// (1) giảm resolution ảnh nhúng bằng CGImage downsample trước khi vẽ lại vào CGPDFContext
// (2) hoặc dùng CGPDFContext vẽ lại từng trang ở DPI thấp hơn nếu chấp nhận rasterize (mất text-selectable)
```

**Compress chi tiết hơn** — nén thật (không rasterize, giữ text chọn được) đòi hỏi duyệt object stream của PDF tìm ảnh nhúng, không có API 1 dòng:
```
với mỗi page:
    duyệt content stream tìm XObject loại /Image
    lấy CGImage gốc → downsample (giữ tỉ lệ, giới hạn cạnh dài theo % user chọn: 100%/70%/50%)
    encode lại JPEG quality thấp hơn (0.5–0.7 thường đủ, giảm size rõ rệt mà mắt khó nhận ra)
    thay object ảnh cũ bằng ảnh mới trong content stream, giữ nguyên vị trí/kích thước hiển thị
    → text layer (nếu có) giữ nguyên, không đụng vào — đây là điểm khác biệt so với rasterize toàn trang
```

### 8.2 — DOCX/PPTX: không có PDFKit tương đương, phải thao tác trực tiếp cấu trúc file

Đây là file ZIP chứa XML (chuẩn OOXML) — không cần SDK, nhưng cần hiểu đúng cấu trúc và **dùng XML parser thật, không string-concat/regex** (regex trên XML rất dễ làm hỏng file khi gặp ký tự đặc biệt hoặc namespace lồng nhau):

```
docx/pptx = ZIP chứa:
  word/document.xml (hoặc ppt/slides/slideN.xml — PPTX mỗi slide 1 file XML riêng, khác DOCX gộp 1 file)
  word/media/*  (ảnh nhúng)
  [Content_Types].xml, _rels/*  ← khai báo quan hệ giữa các phần, PHẢI cập nhật đồng bộ khi thêm/xoá nội dung

Thư viện dùng: ZIPFoundation (unzip/zip) + XMLParser hoặc XMLDocument (Foundation native, không cần thêm dependency ngoài cho XML)
```

**Merge (Word)**:
```
1. unzip cả 2 file
2. parse document.xml của cả A và B bằng XMLDocument (không regex)
3. lấy toàn bộ node con của <w:body> trong B (trừ <w:sectPr> — phần khai báo page setup, không merge cái này)
4. append các node đó vào cuối <w:body> của A, trước node <w:sectPr> cuối cùng
5. gộp media/: copy ảnh từ B sang A, đổi tên tránh trùng (ví dụ prefix "b_" cho toàn bộ ảnh từ file B)
6. QUAN TRỌNG: sửa lại r:id reference trong các node vừa copy — mỗi ảnh trong XML tham chiếu qua r:id
   trỏ tới document.xml.rels, không phải trỏ thẳng tên file — nối 2 file mà không remap r:id sẽ ra
   r:id trùng nhau (id của A và B đều bắt đầu từ rId1) → ảnh của B hiển thị sai hoặc vỡ hoàn toàn
7. update [Content_Types].xml nếu B có loại nội dung A chưa có (ví dụ B có ảnh .webp mà A trước đó không có ảnh nào)
8. re-zip (giữ đúng thứ tự: [Content_Types].xml phải là entry đầu tiên trong zip theo spec OOXML)
```

**Merge (PowerPoint)** — khác Word ở chỗ mỗi slide là 1 file riêng, việc merge đơn giản hơn về nội dung nhưng phức tạp hơn về đánh số:
```
1. copy toàn bộ ppt/slides/slideN.xml từ B sang A, đổi số thứ tự file tiếp nối sau slide cuối của A
2. update ppt/presentation.xml của A — thêm entry <p:sldId> mới trỏ tới các slide vừa copy
3. update ppt/_rels/presentation.xml.rels — khai báo quan hệ id → file cho từng slide mới
4. slide master/layout: nếu B dùng layout khác A, phải copy luôn slideLayout + slideMaster liên quan,
   không chỉ copy mỗi slideN.xml (thiếu bước này slide hiện đúng nội dung nhưng sai theme/font hoàn toàn)
```

**Split** (ngược lại của merge — tách 1 khoảng trang/slide ra file mới): tương tự nhưng theo chiều ngược, cộng thêm bước dọn rác — xoá reference tới phần không còn dùng (ảnh chỉ xuất hiện ở phần bị cắt bỏ, style/font không còn slide nào dùng) để file mới không phình to vì rác thừa.

**Compress (nén ảnh nhúng, không đổi nội dung)**:
```
1. duyệt word/media/*.png|jpg (docx) hoặc ppt/media/*.png|jpg (pptx)
2. downsample qua CGImage (giữ tối đa cạnh dài 1600px hoặc theo % tuỳ chọn user)
3. ghi đè lại vào archive, giữ NGUYÊN tên file (reference trong XML không đổi — đây là lý do compress
   dễ hơn merge nhiều, không phải sửa XML, chỉ thay nội dung file ảnh bên trong zip)
```

### 8.3 — Vận hành: file lớn, chạy nền, và validate trước khi báo thành công

```
MergeSplitCompressOperation
├── chạy trên background queue (không phải main thread) — file PPTX nhiều ảnh có thể vài trăm MB
├── progress callback theo % (số slide/trang đã xử lý / tổng)
├── giới hạn kích thước input hợp lý cho MVP (ví dụ cảnh báo nếu tổng >200MB — tránh hết bộ nhớ khi
   load nhiều PDFDocument/XMLDocument cùng lúc trên thiết bị RAM thấp)
└── SAU khi ghi xong: mở lại file vừa tạo bằng chính SDK/engine của app để xác nhận parse được
     (không chỉ tin "ghi file không lỗi" — 1 file XML hợp lệ về mặt cú pháp vẫn có thể sai quan hệ
      r:id và mở lên bị lỗi trong Word thật dù app tự mở lại "nhìn có vẻ ổn")
```

**Điểm cần chú ý — bẫy hay gặp nhất**: quên đồng bộ `[Content_Types].xml`/`_rels/*` sau khi thêm nội dung mới là nguyên nhân phổ biến nhất khiến file merge "mở được trong app tự build của bạn" (vì engine tự viết dễ dãi bỏ qua lỗi) nhưng **mở lỗi/báo hỏng trong Word/PowerPoint thật** — luôn test round-trip bằng Word/PowerPoint thật (hoặc ít nhất Google Docs/Sheets import), không chỉ test bằng chính SDK bạn đang dùng để mở lại.

---

## 9. Note / comment dạng text (không cần Pencil) `[SDK, khả năng cao có sẵn]`

Nếu SDK bạn chọn cùng họ kiến trúc đã thấy (ribbon-based, có `Review`/`Annotate` ribbon controller riêng biệt) — đây gần như chỉ là **bật 1 ribbon có sẵn + tự build UI danh sách comment**, không phải viết engine comment từ đầu.

### 9.1 — Data model (khớp đúng model comment thật của Word/PDF, không tự chế cấu trúc riêng)

```
Comment
├── id
├── anchorRange (vị trí trong text, hoặc bounding box nếu là PDF annotation)
├── author (tên user — cần có, kể cả app chỉ 1 user, vì file share ra ngoài người khác mở phải thấy ai comment)
├── createdAt
├── body: String
├── resolved: Bool
└── replies: [Comment]   ← Word/PDF chuẩn hỗ trợ reply theo thread, không phải comment phẳng độc lập
```

```
CommentManager (bọc quanh API comment/annotation của SDK)
├── addComment(at range/position, text) → gọi API insert-comment của SDK (nếu Word module) hoặc insert-annotation (nếu PDF module)
├── replyToComment(threadId, text) → API append-reply nếu SDK hỗ trợ thread, nếu không: tự nối chuỗi text
│     có prefix "— reply từ [tên]" vào body comment gốc (giải pháp tạm nếu SDK không có thread thật)
├── resolveComment(id) → đánh dấu đã xử lý — SDK Word chuẩn có field riêng cho việc này (giữ được resolved
│     state khi mở lại bằng Word thật ở máy khác, không chỉ ẩn đi phía app)
├── SDK tự lo phần lưu vào file (comment thật sự nằm trong .docx/.pdf, không phải lưu riêng ở app —
│     xem 9.3 vì sao điều này quan trọng)
└── tự build: sidebar hiển thị list comment (SDK thường chỉ cấp data model, không cấp UI list đẹp)
```

### 9.2 — UI: neo vị trí + mở rộng thread

```
Trong DocumentEditorView:
├── mỗi comment có 1 indicator nhỏ ở lề trang (margin) tại đúng vị trí anchor
├── tap vào indicator → mở popover/sidebar hiện toàn bộ thread (comment gốc + replies)
├── nếu nhiều comment gần nhau (cùng 1 vùng nhỏ) → gộp nhóm, hiện số lượng, tap mới tách ra từng cái
│     (tránh đè chồng indicator không đọc được khi văn bản dày comment)
└── comment đã resolved → làm mờ/thu gọn mặc định, không chiếm chỗ nhưng vẫn truy cập được
```

### 9.3 — Persistence: bắt buộc kiểm chứng comment nằm THẬT trong file, không phải lưu riêng ở app

Đây là rủi ro dễ bị bỏ sót nhất khi tích hợp: 1 số SDK/API "comment" thực chất chỉ lưu annotation vào **database riêng của SDK** (không ghi ngược vào file .docx/.pdf chuẩn) — nghĩa là mở file đó bằng Word/Acrobat thật ở máy khác sẽ **không thấy comment nào cả**, dù trong app bạn hiển thị đầy đủ.

```
Cách xác nhận trước khi build UI phía trên tính năng này:
1. Thêm 1 comment test qua API SDK
2. Export/save file ra ngoài sandbox app
3. Mở file đó bằng Word/Acrobat thật (không phải bằng lại chính app bạn hoặc chính SDK đó)
4. Comment còn hiển thị đúng vị trí, đúng tác giả → SDK ghi comment chuẩn vào file thật, an toàn để build tiếp
   Comment biến mất → SDK chỉ lưu annotation riêng, cần hỏi vendor có API "export comment vào file chuẩn OOXML/PDF" không,
   nếu không có thì phải tự viết XML comment (word/comments.xml + reference trong document.xml) — tốn công hơn nhiều
```

**Điểm cần chú ý**: kiểm tra bước 9.3 **trước khi** build UI sidebar/thread ở 9.2 — nếu SDK không ghi comment chuẩn vào file, hướng làm hoàn toàn khác (phải tự sinh XML), ảnh hưởng ước lượng effort của cả mục này.

---

## 10. E-signature + watermark

### 10.1 — E-signature `[SDK, nếu chọn đúng SDK có PKI]` — 2 tầng, không chỉ vẽ tay

Từ teardown A1: SDK loại này (nếu cùng họ Artifex) hỗ trợ 2 tầng khác nhau về giá trị pháp lý — nên build cả 2, hiểu rõ khác biệt trước khi thiết kế UI (đừng gộp chung 1 nút "Ký" mập mờ):

```
SignatureFlow
├── Tầng 1 — chữ ký vẽ tay (rẻ, làm trước):
│     PKCanvasView hoặc custom draw view → xuất ra image → SDK.placeSignatureImage(at: position)
│     Giá trị: tương đương "chữ ký điện tử cơ bản" — đủ cho hợp đồng thông thường giữa 2 bên đồng thuận,
│     nhưng KHÔNG chứng minh được danh tính người ký nếu có tranh chấp (ai cũng vẽ được hình giống bất kỳ ai)
├── Tầng 2 — ký số PKI thật (làm sau, giá trị pháp lý cao hơn):
│     ├── import certificate người dùng (.p12) → Keychain (KHÔNG lưu private key ở đâu khác ngoài Keychain)
│     ├── SDK.signDocument(with: certificate) → nhúng chữ ký số vào file (verify được bằng Acrobat/các tool chuẩn,
│     │     không chỉ verify được trong chính app bạn — đây là điểm khác biệt cốt lõi so với Tầng 1)
│     └── UI hiển thị trạng thái "Verified/Unverified" khi mở lại file đã ký (đọc cert chain từ SDK)
```

**Lưu ý không phải tư vấn pháp lý, nhưng cần biết để thiết kế đúng UI**: giá trị pháp lý của chữ ký điện tử (kiểu Tầng 1 vẽ tay) vs chữ ký số có chứng thực (Tầng 2, PKI) khác nhau tuỳ luật từng nước (ở EU có khung eIDAS phân 3 cấp độ, ở US có ESIGN Act) — không tự khẳng định trong app "chữ ký này có giá trị pháp lý" một cách chung chung, để tránh cam kết sai với user. An toàn nhất: mô tả đúng cơ chế kỹ thuật ("chữ ký số có chứng thực, verify được bằng Acrobat") thay vì khẳng định về mặt pháp lý.

**UI đặt chữ ký** (cả 2 tầng dùng chung 1 luồng đặt vị trí):
```
1. user chọn "Thêm chữ ký" → hiện overlay cho phép kéo-thả 1 khung chữ nhật lên đúng vị trí trên trang
2. resize khung theo kéo góc (giữ tỉ lệ chữ ký gốc nếu là Tầng 1 vẽ tay, tránh méo hình)
3. xác nhận → SDK render chữ ký (ảnh hoặc chứng thực số) vào đúng khung đó, ở đúng trang
```

**Verify khi mở lại file đã ký** (áp dụng cho Tầng 2):
```swift
let verifyResult = session.verifySignatures()   // SDK trả về danh sách chữ ký + trạng thái từng cái
for sig in verifyResult {
    switch sig.status {
    case .valid:          showBadge(.green, "Đã xác thực — \(sig.signerName)")
    case .modifiedAfterSigning: showBadge(.red, "File đã bị sửa sau khi ký")   // quan trọng — phải cảnh báo rõ, không im lặng
    case .certificateExpired:   showBadge(.orange, "Certificate hết hạn")
    case .unknown:         showBadge(.gray, "Không xác thực được")
    }
}
```

### 10.2 — Watermark `[TỰ BUILD]` — không có ở SDK

```
WatermarkRenderer
├── input: text hoặc image watermark + opacity + rotation + vị trí (tile/center/diagonal)
├── PDF: vẽ đè lên mỗi trang qua CGPDFContext trước khi save (native, không cần SDK)
├── Word/PPT: phức tạp hơn — chèn textbox/shape watermark vào từng slide/page XML
│     (PowerPoint: watermark thường là 1 <p:sp> lặp lại trên slide master — chèn 1 lần vào slideMaster.xml
│      áp dụng cho toàn bộ slide, không phải lặp thủ công từng slide;
│      Word: watermark chuẩn là 1 shape trong header.xml, áp dụng qua tất cả trang tự động vì header lặp lại theo section)
└── convert-to-PDF trước khi watermark đơn giản hơn nhiều nếu chấp nhận watermark chỉ áp dụng lúc export/share
    (không sửa file gốc) — cân nhắc giới hạn scope này cho MVP để giảm effort
```

**Logic vẽ watermark trên PDF (chi tiết)**:
```swift
func drawWatermark(on page: PDFPage, text: String, opacity: CGFloat, rotationDegrees: CGFloat) {
    let bounds = page.bounds(for: .mediaBox)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    // vẽ text xoay chéo giữa trang, lặp lại dạng tile nếu muốn watermark phủ kín (chống crop-out 1 góc)
    context.saveGState()
    context.translateBy(x: bounds.midX, y: bounds.midY)
    context.rotate(by: rotationDegrees * .pi / 180)
    text.draw(at: .zero, withAttributes: [.font: font, .foregroundColor: color.withAlphaComponent(opacity)])
    context.restoreGState()
}
```

**Điểm cần chú ý**: watermark áp lúc export (không sửa file gốc lưu trong app) là lựa chọn hợp lý cho MVP — vừa giảm effort (chỉ cần làm cho PDF export, không phải sửa cấu trúc XML Word/PPT gốc), vừa an toàn hơn (user không lo watermark "dính chết" vào file gốc nếu chọn nhầm).

---

## 11. AI tóm tắt / viết lại / hỏi-đáp tài liệu `[TỰ BUILD — tích hợp LLM API]`

Xác nhận chắc: không đối thủ nào có, không phải "chọn model nào cho giống" mà là làm từ đầu.

### 11.1 — Pipeline chính

```
DocumentAIService
├── extractText(from: DocumentSession) -> String
│     lấy qua API extract-text của SDK (hầu hết SDK document đều có, không cần OCR nếu file gốc đã có text layer)
├── chunkIfNeeded(text) — tài liệu dài (>context window model) → chia theo section/heading, không cắt cứng theo ký tự
├── AI operations:
│     summarize(chunks) → map-reduce nếu nhiều chunk: tóm tắt từng chunk → tóm tắt-của-tóm-tắt
│     rewrite(selection, instruction) → chỉ gửi đoạn được chọn (không gửi cả file) — nhanh hơn, rẻ hơn, an toàn hơn (ít data nhạy cảm gửi đi hơn)
│     ask(question, context: relevantChunks) → cần retrieval đơn giản (tìm chunk liên quan câu hỏi trước khi hỏi model) nếu file dài, tránh nhét cả file vào mỗi câu hỏi
└── ghi lại kết quả:
      rewrite → áp trực tiếp vào SDK session tại đúng vị trí selection (session.replaceText(range, with:))
      summarize/ask → hiển thị riêng (side panel), không tự sửa file trừ khi user bấm "chèn vào tài liệu"
```

### 11.2 — KHÔNG gọi LLM API trực tiếp từ app — cần 1 backend proxy mỏng

Đây là điểm kiến trúc quan trọng nhất của mục này, dễ bị bỏ qua ở giai đoạn MVP vì muốn nhanh: nếu nhúng thẳng API key của OpenAI/Anthropic/Gemini vào code app rồi gọi thẳng từ client, **API key đó nằm trong binary, extract được bằng đúng kiểu static analysis đã dùng để phân tích 2 đối thủ trong tài liệu này** (`strings`/`nm` trên binary, hoặc dễ hơn — network traffic capture qua proxy) — ai cũng lấy được key, dùng chùa quota trả phí của bạn.

```
Kiến trúc đúng:
App  →  Backend riêng của bạn (Cloud Function/thin API server)  →  LLM provider (OpenAI/Anthropic/Gemini...)
     ↑                                                          ↑
  không giữ API key thật                                  API key thật chỉ nằm ở server, không bao giờ xuống client

App xác thực với backend của bạn qua:
  - App Attest (native, đã thấy A1 dùng đúng cơ chế này — com.apple.developer.devicecheck.appattest-environment)
    → chứng minh request đến từ app thật (build đã ký hợp lệ), không phải script giả mạo gọi thẳng backend
  - hoặc đơn giản hơn cho MVP: Firebase App Check (wrap sẵn logic tương tự, ít công sức tự viết hơn App Attest thô)
```

### 11.3 — Rate limit & chi phí theo user (LLM API tính tiền theo token, khác mọi SDK khác trong tài liệu này)

```
Backend proxy:
├── mỗi request AI → check quota còn lại của user (theo tier: free có giới hạn/tháng, Pro cao hơn/không giới hạn)
├── log token usage thật (input + output token, không chỉ đếm số request) → đối chiếu đúng chi phí thật trả cho provider
├── rate limit theo user + theo toàn hệ thống (tránh 1 user spam làm cạn quota chung, hoặc bill tăng vọt bất thường)
└── circuit breaker: nếu provider trả lỗi liên tục (rate limit từ phía họ, hoặc downtime) → tạm ngưng nhận request mới,
      trả lỗi rõ ràng cho app thay vì để user chờ timeout im lặng
```

### 11.4 — Streaming response (UX quan trọng — AI trả lời không nên "im lặng rồi hiện hết 1 lúc")

```swift
for try await chunk in aiService.streamRewrite(selection: text, instruction: prompt) {
    displayedText += chunk   // hiện dần từng phần, giống ChatGPT/Claude — cảm giác phản hồi nhanh hơn nhiều
                              // dù tổng thời gian xử lý thực tế không đổi
}
```

### 11.5 — Xử lý lỗi/fallback

```
AI operation thất bại (provider down, hết quota, timeout, tài liệu quá dài vượt context window):
    → KHÔNG để UI treo/im lặng — hiện lỗi cụ thể theo loại:
        hết quota → CTA nâng cấp Pro (nếu đúng nguyên nhân) hoặc "thử lại sau" (nếu do hệ thống)
        tài liệu quá dài → báo rõ "tài liệu vượt giới hạn xử lý AI hiện tại (~X trang)", không fail âm thầm
        provider timeout → cho phép retry, không tự động retry ngầm nhiều lần (tốn thêm token/chi phí mỗi lần thử)
```

### 11.6 — Privacy: hành động AI phải là lựa chọn rõ ràng của user

**Điểm cần chú ý (liên quan trực tiếp pillar 2 "on-device, không upload")**: nếu dùng AI qua API cloud (gần như chắc chắn ở MVP, on-device LLM chưa đủ tốt cho việc này năm nay), cần tách rõ trong UI: hành động AI là **lựa chọn rõ ràng của user** (nút "Tóm tắt bằng AI" — user biết đoạn đó sẽ được gửi đi), không phải mặc định luôn bật — để không mâu thuẫn với thông điệp "documents never leave your device" ở pillar 2. Cách làm sạch: chỉ gửi phần user chọn/yêu cầu, không tự động gửi toàn bộ tài liệu ngầm khi mở file.

**Liên quan thêm đến Privacy Manifest**: nếu backend proxy (11.2) dùng 1 SDK bên thứ 3 để gọi LLM provider, kiểm tra SDK đó có cần khai báo trong `PrivacyInfo.xcprivacy` không (thường không áp dụng nếu logic gọi API nằm hoàn toàn ở backend, không có SDK client-side nào chạy trong app — thêm 1 lý do nên đặt toàn bộ logic gọi LLM ở server, không phải trong app).

---

## Tổng hợp effort — nhìn lại theo 3 nhóm

| Nhóm | Tính năng | Vì sao |
|---|---|---|
| **Rẻ (native/SDK có sẵn, chỉ cần wire đúng)** | Core editing, AirPrint, Add file Local/iCloud, OCR (Vision), layout adaptive | Framework Apple hoặc API SDK đã có, việc chính là kiến trúc gọi đúng chỗ |
| **Trung bình (SDK có phần, tự build phần UI/wrap)** | Autosave/crash-recovery, iPad multi-pane, Note/comment, E-signature | SDK cấp data/API gốc nhưng UI và logic nghiệp vụ phải tự làm |
| **Đắt (không ai có sẵn, tự viết từ đầu)** | Files app provider, Merge/Split/Compress (đặc biệt Word/PPT), Watermark, AI | Không SDK nào (kể cả đối thủ) có sẵn — đúng là USP thật, nhưng cũng đúng là chi phí thật, nên confirm lại timeline 1–5 tháng đã hợp lý với khối này chưa |

---

*Dựa trên `Feature-Integration-Comparison.md` + `Artifex-SODK-Analysis.md` (static analysis 2 IPA đối thủ) và `product-strategy-master.md` (roadmap Phase 0). Tên class SDK dùng minh hoạ theo pattern Artifex đã quan sát được — đổi theo API thật của SDK bạn chọn license.*
