# Word Office — Guideline bám theo (Sprint 0.1 → 0.2 gate)

> **Mục tiêu file này:** danh sách công việc **theo thứ tự** để bạn tự làm được.
> **Cập nhật:** 2026-08-27 (session 3 — scope MVP chốt lại v2, thêm Tủ hồ sơ)

---

## ⭐ Where we left off — resume ở đây khi mở lại project

**Session 3 (2026-08-27) end state:**

- ✅ **Sprint 0.1 skeleton DONE** — 104 Swift files + 52 Asset Catalog colorsets, build clean, launches iPhone 17 Pro sim
- ✅ **Scope MVP chốt lại theo v2** — `Phase0-Implementation-Logic-v2.md` + `PHASE_1_ARCHITECTURE.md` v2.2 (rewrite 27/08). MVP = 12 mục thực tế (11 v2 + Autosave giữ theo user override). Bỏ Pencil/Compress/AI khỏi MVP, THÊM Tủ hồ sơ (mục 10) làm core loop, VIẾT LẠI Add file thành folder-picker + auto-scan (luồng chính)
- ✅ **Sprint 0.2 nhóm A phần backend DONE (7/9 phase)** — A0 (chốt GRDB) + A1 (3 model) + A2 (5 protocol) + A3 (5 impl) + A4 (URL+DocumentID) + A5 (LibraryStore + Word_OfficeApp inject) + A6 (2 VM) + A8 (DI Container) = **19 file mới + 2 file edit**
- ⏸️ **PAUSED để user add file vào Xcode + add GRDB SPM + build verify** trước khi tôi vào A7 (Views) — checklist add file ở section "PHẦN 3 — Sprint 0.2 nhóm A backend, checklist add Xcode" bên dưới
- ⏳ **Chưa làm**: A7 (6 View + wire RootView) + A9 (4 unit test)

### 4 file đã tạo Sprint 0.2 (session 2) — GIỮ NGUYÊN làm luồng phụ 4.5

Không xoá, không refactor. Giờ chỉ là entry phụ cho file nằm ngoài thư mục đã cấp quyền (nhận qua Mail/Zalo/AirDrop):

1. `Services/Protocols/FileIO/DocumentImporting.swift` — protocol + `ImportOutcome` + `ImportError`
2. `Services/Implementations/Native/iCloudPlaceholderImporter.swift` — actor `NSMetadataQuery` wrapper
3. `Services/Implementations/Native/DocumentImporter.swift` — orchestrator security-scoped + iCloud + UTI + copy sandbox + auto-suffix
4. `Views/Import/AddFileMenu.swift` — `.fileImporter` multi-file (giờ là entry phụ, không phải chính)

### Việc CHƯA làm — chia 2 nhóm theo ưu tiên

#### Nhóm A — Ưu tiên cao: **Core loop Tủ hồ sơ + Add file luồng chính (folder-scan)** — LÀM TRƯỚC

Đây là core loop MVP THẬT (mục 10 v2), làm trước nhóm B vì tạo Aha moment. Chi tiết code tra `Phase0-Implementation-Logic-v2.md` mục 4.1 + mục 10.

**A0 — Quyết định persistence backend (ngày 1, blocking)**
- [ ] Spike 1 ngày: Core Data vs GRDB vs SwiftData cho `MetadataStore` (query `remindAt <= now`, `status == .draft` count, share qua App Group cho FileProvider Sprint 0.3)
- [ ] Chốt trước khi viết `MetadataStoreImpl.swift`

**A1 — Models (Foundation only, Sendable)**
- [ ] `Models/DocumentMetadata.swift` — `documentID`, `status`, `lastOpenedAt`, `lastModifiedAt`, `remindAt?`
- [ ] `Models/DocumentStatus.swift` — enum `.draft | .reviewed | .signed | .sent`
- [ ] `Models/FolderBookmark.swift` — bookmark `Data` + resolved URL + `isStale`

**A2 — Protocols (`Services/Protocols/Library/`)**
- [ ] `FolderPermissionGranting.swift` — xin quyền thư mục
- [ ] `FolderBookmarkResolving.swift` — resolve + `isStale` + revoke
- [ ] `DocumentLibraryScanning.swift` — scan folder → `[DocumentRef]`
- [ ] `MetadataStoring.swift` — CRUD `DocumentMetadata`
- [ ] `RemindScheduling.swift` — in-app filter `remindAt <= now`

**A3 — Implementations (`Services/Implementations/Native/`)**
- [ ] `FolderPermissionPicker.swift` — `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` + callback → bookmark
- [ ] `FolderBookmarkStore.swift` — Keychain (SecItem) save/load, `URL(resolvingBookmarkData:)` + `isStale` handling
- [ ] `DocumentLibraryScanner.swift` — quét folder, filter UTI hỗ trợ, xử lý iCloud placeholder không block cả list
- [ ] `MetadataStoreImpl.swift` — theo backend chốt ở A0
- [ ] `RemindScheduler.swift` — filter `remindAt <= Date()` (KHÔNG `UNUserNotificationCenter`)

**A4 — Extensions**
- [ ] `Extensions/URL+DocumentID.swift` — sinh `documentID` bền vững từ bookmark data + hash (KHÔNG dùng file path — path đổi khi file di chuyển)

**A5 — App state (mở rộng 3-store → 4-store)**
- [ ] `App/LibraryStore.swift` — `@Observable @MainActor` — `documents: [(DocumentRef, DocumentMetadata)]`, `folderPermissionState`, `draftCount` (derived)
- [ ] Update `Word_OfficeApp` — inject `LibraryStore` qua `.environment(_:)`
- [ ] Update `App/AppState.swift` — thêm flag `folderPermissionGranted: Bool`

**A6 — ViewModels**
- [ ] `ViewModels/LibraryViewModel.swift` — coord scanner + metadata store + folder permission state
- [ ] `ViewModels/FolderPermissionViewModel.swift` — CTA cấp/cấp lại quyền

**A7 — Views (`Views/Library/` + `Views/Import/`)**
- [ ] `Views/Import/FolderPermissionOnboarding.swift` — first-run flow xin quyền thư mục
- [ ] `Views/Library/ReauthorizePermissionCTA.swift` — UI khi bookmark revoke/isStale (KHÔNG im lặng tủ trống)
- [ ] `Views/Library/LibraryView.swift` — trang chủ tủ hồ sơ + `draftCount` badge prominent
- [ ] `Views/Library/DocumentCard.swift` — 1 item: tên + status badge + `remindAt` + thumbnail
- [ ] `Views/Library/DocumentStatusPicker.swift` — menu/swipe đổi status THỦ CÔNG (KHÔNG auto-suy luận)
- [ ] `Views/Library/RemindAtField.swift` — date picker sheet
- [ ] `Views/Root/RootView.swift` — root switch: nếu `folderPermissionGranted == false` → `FolderPermissionOnboarding`; else `LibraryView`

**A8 — DI Container**
- [ ] Register: `folderPermissionPicker`, `folderBookmarkStore`, `libraryScanner`, `metadataStore`, `remindScheduler`

**A9 — Unit tests**
- [ ] `DocumentLibraryScannerTests` — scan temp dir với fixtures (mix .docx/.pdf/.txt/non-supported)
- [ ] `FolderBookmarkStoreTests` — save/load/isStale/revoke handling
- [ ] `MetadataStoreImplTests` — CRUD + query `remindAt <= now` + `draftCount`
- [ ] `LibraryViewModelTests` — mock services, test load/rescan/status change/reminder filter

#### Nhóm B — Ưu tiên trung bình: hoàn thiện Add file luồng phụ + Autosave production

Làm sau nhóm A. 4 file session 2 đã có, giờ wire vào app + hoàn thiện autosave/crash-recovery (giữ theo user override 27/08).

- [ ] **Wire `AddFileMenu` vào toolbar** — hiện `DocumentListView` chỉ có nút `+` "New Document"; thêm menu 2 option Create/Import (hoặc thay `+` thành Menu). Ở `LibraryView` sau khi có, entry Add file phụ này nằm ở menu overflow (không phải nút chính, vì luồng chính giờ là auto-scan)
- [ ] **Register services trong `DependencyContainer`** — `iCloudImporter: ICloudPlaceholderImporter` + `documentImporter: DocumentImporting` factories
- [ ] **Update `DocumentListViewModel` (hoặc `LibraryViewModel`)** — method `importFiles(from urls: [URL]) async` gọi `DocumentImporter`, batch không fail whole batch
- [ ] **Crash-recovery scan `.autosave.tmp`** — scan `Documents/` khi launch (`Word_OfficeApp.init` hoặc `RootView.task`), phát hiện `<original>.autosave.tmp` → banner "Khôi phục bản chưa lưu?". Cần: `CrashRecoveryScanning` protocol + `CrashRecoveryScanner` native impl + `CrashRecoveryBanner` view. Reference: `Phase0-Implementation-Logic.md` **bản gốc** §2 (v2 dời Phase 1 nhưng user giữ MVP)
- [ ] **Save-on-background lifecycle** — `Word_OfficeApp` add `@Environment(\.scenePhase)` → `background` gọi `SessionStore.flushIfNeeded`; `EditorPlaceholderView` add `.onDisappear { Task { await vm.flushIfNeeded() } }`
- [ ] **Build verify** — `xcodebuild -project "Word Office.xcodeproj" -scheme "Word Office" -destination "generic/platform=iOS Simulator" build` phải clean

**Sau khi nhóm A + B xong → Sprint 0.2 non-SDK DONE.** Tiếp Sprint 0.3 (PDF Merge/Split + FileProvider + AirPrint + OCR — **BỎ Compress** vì dời Phase 1) hoặc chờ Artifex license để làm Real SDK swap.

### Cách nhanh nhất để resume

Sau khi bạn add file + GRDB + build clean:
- Gõ *"build clean, tiếp A7"* → tôi làm 6 View + wire RootView
- Nếu build fail: paste error → tôi fix
- Nếu muốn skip Views tạm, sang A9 unit tests: *"tiếp A9 unit tests"*

### Checklist add Xcode (dán từ session 3)

**21 file mới cần add vào target Word Office:**

`Models/`: DocumentMetadata, DocumentStatus, FolderBookmark, LibraryEntry
`Services/Protocols/Library/` (folder mới): DocumentLibraryScanning, FolderBookmarkResolving, FolderPermissionGranting, MetadataStoring, RemindScheduling
`Services/Implementations/Native/`: DocumentLibraryScanner, FolderBookmarkStore, FolderPermissionPicker, MetadataStoreImpl, RemindScheduler
`Extensions/`: URL+DocumentID
`App/`: LibraryStore
`ViewModels/`: LibraryViewModel, FolderPermissionViewModel

**Add GRDB:** File → Add Package Dependencies → `https://github.com/groue/GRDB.swift` → Product: **GRDB** → Add to target Word Office

**Đã edit (không add):** Word_OfficeApp.swift, DependencyContainer.swift, Services/Protocols/Library/MetadataStoring.swift

---

---

## Bản đồ tài liệu — mở file nào khi nào

| Khi bạn cần | Đọc file |
|---|---|
| Bước tiếp theo phải làm gì (file này) | `GUIDELINE.md` |
| Kiến trúc tổng thể + tại sao quyết định thế | `Word Office/PHASE_1_ARCHITECTURE.md` (v2.2, 2026-08-27) |
| **Kiến trúc Tủ hồ sơ + storage (đọc trước khi code Sprint 0.2 nhóm A)** | `Word Office/Library-Architecture.md` ← **focused, có ASCII diagram + code mẫu** |
| Chi tiết logic per feature theo scope mới (mục 1–10 + Phụ lục A/B) | `Word Office/Phase0-Implementation-Logic-v2.md` ← **file chính** |
| Logic Autosave/Pencil/Compress (bản gốc, tham khảo) | `Word Office/Phase0-Implementation-Logic.md` bản gốc — giữ nguyên, dùng lại khi Phase 1 hoặc khi làm Autosave nhóm B |
| Định vị sản phẩm + roadmap + đối thủ | `Word Office/product-strategy-master.md` |
| Lịch sử đổi ý roadmap | `Word Office/product-strategy-changelog.md` |
| Design system (color/font/spacing tokens) | `Word Office/Native-Professional-Workspace-Design-System.md` |
| Cách add file vào Xcode + setup build config | `Word Office/Word Office/README-XCODE-INTEGRATION.md` |

---

## PHẦN 1 — NGÀY 1: Xcode integration (3–4 giờ)

**Kết quả cuối ngày:** App build clean trên iPhone/iPad/Mac Catalyst, chạy được scheme Mock, hiển thị màn hình danh sách document (rỗng).

### 1.1 — Mở Xcode + add files vào project (30 phút)

Làm theo `Word Office/Word Office/README-XCODE-INTEGRATION.md` **Step 1**:

- [ ] Mở `Word Office.xcodeproj` bằng Xcode 16+
- [ ] Right-click group `Word Office` → **Add Files to "Word Office"…**
- [ ] Chọn 7 folder (⌘-click multi-select): `App/`, `DesignSystem/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Extensions/`
- [ ] Options: **"Create groups"** (KHÔNG "folder references") + **"Add to target: Word Office"** ✓
- [ ] Kiểm tra Project Navigator: 7 folder mới hiện dưới `Word Office` group
- [ ] Nếu Xcode báo `Word_OfficeApp.swift` / `ContentView.swift` đỏ (missing): right-click → **Delete → Remove Reference**

### 1.2 — Enable Swift 6 strict concurrency (10 phút, C4)

- [ ] Target `Word Office` → **Build Settings** → search `strict concurrency`
- [ ] Đặt **Strict Concurrency Checking = Complete**
- [ ] `⌘B` build → **sẽ có warning** — đây là bình thường ngày đầu
- [ ] Fix từng warning theo hướng dẫn `PHASE_1_ARCHITECTURE.md` §4.1 (`@unchecked Sendable` wrapper cho SDK types Sprint 0.2 sau)

### 1.3 — Tạo 2 build config + 2 scheme (Mock/Real) (20 phút, C3)

Làm theo `README-XCODE-INTEGRATION.md` **Step 3**:

- [ ] Project → **Info** → **Configurations** → duplicate `Debug` thành `Debug-Mock` và `Debug-Real`
- [ ] Target → **Build Settings** → search `active compilation conditions`
- [ ] Config `Debug-Mock`: thêm flag `USE_MOCK_SDK`
- [ ] Config `Debug-Real`: để trống
- [ ] Product → Scheme → Manage Schemes → duplicate scheme thành:
  - `Word Office (Mock)` → dùng `Debug-Mock`
  - `Word Office (Real)` → dùng `Debug-Real`
- [ ] Chọn scheme **Mock** → build (`⌘B`) → phải clean

### 1.4 — Mac Catalyst PoC (30 phút, C1)

- [ ] Target → **General** → **Supported Destinations** → verify **Mac (Mac Catalyst)** có
- [ ] Chọn destination **My Mac (Mac Catalyst)** → Run (`⌘R`)
- [ ] Verify 3 điều:
  - `NavigationSplitView` 3 cột hiện đúng (sidebar + list + detail)
  - Bấm ẩn sidebar → đóng app → mở lại → sidebar vẫn ẩn (N3 `@SceneStorage` work)
  - Hover mouse lên item → có highlight state
- [ ] Nếu 1 trong 3 vỡ → note lại, sẽ wrap `#if targetEnvironment(macCatalyst)` fallback trong tuần

### 1.5 — Run trên iPhone + iPad simulator (30 phút)

- [ ] Chọn iPhone 15 sim → Run → verify TabView 2 tab (Files + Tools) hiện đáy
- [ ] Chọn iPad Pro sim → Run → verify NavigationSplitView 3 cột
- [ ] Bấm nút **+** ở toolbar → sheet "New Document" mở
- [ ] Nhập tên `Test` → chọn `TXT` → Create → file xuất hiện trong list
- [ ] Tap `Test.txt` → editor mở với ô nhập text
- [ ] Gõ vài dòng → chờ 2 giây → về list → mở lại → text còn nguyên (autosave work)

**Nếu hết ngày 1 làm xong 1.1–1.5 → skeleton kiến trúc verified.** Ăn mừng nhẹ. Đóng máy.

---

## PHẦN 2 — TUẦN 1: Polish + Unit tests (5–7 ngày làm việc)

### 2.1 — Xử lý Swift 6 warnings còn lại

- [ ] `⌘B` build cả 2 scheme Mock + Real (Real dùng Mock fallback vì license chưa về)
- [ ] Fix warning từng file — chỉ dùng `@unchecked Sendable` khi thật sự cần, luôn có comment giải thích
- [ ] Target: **0 warning** cuối tuần

### 2.2 — Unit tests (tôi có thể generate nếu bạn muốn)

Sprint 0.1 checklist yêu cầu unit test cho:

- [ ] `DocumentListViewModelTests` — mock `DocumentListing`/`DocumentCreating`, test load/create/delete/rename/sort
- [ ] `EditorViewModelTests` — mock reader/writer/autosave, test load/markDirty/flush
- [ ] `SettingsViewModelTests` — trivial, chỉ verify version/build parse đúng
- [ ] `AutosaveSchedulerTests` — test debounce timing (2s), hard interval (30s), cancel, flush
- [ ] `LocalFileServiceImplTests` — test với temp directory, list/create/delete/rename + auto-suffix `(2)`, `(3)`
- [ ] Coverage target: **>70%** cho ViewModels

Cách chạy: `⌘U` trong Xcode. Nếu muốn tôi generate skeleton test files → nói "generate unit tests" tôi làm luôn.

### 2.3 — Design system audit — verify tokens work đúng

- [ ] Toggle Dark Mode trong simulator (⌘Shift+A) → app phải đổi màu tự động, không hardcode
- [ ] Tăng Dynamic Type max size (Settings → Accessibility → Display & Text Size → Larger Text) → text không bị cắt
- [ ] Verify 52 colorsets đúng theo design doc: mở `Assets.xcassets` → click 1 vài colorset → check Light/Dark hex khớp `Native-Professional-Workspace-Design-System.md` §6

### 2.4 — Placeholder cleanup

Trong 60 file placeholder Sprint 0.2–0.5, kiểm tra:

- [ ] Mỗi file có header `// Sprint 0.X — <purpose>` đúng
- [ ] Không có file nào bị compile error (chỉ có TODO comment, không có body)

### 2.5 — Accessibility labels cho icon buttons

Design doc §9 yêu cầu mọi icon-only button có accessibility label:

- [ ] Verify `DocumentListView` toolbar: nút + và sort đã có `.accessibilityLabel(...)` ✓ (đã add)
- [ ] Sprint sau các View phức tạp hơn phải audit tương tự

### 2.6 — Manual test matrix

Test trước khi khép Sprint 0.1:

| Device | Test |
|---|---|
| iPhone 15 sim | Tabs, create TXT, edit, autosave, settings theme toggle |
| iPhone SE sim (nhỏ) | Layout không bị cắt, empty state fit màn hình |
| iPad Pro sim | Split view, sidebar toggle persist, editor detail |
| iPad mini sim | Split view vẫn work, không tụt xuống compact ngoài ý |
| Mac Catalyst | 3-column, hover, keyboard shortcut Cmd+N (nếu implement) |

---

## PHẦN 3 — KHI ARTIFEX LICENSE VỀ (Sprint 0.2 gate)

**Chưa làm nếu license chưa có.** Note tuần license nhận được → follow steps.

### 3.1 — Add SDK vào project

- [ ] Nhận file `.xcframework` từ Artifex
- [ ] Xcode → target → **General** → **Frameworks, Libraries, and Embedded Content** → drag `.xcframework` vào
- [ ] Set **Embed & Sign**
- [ ] Nhận license key → lưu vào `.env` local hoặc Xcode build setting (KHÔNG commit)

### 3.2 — Implement Real Artifex services

Tạo 3 file trong `Services/Implementations/SDK/Real/`:

- [ ] `ArtifexDocumentSessionManager.swift` — bọc `SODKDoc`/`SODKDocSession` theo Phase0-Implementation-Logic.md §1
- [ ] `ArtifexDocumentReader.swift` — implement `read()` cho DOCX/XLSX/PPTX/PDF qua SDK API
- [ ] `ArtifexDocumentWriter.swift` — implement `write()` tương tự

### 3.3 — Update DependencyContainer

- [ ] Sửa `App/DependencyContainer.swift` — trong `#else` branch, return `ArtifexDocumentSessionManager()` thật (giờ `#else` đang fallback Mock)

### 3.4 — PoC test critical (Sprint 0.4 dependency)

**Test ngay khi có real SDK, không đợi Sprint 0.4:**

- [ ] Verify SDK view controller **chịu embed** trong `UIViewControllerRepresentable` (không chỉ full-screen present)
- [ ] Nếu KHÔNG chịu → escalate Artifex support ngay, hoặc chuẩn bị fallback strategy cho multi-pane Sprint 0.4

### 3.5 — Round-trip fidelity test (Sprint 0.2 GATE)

**Gate cứng — không pass thì không tiếp Sprint 0.2:**

- [ ] Chuẩn bị 5–10 file thật của user hoặc test set (DOCX/XLSX/PPTX/PDF)
- [ ] Với mỗi file: open bằng app → edit nhẹ (1 chỗ) → save → mở bằng **MS Word/Excel/PowerPoint thật** (hoặc Google Docs)
- [ ] Verify fidelity ≥70%: format cơ bản còn nguyên, chữ không mất, table không vỡ
- [ ] Nếu <70% → decision point: escalate Artifex hoặc adjust MVP scope (drop XLSX/PPTX edit tạm)

---

## PHẦN 4 — CHEATSHEET

### Đường dẫn quan trọng

| Path | Nội dung |
|---|---|
| `/Users/admin/Desktop/Word Office/Word Office/Word Office.xcodeproj` | Xcode project mở bằng đây |
| `/Users/admin/Desktop/Word Office/Word Office/Word Office/` | Source code root (app target) |
| `/Users/admin/Desktop/Word Office/Word Office/Word Office/Assets.xcassets/` | 52 colorset |
| `/Users/admin/Desktop/Word Office/Word Office/` | 4 doc markdown (arch/logic/strategy/design + guideline này) |

### Convention cần nhớ (arch v2.2)

- **KHÔNG import SDK ngoài `Services/Implementations/SDK/`** — SwiftLint rule sẽ chặn khi bạn setup
- **KHÔNG import SwiftUI trong `ViewModels/`** — VM chỉ Foundation
- **KHÔNG gộp vào 1 `AppState` god object** — dùng đúng `ThemeStore`/`SessionStore`/**`LibraryStore`**/`AppState` tách **4 store** (C5, arch v2.2 thêm `LibraryStore` cho Tủ hồ sơ)
- **KHÔNG hardcode màu HEX trong View** — dùng `Color.dsXxx` từ `DSColor.swift`
- **KHÔNG hardcode spacing như `padding(16)`** — dùng `DSSpacing.md`
- **KHÔNG dùng `@Previewable` (iOS 18+)** — deployment target là iOS 17, dùng wrapper view pattern
- **KHÔNG toggle Mock↔Real ở runtime** — compile flag `#if USE_MOCK_SDK` (C3)
- **KHÔNG dùng file path làm `documentID`** — path đổi khi file di chuyển trong thư mục cấp quyền; dùng bookmark data + hash (`URL+DocumentID` extension)
- **KHÔNG auto-suy luận `DocumentStatus`** — mở file ≠ `.reviewed`; đổi status CHỈ khi user thao tác thủ công (menu/swipe)
- **KHÔNG dùng `UNUserNotificationCenter`/push cho reminder** — chỉ in-app filter khi mở app (quyết định sản phẩm 27/08)
- **KHÔNG lưu folder bookmark vào UserDefaults** — dùng Keychain (SecItem), tránh backup ra khỏi device

### Cần tôi làm gì thêm — nói câu ngắn tương ứng

| Câu bạn nói | Tôi làm |
|---|---|
| "generate unit tests" | Tạo skeleton test files cho VM + AutosaveScheduler + LocalFileServiceImpl + `LibraryViewModelTests` + `MetadataStoreImplTests` |
| "bắt đầu nhóm A Tủ hồ sơ" | Spike persistence backend (Core Data vs GRDB vs SwiftData) → chốt → tạo A1 Models |
| "chốt persistence backend luôn = GRDB" (hoặc SwiftData/Core Data) | Skip spike, chuyển thẳng sang A1 Models với backend đã chốt |
| "làm folder-picker + bookmark trước" | Tạo A3 `FolderPermissionPicker` + `FolderBookmarkStore` + `FolderPermissionOnboarding` view |
| "làm sidebar Locations thật" | Wire iCloud/Files Provider vào sidebar (Sprint 0.3 preview) |
| "add SwiftLint rule chặn SDK import" | Tạo `.swiftlint.yml` với custom rule |
| "làm String Catalog EN" | Tạo `Localizable.xcstrings` + convert LocalizedStringKey trong Views |
| "add real DOCX reader mock (thay vì placeholder)" | Nâng Mock lên preview DOCX cơ bản qua ZIPFoundation + XMLCoder |
| "hoàn thiện nhóm B Add file phụ + Autosave" | Wire `AddFileMenu` + register DI + `importFiles` VM + crash-recovery + scenePhase save |

### Common pitfall + fix nhanh

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| Build error "Cannot infer contextual base in reference to member 'dsXxx'" trong `.foregroundStyle(.dsXxx)` / `.background(.dsXxx)` / `.tint(.dsXxx)` | SwiftUI `foregroundStyle`/`background`/`tint` nhận `some ShapeStyle`, không phải `Color` trực tiếp → compiler không auto-infer shorthand `.dsXxx` được | Dùng explicit `Color.dsXxx`: `.foregroundStyle(Color.dsTextPrimary)`. Shorthand `.dsXxx` chỉ work khi context là `Color` trực tiếp (ví dụ `var color: Color = .dsXxx`) |
| Build error "not available due to missing import of defining module 'UIKit'" trên `NSAttributedString` RTF methods, `UIImage`, `PKCanvasView`... | Xcode 26 / Swift 6 bật **MemberImportVisibility** — không auto-inherit UIKit từ Foundation nữa; phải `import UIKit` explicit | Thêm `import UIKit` vào đầu file dùng UIKit-only API. Không được lười `import Foundation` là đủ như trước |
| Build error "value of optional type 'UTType?' must be unwrapped" khi so sánh `type == .init(filenameExtension: "md")` | `UTType(filenameExtension:)` return `UTType?`, không unwrap thì so sánh với `UTType` fail | `if let ext = UTType(filenameExtension: "md"), type == ext { ... }` |
| Build error "Unable to find a destination... visionOS 26.2 is not installed" khi build Mac Catalyst | Xcode 26 default add visionOS vào scheme dù chưa cài SDK | Xcode → target → General → Supported Destinations → remove "Apple Vision". Hoặc Xcode → Settings → Components → tải visionOS SDK |
| Build error "Cannot find 'AppState' in scope" | File chưa add vào target | Right-click file trong Xcode → **Target Membership** → check Word Office |
| Colorset không hiện màu | Contents.json corrupt | Xóa colorset trong Xcode → tạo lại bằng tay hoặc chạy lại Python script |
| Xcode báo "duplicate @main" | File cũ `Word_OfficeApp.swift` ở root chưa xóa reference | Right-click file đỏ → Delete → Remove Reference |
| Preview crash "environment(AppState.self) missing" | Preview không có `.environment(...)` | Add `.environment(AppState())` vào `#Preview` block |
| Warning "conformance to Sendable" | Struct/class chưa mark Sendable | Add `Sendable` hoặc `@unchecked Sendable` với comment lý do |
| Autosave không chạy | `markDirty()` không được gọi | Verify TextEditor onChange có gọi `vm.markDirty()` |
| Xcode báo "Simulator device failed to launch com.app.word.office..." + "No such process" (NSPOSIXErrorDomain Code 3) | Sim ở half-boot state, không phải bug code. App vẫn install & chạy được nếu launch thủ công | Fix theo thứ tự: (1) mở app Simulator, đợi boot xong, ⌘R lại; (2) Simulator → Device → Erase All Content; (3) Product → Clean Build Folder (⌘⇧K); (4) đổi sim khác (iPhone 16/SE); (5) khởi động lại Xcode |

---

## PHẦN 5 — CHECKPOINT

Đánh dấu khi hoàn thành:

- [x] **Ngày 1 xong** — App build clean, run được trên iPhone/iPad/Mac Catalyst với scheme Mock
- [x] **Sprint 0.1 DONE** (session 2, 2026-08-26) — 104 Swift files + 52 colorsets, verified launches
- [x] **Scope MVP chốt v2** (session 3, 2026-08-27) — 12 mục, thêm Tủ hồ sơ, bỏ Pencil/Compress/AI. Arch v2.2 + GUIDELINE rewrite xong
- [ ] **Sprint 0.2 nhóm A DONE** — Tủ hồ sơ + folder-scan chạy end-to-end (onboarding → cấp quyền → scan → LibraryView đầy → đổi status persist)
- [ ] **Sprint 0.2 nhóm B DONE** — Add file phụ wire xong, crash-recovery + save-on-background chạy đúng
- [ ] **Artifex license về** — swap Mock → Real, PoC embed view pass, round-trip fidelity ≥70% với file thật
- [ ] **Sprint 0.2 gate pass** — tiếp tục Sprint 0.3 (PDF Merge/Split + Files Provider + OCR — **KHÔNG** Compress)

---

*Nếu bí ở bước nào, gõ mô tả vào chat tôi giải thích/làm tiếp. Không cần đọc lại toàn bộ arch doc — tôi đã có context.*
