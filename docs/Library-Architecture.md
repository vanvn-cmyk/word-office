# Kiến trúc "Tủ hồ sơ" (Mục 10 MVP) — chi tiết & sơ đồ

> **Mục file này:** giải thích kỹ 1 mục duy nhất — core loop MVP "Tủ hồ sơ" — vì đây là phần mới nhất và dễ confused nhất. Đọc file này TRƯỚC khi code Sprint 0.2 nhóm A.
> **Cập nhật:** 2026-08-27
> **Song song với:** `PHASE_1_ARCHITECTURE.md` v2.2 (arch tổng) + `Phase0-Implementation-Logic-v2.md` mục 10 (logic chi tiết per feature)

---

## 1. 1 câu tóm tắt

App mở → xin quyền 1 **thư mục** trên máy (iCloud Drive/Local) → tự quét thư mục đó → hiện danh sách tài liệu trong "Tủ hồ sơ" → user gán trạng thái (Nháp/Đã xem/Đã ký/Đã gửi) + đặt nhắc → mở app lần sau thấy tủ tự đầy sẵn, cần gì làm luôn, khỏi phải "Add file" thủ công.

**File `.docx`/`.pdf` GỐC nằm nguyên chỗ user cấp quyền — app KHÔNG copy, KHÔNG di chuyển.** App chỉ lưu **metadata riêng** (status, nhắc) trong sandbox app.

---

## 2. 3 loại data, 3 nơi lưu — sơ đồ tổng

```
┌──────────────────────────────────────────────────────────────────────────┐
│  THIẾT BỊ USER                                                            │
│                                                                            │
│  ┌────────────────────────────────────┐                                   │
│  │ Thư mục user CẤP QUYỀN (bên ngoài) │                                   │
│  │                                    │                                   │
│  │  iCloud Drive / Documents / Work / │                                   │
│  │    ├── hopdong-2026.docx    ◄──────┼── 1️⃣ FILE GỐC — không copy       │
│  │    ├── baocao.xlsx                 │    (app đọc/ghi qua bookmark)    │
│  │    ├── quote.pdf                   │                                   │
│  │    └── ...                         │                                   │
│  └────────────────────────────────────┘                                   │
│                                                                            │
│  ┌────────────────────────────────────┐   ┌───────────────────────────┐  │
│  │ App Sandbox                        │   │ Keychain (iOS)            │  │
│  │  (Group Container — share với      │   │                           │  │
│  │   FileProvider Sprint 0.3)         │   │  ┌──────────────────┐    │  │
│  │                                    │   │  │ FolderBookmark   │    │  │
│  │  ┌──────────────────────────┐     │   │  │   bookmarkData   │◄───┼── 3️⃣ QUYỀN
│  │  │ metadata.sqlite          │◄────┼───┼──│   displayPath    │    │    THƯ MỤC
│  │  │                          │     │   │  │   grantedAt      │    │    (bền vững qua
│  │  │  Table: DocumentMetadata │     │   │  └──────────────────┘    │    uninstall,
│  │  │  ┌───────────────────┐  │     │   │                           │    encrypted)
│  │  │  │ documentID (PK)   │  │◄────┼───┼── 2️⃣ METADATA           │  │
│  │  │  │ status            │  │     │   │    RIÊNG (status,        │  │
│  │  │  │ lastOpenedAt      │  │     │   │    nhắc) — KHÔNG          │  │
│  │  │  │ lastModifiedAt    │  │     │   │    ghi vào file gốc       │  │
│  │  │  │ remindAt?         │  │     │   │                           │  │
│  │  │  └───────────────────┘  │     │   └───────────────────────────┘  │
│  │  └──────────────────────────┘     │                                    │
│  └────────────────────────────────────┘                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### Chi tiết 3 nơi

| # | Loại | Lưu ở | Bền vững qua | Sync iCloud? |
|---|---|---|---|---|
| **1️⃣** | **File gốc** `.docx`/`.xlsx`/`.pdf`... | Ở nguyên chỗ user cấp quyền (iCloud Drive/Local/...). App KHÔNG copy. | Uninstall app (file thuộc user, không phải app) | Nếu user để trong iCloud Drive thì có (do iOS, không phải app) |
| **2️⃣** | **`DocumentMetadata`** (status, remindAt, lastOpenedAt) | `metadata.sqlite` trong App Group Container | Bị xoá khi user gỡ app | **KHÔNG** (chốt local only 27/08). Đổi status iPhone → iPad không thấy |
| **3️⃣** | **`FolderBookmark`** (quyền truy cập thư mục cấp) | Keychain (SecItem) | **Còn sau uninstall + reinstall** (Keychain sống độc lập) | Không (mặc định OFF cho app data) |

### Tại sao KHÔNG copy file gốc vào app?

- **Dung lượng**: 500 tài liệu × 10MB = 5GB copy trùng, phá bộ nhớ user
- **Lệch bản**: user sửa file bằng Word desktop (qua iCloud) → 2 bản không đồng bộ
- **Xoá gốc**: user xoá file trong Files app → app vẫn hiện bản copy cũ, confused
- **Bài học từ đối thủ**: 2/2 app đối thủ đã phân tích đều làm sai kiểu này (copy hết vào sandbox) → user phàn nàn tốn bộ nhớ

**Ngoại lệ duy nhất**: luồng phụ Add file thủ công (§4.5 `Phase0-Implementation-Logic-v2.md`) — file nhận qua Mail/AirDrop nằm ngoài thư mục cấp quyền → phải copy vào sandbox vì không có cách nào truy cập lại.

---

## 3. Kiến trúc code — 3 layer + 1 store

Tuân đúng MVVM + SOLID (không đổi so với arch v2.2 §3):

```
┌─────────────────────────────────────────────────────────────────────┐
│  VIEW LAYER (SwiftUI)                                                │
│                                                                       │
│  RootView                                                             │
│    └── if folderPermissionGranted:                                    │
│          LibraryView                    ← trang chủ Tủ hồ sơ         │
│            ├── DocumentCard × N          (badge draftCount)           │
│            │     ├── DocumentStatusPicker (swipe/menu)                │
│            │     └── RemindAtField (sheet)                            │
│            └── ReauthorizePermissionCTA (khi bookmark revoke)         │
│        else:                                                          │
│          FolderPermissionOnboarding    ← first-run xin quyền          │
│                                                                       │
│  ▲ Chỉ đọc @Observable, không gọi service trực tiếp                  │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ @Bindable / @Environment
                              │
┌─────────────────────────────────────────────────────────────────────┐
│  VIEWMODEL LAYER (@Observable @MainActor)                            │
│                                                                       │
│  LibraryViewModel                                                     │
│    ├── documents: [(DocumentRef, DocumentMetadata)]                  │
│    ├── draftCount: Int (computed)                                     │
│    ├── loadLibrary() async                                            │
│    ├── setStatus(_ status: DocumentStatus, for: DocumentRef) async    │
│    └── setReminder(_ date: Date?, for: DocumentRef) async             │
│                                                                       │
│  FolderPermissionViewModel                                            │
│    ├── permissionState: .notGranted | .granted | .revoked            │
│    └── requestPermission() async                                      │
│                                                                       │
│  ▲ KHÔNG import SwiftUI, KHÔNG import SDK, KHÔNG import GRDB/SwiftData│
│    Chỉ import Foundation + protocol từ Services/Protocols/           │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ init injection (DIP)
                              │
┌─────────────────────────────────────────────────────────────────────┐
│  SERVICE LAYER — Protocol (ISP nhỏ) + Impl                           │
│                                                                       │
│  Protocols (Services/Protocols/Library/)                              │
│    ┌─────────────────────────────────┐                               │
│    │ FolderPermissionGranting        │ ─┐                            │
│    │   requestFolderAccess() async   │  │                            │
│    │     -> FolderBookmark?          │  │                            │
│    └─────────────────────────────────┘  │                            │
│    ┌─────────────────────────────────┐  │                            │
│    │ FolderBookmarkResolving         │  │                            │
│    │   loadSaved() -> FolderBookmark?│  ├─ inject vào LibraryViewModel│
│    │   resolve(_:) throws -> URL     │  │                            │
│    │   save(_ bookmark:)             │  │                            │
│    └─────────────────────────────────┘  │                            │
│    ┌─────────────────────────────────┐  │                            │
│    │ DocumentLibraryScanning         │  │                            │
│    │   scan(folder: URL) async       │  │                            │
│    │     -> [DocumentRef]            │  │                            │
│    └─────────────────────────────────┘  │                            │
│    ┌─────────────────────────────────┐  │                            │
│    │ MetadataStoring                 │  │                            │
│    │   fetch(id:) -> DocumentMetadata│  │                            │
│    │   upsert(_ metadata:)           │  │                            │
│    │   draftCount() -> Int           │  │                            │
│    │   dueReminders(now:) -> [ID]    │  │                            │
│    └─────────────────────────────────┘ ─┘                            │
│                                                                       │
│  Implementations (Services/Implementations/Native/)                   │
│    ├── FolderPermissionPicker  (UIDocumentPickerViewController)      │
│    ├── FolderBookmarkStore     (Keychain SecItem)                    │
│    ├── DocumentLibraryScanner  (FileManager + NSMetadataQuery)       │
│    └── MetadataStoreImpl       (GRDB HOẶC SwiftData — chốt A0)       │
│                                                                       │
│  ▲ CHỈ layer này biết Keychain/FileManager/SQLite tồn tại            │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  APP-LEVEL STORE (@Observable @MainActor) — share qua Environment    │
│                                                                       │
│  LibraryStore                                                         │
│    ├── documents: [(DocumentRef, DocumentMetadata)]                  │
│    ├── folderPermissionState                                         │
│    └── draftCount (derived)                                          │
│                                                                       │
│  ▲ LibraryViewModel WRITE vào store, các View khác READ qua          │
│    @Environment(LibraryStore.self) — không phải mọi view giữ VM riêng│
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. 5 diễn biến chính — bước-theo-bước

### Diễn biến 1 — App mở LẦN ĐẦU (chưa cấp quyền)

```
1. Word_OfficeApp.init
   └── DependencyContainer wire tất cả service
   └── inject vào 4 store (Theme/Session/Library/App)

2. RootView xuất hiện
   └── check LibraryStore.folderPermissionState
   └── == .notGranted (Keychain rỗng)
   └── show FolderPermissionOnboarding

3. User bấm "Chọn thư mục" trong onboarding
   └── FolderPermissionViewModel.requestPermission()
       └── gọi FolderPermissionGranting.requestFolderAccess()
           └── present UIDocumentPickerViewController(forOpeningContentTypes: [.folder])

4. User chọn 1 thư mục → callback về app
   └── FolderPermissionPicker:
       ├── url.startAccessingSecurityScopedResource()
       ├── bookmarkData = url.bookmarkData(options: .minimalBookmark)
       ├── url.stopAccessingSecurityScopedResource()
       └── return FolderBookmark(bookmarkData, displayPath, grantedAt)

5. LibraryViewModel nhận bookmark
   ├── FolderBookmarkStore.save(bookmark)      → lưu Keychain
   ├── LibraryStore.folderPermissionState = .granted
   └── gọi loadLibrary() (diễn biến 3 bên dưới)

6. RootView re-render (LibraryStore đổi)
   └── giờ show LibraryView (thay onboarding)
```

### Diễn biến 2 — Cấp quyền BỊ REVOKE (user tắt trong Settings)

```
1. App mở, RootView check permission state
   └── FolderBookmarkStore.loadSaved() → có bookmark trong Keychain
   └── FolderBookmarkStore.resolve(bookmark) throws → BOOKMARK STALE hoặc REVOKED

2. LibraryViewModel bắt exception
   └── LibraryStore.folderPermissionState = .revoked
   └── show ReauthorizePermissionCTA (KHÔNG im lặng tủ trống — rủi ro §9 arch v2.2)

3. User bấm "Cấp lại quyền" trong CTA
   └── quay về diễn biến 1 bước 3
```

### Diễn biến 3 — Mở app LẦN SAU (đã cấp quyền, auto-scan)

```
1. Word_OfficeApp.init → LibraryStore.folderPermissionState = .granted
2. RootView show LibraryView
3. LibraryView.task → gọi LibraryViewModel.loadLibrary()
   │
   ├── (a) FolderBookmarkStore.loadSaved() → bookmark từ Keychain
   ├── (b) FolderBookmarkStore.resolve(bookmark) → URL thư mục (xử lý isStale)
   ├── (c) folderURL.startAccessingSecurityScopedResource()
   │
   ├── (d) DocumentLibraryScanner.scan(folder: folderURL) async
   │       ├── FileManager.contentsOfDirectory(at: folderURL)
   │       ├── filter theo UTI hỗ trợ (docx/xlsx/pptx/pdf/hwp)
   │       ├── với mỗi file iCloud: check placeholder — không chờ tải xong
   │       │     (chỉ mark "downloading", không block cả list)
   │       └── return [DocumentRef]
   │
   ├── (e) với mỗi DocumentRef:
   │       ├── documentID = URL.documentID(from: bookmark)   // bookmark + hash
   │       ├── metadata = MetadataStoring.fetch(id: documentID)
   │       │     ├── nếu có → dùng
   │       │     └── nếu chưa → tạo mới với status = .draft, upsert vào SQLite
   │       └── ghép thành (DocumentRef, DocumentMetadata)
   │
   ├── (f) LibraryStore.documents = [...]      → SwiftUI re-render LibraryView
   ├── (g) LibraryStore.draftCount = ...       → badge cập nhật
   │
   └── (h) RemindScheduling.dueReminders(now: Date())
           └── documents nào có remindAt <= now → sort lên đầu list
                (in-app, KHÔNG UNUserNotificationCenter)

4. folderURL.stopAccessingSecurityScopedResource() (defer)
```

### Diễn biến 4 — User đổi STATUS thủ công

```
1. User swipe trên DocumentCard → menu status hiện
   └── chọn "Đã xem lại"

2. DocumentCard callback → LibraryViewModel.setStatus(.reviewed, for: docRef)
   │
   ├── (a) metadata = MetadataStoring.fetch(id: docRef.documentID)
   ├── (b) metadata.status = .reviewed
   ├── (c) metadata.lastModifiedAt = Date()
   ├── (d) MetadataStoring.upsert(metadata)    → ghi vào SQLite
   │
   └── (e) LibraryStore.documents[index] = updated tuple
           → SwiftUI re-render đúng DocumentCard đó (thanks @Observable diff)
           → draftCount tự giảm nếu status cũ là .draft

3. File gốc .docx KHÔNG bị đụng tới. Chỉ metadata.sqlite thay đổi.
```

**⚠️ Quan trọng — không auto-suy luận**: KHÔNG có code path nào tự đổi status từ hành vi (mở file, edit file, close file...). Status CHỈ đổi qua diễn biến 4 (user thủ công). Đây là rủi ro cao nhất trong bảng §9 arch v2.2.

### Diễn biến 5 — Đặt REMINDER + hiển thị

```
1. User bấm RemindAtField trên DocumentCard → date picker sheet
   └── chọn "2026-09-01 09:00"

2. LibraryViewModel.setReminder(date, for: docRef)
   ├── metadata.remindAt = date
   ├── MetadataStoring.upsert(metadata)
   └── LibraryStore refresh

3. --- ngày 2026-09-01, user mở app ---

4. LibraryViewModel.loadLibrary() (diễn biến 3)
   └── bước (h): RemindScheduling.dueReminders(now: Date())
       └── SQL query: SELECT documentID FROM metadata WHERE remindAt <= ?
       └── return [docRef.id]

5. LibraryStore sort documents: due reminders lên đầu + highlight visual
   └── LibraryView tự render lại theo order mới

6. KHÔNG có notification khi app đóng. User chỉ thấy khi mở app.
   (quyết định sản phẩm chốt trong product-strategy-changelog.md)
```

---

## 5. Protocol interface mẫu — copy dùng luôn

### `FolderPermissionGranting.swift`

```swift
import Foundation

protocol FolderPermissionGranting: Sendable {
    /// Present UIDocumentPickerViewController(.folder), trả về bookmark khi user chọn xong.
    /// Return nil nếu user cancel.
    /// Throws nếu picker fail hoặc không tạo được bookmark data.
    func requestFolderAccess() async throws -> FolderBookmark?
}
```

### `FolderBookmarkResolving.swift`

```swift
import Foundation

protocol FolderBookmarkResolving: Sendable {
    /// Load bookmark đã lưu từ Keychain. Nil nếu chưa từng cấp quyền.
    func loadSaved() -> FolderBookmark?

    /// Resolve bookmark → URL truy cập được. Handle isStale (refresh bookmark).
    /// Throws .bookmarkStale hoặc .revoked nếu OS đã thu hồi quyền.
    func resolve(_ bookmark: FolderBookmark) throws -> URL

    /// Lưu bookmark vào Keychain (overwrite bookmark cũ nếu có).
    func save(_ bookmark: FolderBookmark) throws

    /// Xoá bookmark (khi user chủ động chọn "Reset thư mục").
    func delete() throws
}

enum FolderBookmarkError: Error, Sendable {
    case bookmarkStale       // isStale = true, cần refresh
    case revoked             // OS đã thu quyền, phải xin lại
    case keychainFailure(OSStatus)
}
```

### `DocumentLibraryScanning.swift`

```swift
import Foundation

protocol DocumentLibraryScanning: Sendable {
    /// Quét thư mục, trả về file đúng UTI hỗ trợ.
    /// Với file iCloud là placeholder: KHÔNG chờ tải xong,
    /// đánh dấu `isDownloading = true` trong DocumentRef, hiện ngay lên tủ.
    func scan(folder: URL) async -> [DocumentRef]
}
```

### `MetadataStoring.swift`

```swift
import Foundation

protocol MetadataStoring: Sendable {
    func fetch(id: String) async throws -> DocumentMetadata?
    func upsert(_ metadata: DocumentMetadata) async throws
    func delete(id: String) async throws

    /// Đếm status == .draft — dùng cho badge trên LibraryView.
    func draftCount() async throws -> Int

    /// Query documentID có remindAt <= now, sort theo remindAt tăng dần.
    func dueReminders(now: Date) async throws -> [String]

    /// Cho preview + test: xoá sạch DB.
    func reset() async throws
}
```

### `RemindScheduling.swift`

```swift
import Foundation

protocol RemindScheduling: Sendable {
    /// Wrap MetadataStoring.dueReminders cho tương lai mở rộng
    /// (vd: recurring reminder — Phase sau). Giờ MVP chỉ 1 method.
    func dueReminderIDs(at moment: Date) async throws -> [String]
}
```

---

## 6. Model — 3 file thuần data (A1)

### `DocumentMetadata.swift`

```swift
import Foundation

struct DocumentMetadata: Sendable, Codable, Identifiable, Hashable {
    let id: String                    // = documentID bền vững
    var status: DocumentStatus
    var lastOpenedAt: Date
    var lastModifiedAt: Date
    var remindAt: Date?               // nil = chưa đặt nhắc

    init(id: String,
         status: DocumentStatus = .draft,
         lastOpenedAt: Date = Date(),
         lastModifiedAt: Date = Date(),
         remindAt: Date? = nil) {
        self.id = id
        self.status = status
        self.lastOpenedAt = lastOpenedAt
        self.lastModifiedAt = lastModifiedAt
        self.remindAt = remindAt
    }
}
```

### `DocumentStatus.swift`

```swift
import Foundation

enum DocumentStatus: String, Sendable, Codable, CaseIterable, Identifiable {
    case draft       // Nháp
    case reviewed    // Đã xem lại
    case signed      // Đã ký
    case sent        // Đã gửi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft:    "Nháp"
        case .reviewed: "Đã xem lại"
        case .signed:   "Đã ký"
        case .sent:     "Đã gửi"
        }
    }
}
```

### `FolderBookmark.swift`

```swift
import Foundation

struct FolderBookmark: Sendable, Codable {
    let bookmarkData: Data       // URL.bookmarkData(options: .minimalBookmark)
    let displayPath: String      // "iCloud Drive / Documents / Work"
    let grantedAt: Date
}
```

---

## 7. 5 bẫy dễ mắc (xem lại trước khi code)

| # | Bẫy | Triệu chứng | Cách tránh |
|---|---|---|---|
| 1 | Dùng **file path** làm `documentID` | User đổi tên/di chuyển file → metadata "mất" (thực ra là mồ côi vì key khác) | Sinh `documentID` từ bookmark data + hash nội dung (`URL+DocumentID` extension). Path chỉ dùng để MỞ file, không làm key |
| 2 | Auto-suy luận status (mở file = `.reviewed`) | Tủ hồ sơ không còn tín hiệu "còn nợ việc" → core loop chết | Chỉ đổi status qua `setStatus()` — không có code path nào khác được update field này |
| 3 | Chờ tải xong mọi iCloud placeholder khi scan | Mở app chờ 30 giây mới thấy tủ (nếu 200 file iCloud) → Aha moment phá | Hiện ngay `isDownloading = true` cho file placeholder, tải nền, cập nhật khi xong. Xem `Phase0-Implementation-Logic-v2.md` §4.2 |
| 4 | Bookmark revoke → im lặng tủ trống | User nghĩ app hỏng, gỡ cài | BẮT BUỘC show `ReauthorizePermissionCTA` khi `resolve` fail. Test scenario: cấp quyền → Settings tắt → mở lại app → phải hiện CTA |
| 5 | Push notification cho reminder | Cảm giác spam, phản cảm với công cụ năng suất — quyết định sản phẩm | KHÔNG `UNUserNotificationCenter`. Reminder chỉ = filter list khi app đang mở |

---

## 8. Testing — mock nào cần

Sprint 0.2 nhóm A9 (xem `GUIDELINE.md`):

```
MockFolderPermissionGranting  → return preset FolderBookmark
MockFolderBookmarkResolving   → in-memory Dictionary, giả lập isStale/revoke
MockDocumentLibraryScanning   → return fixture [DocumentRef] cố định
MockMetadataStore             → in-memory [String: DocumentMetadata]
                                 (KHÔNG dùng real GRDB/SwiftData trong unit test)
```

Test flow điển hình:

```swift
@Test("Đổi status khỏi draft → draftCount giảm")
func statusChangeUpdatesDraftCount() async throws {
    let store = MockMetadataStore()
    try await store.upsert(DocumentMetadata(id: "doc-1", status: .draft))
    try await store.upsert(DocumentMetadata(id: "doc-2", status: .draft))
    #expect(try await store.draftCount() == 2)

    let vm = LibraryViewModel(metadataStore: store, /* ... */)
    try await vm.setStatus(.reviewed, for: DocumentRef(id: "doc-1", ...))

    #expect(try await store.draftCount() == 1)
}
```

---

## 9. Điểm nối với các mục MVP khác

| Nối với | Điểm nối |
|---|---|
| **Mục 1 (Core editing)** | Tap 1 `DocumentCard` → mở `DocumentEditorSplitView` → `EditorViewModel` chạy như cũ. Sau khi close editor, `lastOpenedAt` update qua `MetadataStoring.upsert()` |
| **Mục 2 (Autosave)** | Autosave ghi vào file gốc (qua bookmark). Khi save xong → gọi `MetadataStoring.upsert()` để cập nhật `lastModifiedAt` |
| **Mục 4 (Files provider) Sprint 0.3** | FilesProviderExtension đọc CÙNG `metadata.sqlite` trong App Group container → thumbnail/list trong Files app hiện đồng nhất với LibraryView của app |
| **Mục 5 (Add file thủ công §4.5)** | File thủ công add vào sandbox → sinh `documentID` riêng (không có bookmark từ folder cấp quyền) → vẫn insert vào `MetadataStoring` như file scan tự động, chung 1 LibraryView |
| **Mục 9 (E-signature)** | Sau khi user ký file → prompt "Đổi status thành Đã ký?" → tuỳ user (thủ công, không auto). Nếu user chọn có → `setStatus(.signed, for: docRef)` |
| **Phụ lục A Phase 1 (AI tóm tắt)** | Trên `DocumentCard` với status `.draft` + lâu chưa mở → hiện nổi bật nút "Tóm tắt" (điểm nối trực tiếp core loop) |

---

## 10. Reference nhanh

- Arch tổng: `PHASE_1_ARCHITECTURE.md` v2.2 §3 (layer), §5 (folder structure)
- Logic per feature: `Phase0-Implementation-Logic-v2.md` mục 4 (Add file folder-scan) + mục 10 (Tủ hồ sơ)
- Task list Sprint 0.2 nhóm A: `GUIDELINE.md` "Where we left off"
- Quyết định persistence backend (blocking): chọn GRDB/SwiftData/CoreData ở A0 trước khi viết `MetadataStoreImpl`

---

*File này giữ scope hẹp — chỉ mục 10 + storage. Nếu cần hiểu mục khác (editing/OCR/watermark/...) đọc `Phase0-Implementation-Logic-v2.md` mục tương ứng.*
