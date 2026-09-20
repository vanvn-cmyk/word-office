# Word Office — Phase 0 (MVP) Architecture v2.2

> **Status:** Draft v2.2 · 2026-08-27 (rewrite theo scope MVP v2 chốt 27/08 — thay thế v2.1 "10 mục AI dời Phase 2")
> **Scope:** MVP **12 mục thực tế** (11 mục v2 + user override giữ Autosave) — logic chi tiết: `Phase0-Implementation-Logic-v2.md`
> **Engine strategy:** SDK thương mại (Artifex Smart Office SDK — mặc định) + Apple native + OSS Swift fill-in
> **Architecture:** MVVM + SOLID + SwiftUI-native (`@Observable` iOS 17+)
> **Timeline:** ~13 tuần / 5 sprints / ≈3.5 tháng (reshuffle nội dung, cùng số sprints với v2.1)

---

## 0. Tại sao viết lại (v2.2 vs v2.1)

V2.1 chốt 10 mục MVP (AI dời Phase 2). V2.2 cập nhật theo `Phase0-Implementation-Logic-v2.md` (27/08) + user override:

**Ra khỏi MVP (dời Phase 1):**
- Apple Pencil (từ Sprint 0.4)
- Compress (PDF/DOCX/PPTX — từ Sprint 0.3, giữ Merge/Split)
- AI tóm tắt (Phụ lục A trong doc v2)

**Ra khỏi MVP (dời Phase 2):**
- AI tạo văn bản từ mô tả (Phụ lục B)

**Vào MVP mới:**
- **Mục 10 — Core loop "Tủ hồ sơ"** (habit loop Zeigarnik). Đây là core loop MVP THẬT, không phải AI.
- **Mục 5 — Add file VIẾT LẠI**: luồng chính là cấp quyền 1 lần cho 1 thư mục → auto-scan/import. Luồng `.fileImporter` cũ demote thành phụ.

**Giữ theo user override (2026-08-27):**
- Autosave + crash-recovery (v2 gốc đẩy Phase 1, user quyết giữ MVP)

**Không đổi:** MVVM + SOLID, Artifex SDK strategy, Mock SDK skeleton, 5 sprints, iOS 17+, `@Observable`.

---

## 1. Mục tiêu Phase 0 (MVP)

Sau ~13 tuần, app phải làm được **12 mục** (bảng dưới đánh số theo doc v2 + Autosave giữ):

1. Core editing DOC/DOCX, XLS/XLSX, PPT/PPTX + xem & convert PDF
2. **Autosave + crash-recovery** ← v2 gốc đẩy Phase 1, user giữ MVP (2026-08-27)
3. Kiến trúc layout adaptive (iPhone / iPad / iPad-split / Mac Catalyst / iPhone Fold-ready)
4. Files app provider + AirPrint
5. **Add file — cấp quyền 1 lần cho thư mục + auto-scan** (luồng chính) + Add file thủ công (luồng phụ 4.5)
6. iPad multi-pane UI + keyboard shortcuts (**KHÔNG** Apple Pencil — dời Phase 1)
7. OCR — scan giấy thành văn bản
8. **Merge / Split — Word, PDF, PowerPoint** (**KHÔNG** Compress — dời Phase 1)
9. Note / comment dạng text
10. **Core loop "Tủ hồ sơ"** ← MỚI, chưa có ở v2.1 — habit loop Zeigarnik, metadata riêng + status + remindAt in-app
11. E-signature (vẽ tay MVP, PKI cho Phase 2 nếu SDK hỗ trợ sẵn) + Watermark

**Ra khỏi MVP:**
- ~~Apple Pencil~~ → Phase 1
- ~~Compress (PDF/DOCX/PPTX)~~ → Phase 1
- ~~AI tóm tắt~~ → Phase 1 (Phụ lục A trong doc v2)
- ~~AI tạo văn bản từ mô tả~~ → Phase 2 (Phụ lục B trong doc v2)

---

## 2. Assumptions — trạng thái sau confirm 2026-08-27

| # | Assumption | Trạng thái |
|---|---|---|
| A1 | **SDK = Artifex Smart Office SDK** — cover full Office edit + PKI + Review ribbon | ✅ Confirmed |
| A2 | **License đang làm việc với Artifex sales.** Sprint 0.1 dựng **Mock SDK layer** theo pattern Artifex API. Khi license về, swap `MockArtifexDocumentSessionManager` → `ArtifexDocumentSessionManager` thật, VM/View không đổi 1 dòng (LSP + DIP) | ✅ Confirmed workaround |
| A3 | **Deployment target iOS 17.0+** | ✅ Confirmed |
| A4 | **Support iPhone + iPad + Mac Catalyst** (không native macOS scene riêng ở MVP; Mac app thật để Phase 3) | ✅ Default |
| A5 | ~~**Backend AI proxy = Cloudflare Workers**~~ **AI hoàn toàn ngoài MVP.** Không backend cho Phase 0. Khi Phase 1 làm AI tóm tắt: dùng lại research cũ (Cloudflare Workers + Hono + App Attest) | ⏸️ Phase 1+ |
| A6 | **Bundle ID + Apple Developer team ID: user gửi sau.** Tạm dùng `com.word-office.app`. **⚠️ Cần cấp trước Sprint 0.3** (Files Provider entitlement + App Group ID phải match) | ⏳ Chờ user |
| A7 | **Localization MVP = English only.** String Catalog EN, Vietnamese Phase 2 | ✅ Confirmed |
| A8 | Language: Swift 6+, Xcode 16+ | ✅ Máy sẵn sàng |
| A9 | Design system: **chờ user gửi** — dùng system default (SF Symbols, system colors) đến khi có | ⏳ |
| A10 | Không cloud sync (iCloud/GDrive/Dropbox) ngoài import ở MVP — Dropbox/Drive full sync = Phase 2 | ✅ |
| **A11** | **Core loop MVP = "Tủ hồ sơ" (Zeigarnik habit loop), KHÔNG phải AI.** Metadata store riêng (Core Data hoặc SQLite qua GRDB — quyết định Sprint 0.2), status thủ công (không auto-suy luận), nhắc trong app (không push) | ✅ Confirmed 27/08 |
| **A12** | **Add file luồng chính = folder-picker + bookmark + auto-scan** (không phải `.fileImporter` chọn từng file). Luồng thủ công demote thành phụ | ✅ Confirmed 27/08 |

---

## 3. Kiến trúc — MVVM + SOLID + 4 layer

### 3.1 Nguyên tắc

- **M (Model)** — Pure data (`struct` / `enum`). Không logic, không side-effect. `Codable`, `Equatable`, `Hashable`, `Identifiable`. **Sendable** (Swift 6 strict concurrency — xem §4.1).
- **VM (ViewModel)** — `@Observable @MainActor` class. Sở hữu state, gọi services, expose data. **Không import SwiftUI, không import SDK.**
- **V (View)** — SwiftUI `View`. Chỉ presentation. Nhận VM qua `@State` (owned) hoặc `@Bindable` (injected).
- **S (Service)** — Protocol-based (ISP nhỏ), `Sendable`, inject concrete impl qua init. Handles I/O, SDK calls, native framework, network.
- **E (Engine)** — Concrete implementation của service. **CHỈ layer này biết SDK/native framework tồn tại.** Nếu SDK types không `Sendable` → wrapper dùng `@unchecked Sendable` + chú thích rõ lý do + isolate qua actor.

### 3.1.1 Shared state — tách theo domain, KHÔNG god object (C5)

**KHÔNG** gộp mọi shared state vào 1 `AppState` — nếu chứa cả session doc đang mở, mọi View nghe `AppState` sẽ re-invalidate khi mở/đóng doc → hitch UI.

Tách thành **4 store** nhỏ (thêm `LibraryStore` cho Tủ hồ sơ), inject riêng qua `.environment(_:)`:

| Store | Chứa gì | Ai nghe |
|---|---|---|
| `ThemeStore` (`@Observable`) | theme, font default, accent color | Views có styling reactive |
| `SessionStore` (`@Observable`) | current document session ref, dirty flag, autosave status | Editor, toolbar, sidebar item highlight |
| **`LibraryStore` (`@Observable`)** ← MỚI | Danh sách `DocumentMetadata` (mục 10 Tủ hồ sơ), folder bookmark permission state, draftCount | `LibraryView`, badge count trên root |
| `AppState` (`@Observable`) | metadata only: launch count, last version, first-run flag, folder permission granted flag | Onboarding, app-level flags |

Mỗi View chỉ observe store nó thật sự cần → invalidation không lan sang view khác.

### 3.2 SOLID mapping — critical cho SDK integration

| Principle | Áp dụng cho MVP 12 mục |
|---|---|
| **S**RP | 1 service = 1 domain. `DocumentSessionManaging` chỉ mở/đóng session SDK; `AutosaveScheduling` chỉ debounce; `TextRecognizing` chỉ OCR; **`DocumentLibraryScanning` chỉ quét thư mục**; **`MetadataStoring` chỉ CRUD metadata**. Không service god. |
| **O**CP | Add format mới (HWP) = tạo `HWPDocumentReading: DocumentReading` conform, KHÔNG sửa VM cũ. Đổi SDK (Artifex → PSPDFKit) = swap impl `DocumentSessionManaging`, VM không đổi 1 dòng. Đổi metadata backend (Core Data → GRDB) = swap `MetadataStoring` impl. |
| **L**SP | Mọi impl `DocumentReading`/`Writing`/`MetadataStoring`/... swappable. Test dùng `MockMetadataStore` (in-memory). |
| **I**SP | Protocol nhỏ, tách riêng: `DocumentReading`, `DocumentWriting`, `DocumentListing`, `DocumentExporting`, `DocumentSessionManaging`, `FolderPermissionGranting`, `DocumentLibraryScanning`, `MetadataStoring`, `RemindScheduling` — KHÔNG gộp 1 `DocumentService` god protocol. |
| **D**IP | UI/VM phụ thuộc **protocol**, không phụ thuộc SDK/Core Data/GRDB. DI container ở `App/` inject impl. **⚠️ Vi phạm nghiêm trọng nhất nếu để nhỡ tay: import Artifex header vào View/VM — cần code review lint chặn.** |

### 3.3 Rules từ `swiftui-expert-skill` (giữ nguyên v2.1)

- ✅ `@State private var` luôn `private`
- ✅ `@Observable` class luôn có `@MainActor`
- ✅ `@ObservationIgnored @AppStorage` trong `@Observable` class
- ✅ Types `Equatable` cho property hay write (tránh re-invalidation)
- ✅ `@Bindable` cho `@Observable` inject từ parent
- ✅ `@Environment(AppState.self)` cho shared state
- ✅ KeyPath binding (`$model[key]`) thay `Binding(get:set:)`
- ✅ `NavigationSplitView` thay `NavigationView`
- ✅ `foregroundStyle` thay `foregroundColor`
- ✅ `Button` cho mọi tappable (không `onTapGesture`)
- ✅ `onChange(of:) { }` không param, hoặc `{ old, new in }`
- ✅ Preview self-contained mock data — không phụ thuộc SDK/filesystem

---

## 4. Tech Stack

### 4.1 iOS app

| Layer | Công nghệ | Vai trò |
|---|---|---|
| **Language** | Swift 6+ | Concurrency + macros |
| **Concurrency mode** | **Swift 6 strict concurrency ENABLED** (build setting `SWIFT_STRICT_CONCURRENCY = complete`) từ Sprint 0.1 (C4) | Bắt lỗi data race ở compile time; enable muộn phải refactor hàng loạt |
| **UI** | SwiftUI (iOS 17+) | Adaptive, `@Observable` |
| **State** | `@Observable` + `@State` + `@Bindable` | Không `ObservableObject`. Shared state tách 4 store theo domain (§3.1.1), không god object |
| **Navigation** | `NavigationSplitView` + `NavigationStack` | Adaptive theo `horizontalSizeClass`. `@SceneStorage` cho `columnVisibility` persist qua launches (N3) |
| **Async** | Swift Concurrency (`async/await`, `Task`, actors) | Không Combine cho code mới |
| **Metadata persistence (Tủ hồ sơ)** | **SQLite qua GRDB.swift HOẶC SwiftData** — quyết định Sprint 0.2 ngày đầu | Cả 2 đều share qua App Group. GRDB đơn giản hơn cho query filter (`remindAt <= Date()`), SwiftData integrate tốt hơn với SwiftUI observation. |
| **Folder bookmark storage** | `Data` (bookmark) lưu vào Keychain (SecItem) — KHÔNG UserDefaults (dễ backup ra khỏi device) | Resolve mỗi lần app mở, xử lý `isStale`/revoke với UI CTA "Cấp lại quyền" |
| **Folder scan** | `FileManager.contentsOfDirectory` + `NSMetadataQuery` cho iCloud placeholder detect | Chi tiết `Phase0-Implementation-Logic-v2.md` §4.1–4.2 |
| **Text editor bridge** | `UIViewRepresentable(UITextView)` | iOS 17–25; iOS 26+ dùng `TextEditor(AttributedString)`. Sprint 0.2 phải xử lý: selection binding SwiftUI↔UIKit, UndoManager integration, `AttributedString`↔`NSAttributedString` diff-friendly (C2) |
| **RTF I/O** | `NSAttributedString` native | Baseline test Sprint 0.1 |
| **Mac Catalyst** | Test PoC riêng Sprint 0.1 — `NavigationSplitView` `columnVisibility` sync/toolbar/sidebar hover khác iPad (C1). Fallback: `#if targetEnvironment(macCatalyst)` khi cần | Không giả định "chạy như iPad" |
| **Concurrency lint** | SwiftLint + custom rule chặn import SDK ngoài `Services/Implementations/SDK/` | Bảo vệ DIP |
| **DI toggle Mock/Real SDK** | **Compile-time** flag `#if USE_MOCK_SDK` (Xcode build setting `SWIFT_ACTIVE_COMPILATION_CONDITIONS`) — KHÔNG runtime `Bool` (C3) | Runtime toggle giữa lúc doc mở → session state mất |
| **Test** | XCTest + swift-testing | Mock qua protocol |
| **Dep manager** | Swift Package Manager | Không CocoaPods |

### 4.2 SDK + native + OSS fill-in

| Domain | Engine | License | Vai trò |
|---|---|---|---|
| **Core edit DOCX/XLSX/PPTX + PDF viewer** | **Artifex Smart Office SDK** | Commercial | Main engine — bọc trong `DocumentSessionManaging` |
| **PDF merge/split** | Apple `PDFKit` | Native | SDK không có |
| ~~**PDF compress**~~ | ~~`CGPDFContext` + `CGImage` downsample~~ | ~~Native~~ | **Dời Phase 1** |
| **DOCX/PPTX merge** | `ZIPFoundation` + `XMLCoder` trên OOXML | MIT / Apache | SDK không có; xem `Phase0-Implementation-Logic-v2.md` §7 |
| ~~**DOCX/PPTX compress**~~ | ~~`OOXMLMediaCompressor`~~ | ~~OSS~~ | **Dời Phase 1** |
| **OCR** | Apple `Vision` (`VNRecognizeTextRequest`) | Native | SDK không có |
| **Document scanner** | Apple `VNDocumentCameraViewController` | Native | Edge-detection + deskew tự động |
| ~~**Apple Pencil**~~ | ~~Apple `PencilKit` + `UIPencilInteraction`~~ | ~~Native~~ | **Dời Phase 1** |
| **Files app provider** | `NSFileProviderReplicatedExtension` + App Group | Native | Extension target riêng |
| **Face ID / Touch ID** | Apple `LocalAuthentication` (`LAContext`) | Native | MVP (đẩy lên vì có thời gian rảnh sau khi cắt Pencil/Compress/AI) |
| **E-signature — Tầng 1 vẽ tay** | Custom `SignatureCanvas` (UIView cho pen input, KHÔNG PencilKit vì Pencil dời Phase 1) → image → SDK place | Custom + SDK | MVP |
| **E-signature — Tầng 2 PKI** | SDK `ARDKOpenSSLSigner` (Artifex) hoặc `Security.framework` + CryptoKit | SDK/Native | Phase 2 (nếu SDK hỗ trợ), tự viết cost cao |
| **Watermark** | `CGPDFContext` (PDF) + OOXML (Word/PPT) | Native + OSS | MVP giới hạn PDF-only lúc export |
| **Comment/Note** | SDK Review ribbon (`SODKReviewRibbonViewController` nếu Artifex) + tự UI sidebar | SDK | Verify comment ghi vào file thật (xem `Phase0-Implementation-Logic-v2.md` §8.2) |
| **AirPrint** | `UIPrintInteractionController` + `UIPrintPageRenderer` từ SDK | Native + SDK | |
| ~~**AI**~~ | ⏸️ **Hoàn toàn ngoài MVP** — AI tóm tắt Phase 1, AI tạo văn bản Phase 2 | — | Không có trong MVP |
| **iCloud placeholder** | `NSMetadataQuery` + `ubiquitousItemDownloadingStatusKey` | Native | Xem `Phase0-Implementation-Logic-v2.md` §4.2 |
| **File coordination** | `NSFileCoordinator` + `NSFilePresenter` | Native | Đồng bộ giữa app + Files Provider extension |
| **Metadata store (Tủ hồ sơ)** | GRDB.swift **hoặc** SwiftData | MIT / Native | Quyết định Sprint 0.2 |
| **Folder bookmark** | `URL.bookmarkData` + Keychain (`SecItem`) | Native | Bền vững qua app restart, xử lý `isStale` |

**Third-party Swift Package cần thêm:**
- `ZIPFoundation` (Apache 2.0)
- `XMLCoder` (MIT) — hoặc `SWXMLHash` (MIT)
- `GRDB.swift` (MIT) — nếu chọn SQLite thay SwiftData (quyết định Sprint 0.2)
- Artifex SDK — theo hướng dẫn vendor (thường là XCFramework binary)

---

## 5. Folder Structure

```
Word Office/                                         # Xcode project
├── Word Office/                                     # Main app target
│   ├── App/
│   │   ├── Word_OfficeApp.swift                     # @main + DI wiring
│   │   ├── AppState.swift                           # @Observable — metadata only (launch count, flags, folderPermissionGranted) — C5
│   │   ├── ThemeStore.swift                         # @Observable — theme, font, accent (C5 split)
│   │   ├── SessionStore.swift                       # @Observable — current doc session ref, dirty, autosave (C5 split)
│   │   ├── LibraryStore.swift                       # ★ MỚI — @Observable — DocumentMetadata list, draftCount (Tủ hồ sơ mục 10)
│   │   └── DependencyContainer.swift                # DI factory. Mock↔Real SDK swap qua #if USE_MOCK_SDK compile flag (C3)
│   │
│   ├── Models/                                      # Pure data — no logic, no import SDK
│   │   ├── DocumentRef.swift                        # id, name, url, modifiedAt, kind
│   │   ├── DocumentKind.swift                       # txt, rtf, md, docx, xlsx, pptx, pdf, hwp
│   │   ├── DocumentContent.swift                    # Content wrapper
│   │   ├── DocumentMetadata.swift                   # ★ MỚI — documentID, status, lastOpenedAt, remindAt (Tủ hồ sơ)
│   │   ├── DocumentStatus.swift                     # ★ MỚI — .draft | .reviewed | .signed | .sent
│   │   ├── FolderBookmark.swift                     # ★ MỚI — bookmark data + resolved URL + isStale flag
│   │   ├── Comment.swift                            # id, anchor, author, body, replies, resolved
│   │   ├── Signature.swift                          # Tầng 1 (image) vs Tầng 2 (cert)
│   │   ├── Watermark.swift                          # text/image, opacity, rotation
│   │   ├── OCRResult.swift                          # blocks + confidence
│   │   └── AppTheme.swift                           # system, light, dark
│   │   # AIRequest.swift → Phase 1+ (AI tóm tắt)
│   │
│   ├── Services/
│   │   ├── Protocols/                               # ISP-split, small
│   │   │   ├── Document/
│   │   │   │   ├── DocumentSessionManaging.swift    # open/close SDK session
│   │   │   │   ├── DocumentReading.swift
│   │   │   │   ├── DocumentWriting.swift
│   │   │   │   ├── DocumentListing.swift
│   │   │   │   ├── DocumentCreating.swift
│   │   │   │   └── DocumentExporting.swift          # export as PDF
│   │   │   ├── Autosave/AutosaveScheduling.swift
│   │   │   ├── Library/                             # ★ MỚI — Tủ hồ sơ (mục 10)
│   │   │   │   ├── FolderPermissionGranting.swift   # xin quyền thư mục, lưu bookmark
│   │   │   │   ├── FolderBookmarkResolving.swift    # resolve + isStale + revoke handling
│   │   │   │   ├── DocumentLibraryScanning.swift    # scan thư mục → list DocumentRef
│   │   │   │   ├── MetadataStoring.swift            # CRUD DocumentMetadata
│   │   │   │   └── RemindScheduling.swift           # filter remindAt <= now (in-app, không push)
│   │   │   ├── PDFTools/
│   │   │   │   ├── PDFMerging.swift
│   │   │   │   └── PDFSplitting.swift
│   │   │   │   # PDFCompressing.swift → Phase 1
│   │   │   ├── OfficeTools/
│   │   │   │   └── OfficeMerging.swift              # DOCX/PPTX qua OOXML
│   │   │   │   # OfficeCompressing.swift → Phase 1
│   │   │   ├── Recognition/TextRecognizing.swift    # OCR
│   │   │   ├── Signature/
│   │   │   │   ├── SignatureDrawing.swift
│   │   │   │   ├── SignaturePKISigning.swift        # Phase 2 (nếu SDK support)
│   │   │   │   └── SignatureVerifying.swift
│   │   │   ├── Comment/
│   │   │   │   ├── CommentReading.swift
│   │   │   │   └── CommentWriting.swift
│   │   │   ├── Watermark/WatermarkApplying.swift
│   │   │   # AI/ → Phase 1+ (DocumentSummarizing) + Phase 2 (DocumentGenerating)
│   │   │   ├── Security/BiometricLocking.swift
│   │   │   └── FileIO/
│   │   │       ├── LocalFileService.swift
│   │   │       ├── DocumentImporting.swift          # ← đã tạo Sprint 0.2 partial, giữ cho luồng phụ 4.5
│   │   │       ├── iCloudImporting.swift
│   │   │       └── FilesProviderCoordinating.swift
│   │   │
│   │   └── Implementations/
│   │       ├── SDK/                                 # ⚠️ CHỈ folder này import SDK
│   │       │   ├── Mock/                            # Sprint 0.1 → swap khi có license
│   │       │   │   ├── MockArtifexDocumentSessionManager.swift
│   │       │   │   ├── MockArtifexDocumentReader.swift
│   │       │   │   ├── MockArtifexDocumentWriter.swift
│   │       │   │   ├── MockArtifexCommentReader.swift
│   │       │   │   ├── MockArtifexCommentWriter.swift
│   │       │   │   └── MockArtifexPrintRenderer.swift
│   │       │   └── Real/                            # Enable khi Artifex license về
│   │       │       ├── ArtifexDocumentSessionManager.swift
│   │       │       ├── ArtifexDocumentReader.swift
│   │       │       ├── ArtifexDocumentWriter.swift
│   │       │       ├── ArtifexCommentReader.swift
│   │       │       ├── ArtifexCommentWriter.swift
│   │       │       ├── ArtifexPKISigner.swift       # Phase 2
│   │       │       └── ArtifexPrintRenderer.swift
│   │       ├── Native/                              # Apple framework wrappers
│   │       │   ├── LocalFileServiceImpl.swift
│   │       │   ├── AutosaveScheduler.swift          # debounce + staging write
│   │       │   ├── PDFKitMerger.swift
│   │       │   ├── PDFKitSplitter.swift
│   │       │   # PDFKitCompressor.swift → Phase 1
│   │       │   ├── VisionTextRecognizer.swift
│   │       │   ├── SignatureCanvasDrawer.swift      # ★ CUSTOM view (không PencilKit vì Pencil dời Phase 1)
│   │       │   ├── WatermarkPDFRenderer.swift
│   │       │   ├── BiometricLockerImpl.swift
│   │       │   ├── iCloudPlaceholderImporter.swift  # ← đã có Sprint 0.2 partial
│   │       │   ├── DocumentImporter.swift           # ← đã có Sprint 0.2 partial (luồng phụ 4.5)
│   │       │   ├── FilesProviderSignaler.swift
│   │       │   ├── FolderPermissionPicker.swift     # ★ MỚI — xin quyền thư mục qua UIDocumentPickerViewController(.folder)
│   │       │   ├── FolderBookmarkStore.swift        # ★ MỚI — Keychain storage + resolve + isStale
│   │       │   ├── DocumentLibraryScanner.swift     # ★ MỚI — scan thư mục + auto-import
│   │       │   ├── MetadataStoreImpl.swift          # ★ MỚI — GRDB hoặc SwiftData (chọn Sprint 0.2)
│   │       │   └── RemindScheduler.swift            # ★ MỚI — in-app filter (không UNUserNotificationCenter)
│   │       └── OOXML/                               # OSS Swift cho SDK không cover
│   │           ├── DOCXMerger.swift                 # ZIPFoundation + XMLCoder
│   │           ├── PPTXMerger.swift
│   │           # OOXMLMediaCompressor.swift → Phase 1
│   │           └── OOXMLWatermarkInjector.swift
│   │       # AI/ → Phase 1+ (ProxyAISummarizer) + Phase 2 (ProxyDocumentGenerator)
│   │
│   ├── ViewModels/                                  # @Observable @MainActor — no SwiftUI, no SDK
│   │   ├── LibraryViewModel.swift                   # ★ MỚI — root của Tủ hồ sơ, coord LibraryStore
│   │   ├── DocumentListViewModel.swift              # giờ chỉ list phẳng, bị LibraryView bọc ngoài (hoặc merge lại)
│   │   ├── EditorViewModel.swift
│   │   ├── PDFToolsViewModel.swift                  # merge/split only (compress cắt)
│   │   ├── OCRViewModel.swift
│   │   ├── SignatureViewModel.swift
│   │   ├── CommentViewModel.swift
│   │   ├── WatermarkViewModel.swift
│   │   ├── FolderPermissionViewModel.swift          # ★ MỚI — CTA cấp/cấp lại quyền
│   │   └── SettingsViewModel.swift
│   │   # AIViewModel.swift → Phase 1+
│   │
│   ├── Views/
│   │   ├── Root/RootView.swift                      # NavigationSplitView adaptive — root giờ là LibraryView
│   │   ├── Library/                                 # ★ MỚI — Tủ hồ sơ (mục 10)
│   │   │   ├── LibraryView.swift                    # trang chủ tủ hồ sơ + draftCount badge
│   │   │   ├── DocumentCard.swift                   # 1 item: tên, status badge, remindAt, thumbnail
│   │   │   ├── DocumentStatusPicker.swift           # menu/swipe đổi status thủ công
│   │   │   ├── RemindAtField.swift                  # date picker sheet
│   │   │   └── ReauthorizePermissionCTA.swift       # UI khi bookmark revoke/isStale
│   │   ├── Sidebar/
│   │   │   ├── DocumentListView.swift               # giữ, dùng bên trong Library hoặc as-is
│   │   │   └── DocumentRowView.swift
│   │   ├── Editor/
│   │   │   ├── DocumentEditorSplitView.swift        # outline + SDK editor bọc UIViewControllerRepresentable
│   │   │   ├── SDKEditorHostView.swift              # UIViewControllerRepresentable
│   │   │   ├── FormatToolbarView.swift
│   │   │   └── OutlineSidebarView.swift
│   │   ├── PDFTools/
│   │   │   ├── MergeSplitView.swift                 # bỏ Compress khỏi tên
│   │   │   └── WatermarkSheetView.swift
│   │   ├── OCR/
│   │   │   ├── ScanFlowView.swift
│   │   │   └── OCRPreviewView.swift
│   │   ├── Signature/
│   │   │   ├── SignaturePlacementView.swift
│   │   │   └── SignatureCanvasView.swift            # ★ custom (không PencilKit)
│   │   ├── Comment/
│   │   │   ├── CommentSidebarView.swift
│   │   │   ├── CommentThreadView.swift
│   │   │   └── CommentIndicatorView.swift
│   │   # AI/ (AISummarySheet...) → Phase 1+
│   │   ├── Settings/SettingsView.swift
│   │   ├── Import/
│   │   │   ├── FolderPermissionOnboarding.swift     # ★ MỚI — onboarding xin quyền thư mục (luồng chính 4.1)
│   │   │   ├── AddFileMenu.swift                    # ← đã có Sprint 0.2, giữ làm entry phụ 4.5
│   │   │   └── ImportProgressView.swift             # iCloud download progress
│   │   └── Common/
│   │       ├── EmptyStateView.swift
│   │       ├── ConfirmDialog.swift
│   │       └── ErrorBanner.swift
│   │
│   ├── Extensions/
│   │   ├── URL+Documents.swift
│   │   ├── URL+UTI.swift                            # xác định kind từ UTI, không tin đuôi file
│   │   ├── URL+DocumentID.swift                     # ★ MỚI — sinh documentID bền vững từ bookmark + hash
│   │   └── AttributedString+RTF.swift
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── Localizable.xcstrings                    # String Catalog EN only (VI Phase 2)
│   │   └── PrivacyInfo.xcprivacy                    # File-timestamp declaration cho FileProvider
│   │
│   └── Word Office.entitlements                     # App Groups, iCloud
│
├── FilesProviderExtension/                          # NEW target (Sprint 0.3)
│   ├── FileProviderExtension.swift                  # NSFileProviderReplicatedExtension
│   ├── EnumeratorImpl.swift
│   ├── ThumbnailCache.swift
│   ├── AppGroupBridge.swift
│   ├── Info.plist
│   └── FilesProviderExtension.entitlements
│
├── Shared/                                          # Swift Package chia sẻ app + extension
│   ├── AppGroupContainer.swift
│   ├── MetadataStore.swift                          # SQLite/CoreData shared (Tủ hồ sơ + FileProvider dùng chung)
│   └── FileCoordinatorWrapper.swift
│
├── Word OfficeTests/
│   ├── ViewModels/                                  # unit test tất cả VM
│   │   └── LibraryViewModelTests.swift              # ★ MỚI
│   ├── Services/
│   │   ├── OOXMLMergerTests.swift                   # round-trip test DOCX
│   │   ├── AutosaveSchedulerTests.swift
│   │   ├── VisionTextRecognizerTests.swift
│   │   ├── DocumentLibraryScannerTests.swift        # ★ MỚI — scan temp dir với fixtures
│   │   ├── FolderBookmarkStoreTests.swift           # ★ MỚI — isStale/revoke handling
│   │   └── MetadataStoreImplTests.swift             # ★ MỚI — CRUD + query remindAt
│   └── Mocks/                                       # MockDocumentReading, MockMetadataStore, etc.
│
├── Word OfficeUITests/
└── FilesProviderExtensionTests/

# Backend/ (Cloudflare Workers + Hono + App Attest) → Phase 1+ khi ship AI tóm tắt
```

---

## 6. Sprint plan — 5 sprints / ~13 tuần (reshuffle theo scope v2.2)

### Sprint 0.1 — Foundation + Mock SDK skeleton (tuần 1–3) — **GIỮ NGUYÊN**

**Goal:** MVVM+SOLID skeleton hoàn chỉnh, UI đầy đủ với **Mock SDK layer** theo pattern Artifex API. Khi license Artifex về, chỉ swap folder `Mock/` → `Real/` trong DI container, VM/View không đổi 1 dòng.

**Trạng thái hiện tại (2026-08-27):** ✅ **DONE** — 104 Swift files + 52 colorsets, build clean iOS Sim, verified launches iPhone 17 Pro sim. Chi tiết ở `GUIDELINE.md`.

### Sprint 0.2 — Core editing + Autosave + **Add file mới (folder-scan) + Tủ hồ sơ core loop** (tuần 4–7, +1 tuần)

**Goal:** Edit DOCX/XLSX/PPTX/PDF thật, autosave production-grade, **core loop Tủ hồ sơ chạy end-to-end**, import file từ folder auto-scan + luồng phụ Local/iCloud thủ công.

**Ưu tiên cao (core loop MVP thật — làm trước Add file phụ):**
- [ ] **Quyết định persistence backend**: Core Data vs GRDB vs SwiftData — spike 1 ngày, chốt ngày 2
- [ ] Models: `DocumentMetadata`, `DocumentStatus`, `FolderBookmark` — `Sendable`, `Codable`
- [ ] Protocols: `FolderPermissionGranting`, `FolderBookmarkResolving`, `DocumentLibraryScanning`, `MetadataStoring`, `RemindScheduling`
- [ ] `FolderPermissionPicker` — `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`, callback → bookmark
- [ ] `FolderBookmarkStore` — save/load Keychain, `URL(resolvingBookmarkData:)` + `isStale` handling
- [ ] `DocumentLibraryScanner` — quét folder, filter UTI hỗ trợ, xử lý iCloud placeholder (không block cả list), emit `DocumentRef[]`
- [ ] `MetadataStoreImpl` — CRUD + query `remindAt <= now` + `status == .draft` count
- [ ] `LibraryStore` (4-store split, mở rộng từ v2.1)
- [ ] `LibraryViewModel` — coord scanner + metadata store + folder permission state
- [ ] `LibraryView` — trang chủ tủ hồ sơ + `draftCount` badge prominent
- [ ] `DocumentCard` + `DocumentStatusPicker` swipe/menu + `RemindAtField` sheet
- [ ] `FolderPermissionOnboarding` — first-run flow + `ReauthorizePermissionCTA` khi bookmark revoke
- [ ] `URL+DocumentID` extension — sinh key bền vững (KHÔNG dùng path)

**Add file luồng phụ 4.5 (đã bắt đầu Sprint 0.2 partial, hoàn thiện):**
- [ ] Wire `AddFileMenu` vào toolbar (đã tạo, chưa wire)
- [ ] Register `iCloudImporter` + `DocumentImporter` trong DI
- [ ] `DocumentListViewModel.importFiles(from:)` batch import

**Core editing + Autosave (giữ theo user):**
- [ ] **Swap `MockArtifex*` → `ArtifexDocumentSessionManager` thật** trong DI (khi license về)
- [ ] **PoC critical — test SDK có chịu embed vs full-screen** (blocking Sprint 0.4 multi-pane)
- [ ] `FormatToolbarView` — Bold/Italic/Underline/Align/List — route qua SDK style API
- [ ] Autosave: debounce 2s + hard timer 30s + staging file + atomic rename (`Phase0-Implementation-Logic.md` §2 bản gốc)
- [ ] Crash-recovery: scan `*.autosave.tmp` khi launch → banner "Khôi phục?"
- [ ] Save-on-background lifecycle: `@Environment(\.scenePhase)` → `background` gọi `SessionStore.flushIfNeeded`
- [ ] Convert PDF: SDK `exportAs(.pdf)` cho DOCX/XLSX/PPTX
- [ ] **Round-trip test** với file thật (5–10 DOCX/XLSX/PPTX/PDF thực tế) — validate fidelity đủ hay không
- [ ] Unit tests + integration tests

**Deliverable Sprint 0.2:** Mở app lần đầu → onboarding xin quyền thư mục → cấp quyền → tủ hồ sơ tự đầy → tap 1 file → edit → autosave → về tủ → thấy `draftCount` giảm khi đổi status.

> **Sprint 0.2 kéo dài 4 tuần** (thêm 1 tuần vs v2.1 để nhét Tủ hồ sơ + folder-scan). Nếu Artifex license chưa về, phần core editing/autosave dùng Mock, Tủ hồ sơ chạy 100% không phụ thuộc SDK.

### Sprint 0.3 — PDF power tools + Files Provider + AirPrint + OCR (tuần 8–10)

**Goal:** Bộ USP PDF hoàn chỉnh + Files app hiện app như 1 location + scan giấy → text. **BỎ Compress** (dời Phase 1).

- [ ] `PDFKitMerger` / `PDFKitSplitter` (PDFKit) — **KHÔNG** `PDFKitCompressor`
- [ ] `DOCXMerger` / `PPTXMerger` (ZIPFoundation + XMLCoder) — validate mở lại bằng Word/PowerPoint thật
- [ ] `MergeSplitView` UI + progress + background queue + validate output — **BỎ** Compress option
- [ ] **FilesProviderExtension target** setup: App Group, entitlement, PrivacyInfo (`Phase0-Implementation-Logic-v2.md` §3)
- [ ] `NSFileProviderReplicatedExtension` — enumerator, item, fetchContents, thumbnail cache
- [ ] **MetadataStore share qua App Group** — cùng nguồn dữ liệu với Tủ hồ sơ mục 10 (Sprint 0.2)
- [ ] `registerFileProviderDomainIfNeeded()` từ app chính
- [ ] 2-chiều sync: sửa trong Files app ↔ sửa trong app chính
- [ ] `ArtifexPrintRenderer` + `UIPrintInteractionController` (AirPrint)
- [ ] `VisionTextRecognizer` với `VNRecognizeTextRequest`
- [ ] `ScanFlowView` với `VNDocumentCameraViewController`
- [ ] Recognition languages: VN + EN + user-select
- [ ] Output PDF searchable; output DOCX editable = optional Phase 2
- [ ] Confidence highlight cho vùng OCR nghi ngờ

### Sprint 0.4 — iPad-native + Comment + E-sig + Watermark (tuần 11–12) — **RÚT 1 TUẦN vs v2.1**

**Goal:** Trải nghiệm dân pro dùng iPad Pro thật + collab tools. **BỎ Apple Pencil** (dời Phase 1) — cắt 1 tuần.

- [ ] `DocumentEditorSplitView` — outline sidebar + SDK editor bọc `UIViewControllerRepresentable`
- [ ] **Kiểm tra sớm:** SDK có chịu embed vs chỉ full-screen — nếu không, phải fallback hoặc negotiate vendor
- [ ] ~~`PencilKitSignatureDrawer` với `PKCanvasView`~~ → dời Phase 1
- [ ] ~~`UIPencilInteraction` cho double-tap switch tool~~ → dời Phase 1
- [ ] **`SignatureCanvasDrawer` custom** (UIView cho pen input, không PencilKit) — vẽ tay chữ ký MVP
- [ ] Keyboard shortcuts routing — chỉ define ở app-level phím KHÔNG conflict với SDK
- [ ] Trackpad hover `.hoverEffect` cho iPad + Magic Keyboard
- [ ] `CommentReading/Writing` qua SDK Review ribbon
- [ ] **Verify comment ghi vào file thật** — export → mở bằng MS Word/Acrobat → còn không? — nếu không, fallback tự viết `word/comments.xml`
- [ ] `CommentSidebarView` + `CommentIndicatorView` (margin) + `CommentThreadView` (popover)
- [ ] `SignatureDrawing` (vẽ tay MVP) + `SignaturePlacementView` (kéo-thả khung)
- [ ] E-sig PKI (Tầng 2): dùng `ArtifexPKISigner` nếu SDK có sẵn; nếu không → Phase 2
- [ ] `WatermarkPDFRenderer` — text/image + opacity + rotation + tile
- [ ] Watermark chỉ lúc export PDF (không sửa file gốc) — MVP scope

### Sprint 0.5 — Polish + Face ID + TestFlight (tuần 13) — **RÚT xuống 1 tuần**

**Goal:** App polish sẵn beta, submit TestFlight. (AI + Pencil + Compress đã cắt, giảm ~2 tuần khỏi sprint này.)

- [ ] `BiometricLockerImpl` — Face ID/Touch ID khoá app
- [ ] Empty states, error banners, retry UX toàn app
- [ ] Preview self-contained mock cho mọi View (bao gồm `LibraryView` với `MockMetadataStore`)
- [ ] Manual test: iPhone 15 sim, iPad Pro sim, Mac Catalyst, iPhone SE (small screen)
- [ ] Accessibility labels + Dynamic Type
- [ ] Performance pass — chạy Instruments SwiftUI template trên iPad Pro, fix hitch nếu có
- [ ] TestFlight beta submit
- [ ] Onboarding tour ngắn (3 màn): (1) cấp quyền thư mục → Tủ hồ sơ, (2) status + reminder in-app, (3) PDF tools + OCR

**Timeline tổng cộng:** Sprint 0.1 (3 tuần) + 0.2 (4 tuần, +1 vì thêm Tủ hồ sơ) + 0.3 (3 tuần, -0 nhưng bỏ Compress) + 0.4 (2 tuần, -1 vì bỏ Pencil) + 0.5 (1 tuần, -1 vì bỏ AI + polish nhẹ hơn) = **13 tuần** (giữ nguyên tổng, chỉ shuffle nội dung).

---

## 7. Testing Strategy

- **Unit tests bắt buộc:**
  - Tất cả ViewModels với mock services (protocol-based) — **bao gồm `LibraryViewModelTests`**
  - `AutosaveScheduler` — debounce timing + atomic rename
  - `OOXML mergers` — round-trip DOCX/PPTX
  - `VisionTextRecognizer` — golden set ảnh scan
  - **`DocumentLibraryScannerTests`** — scan temp dir với fixtures (mix docx/pdf/txt/non-supported)
  - **`FolderBookmarkStoreTests`** — save/load/isStale/revoke handling
  - **`MetadataStoreImplTests`** — CRUD + query `remindAt <= now` + `status == .draft` count
- **Integration tests:**
  - `ArtifexDocumentSessionManager` với file thật (fixture DOCX/XLSX/PPTX/PDF)
  - `FilesProviderExtension` với `NSFileProviderManager.enableTestingMode`
  - **Tủ hồ sơ end-to-end**: onboarding → cấp quyền → scan → hiển thị metadata → đổi status → verify persist
- **Round-trip fidelity test** — Sprint 0.2 gate:
  - 5–10 file thật của user → open → save → open trong MS Word/Acrobat → còn nguyên chưa?
  - Nếu <70% fidelity → decision point: escalate với Artifex support hoặc adjust scope
- **Coverage target:** >70% ViewModels, >50% overall
- **Previews:** self-contained mock, không phụ thuộc SDK/filesystem/Keychain (`MockFolderBookmarkStore` + `MockMetadataStore` in-memory)
- **Manual test matrix:** iPhone 15 / iPad Pro / iPad mini / Mac Catalyst — mỗi Sprint

---

## 8. Success Criteria Phase 0 (MVP)

Phase 0 gọi là **DONE** khi:

- ✅ App build không lỗi trên iPhone / iPad / Mac Catalyst
- ✅ User mở/sửa/lưu DOCX/XLSX/PPTX/PDF thật, fidelity ≥70%
- ✅ Crash giữa lúc save → mở lại app → banner "Khôi phục?" hiện đúng
- ✅ iPhone: NavigationStack push editor; iPad: split view sidebar + editor; Mac Catalyst: sidebar collapse
- ✅ Files app hiện app như 1 vị trí duyệt được (sau khi user bật lần đầu)
- ✅ **First launch: onboarding xin quyền thư mục → cấp quyền → Tủ hồ sơ tự đầy** (mục 10 core loop)
- ✅ **Tủ hồ sơ: hiển thị metadata, đổi status thủ công persist đúng, `draftCount` giảm khi đổi status khỏi `.draft`**
- ✅ **`remindAt` filter chạy đúng khi mở app (in-app, KHÔNG push notification)**
- ✅ **Bookmark revoke → hiện CTA "Cấp lại quyền" (không im lặng)**
- ✅ Add file thủ công (luồng phụ 4.5): import Local + iCloud (bao gồm placeholder chưa download) chạy đúng
- ✅ AirPrint 1 file DOCX/PDF thành công
- ✅ Scan giấy → OCR ra text tiếng Việt + Anh → export searchable PDF
- ✅ Merge 2 PDF, split PDF theo range chạy đúng (**KHÔNG** compress trong MVP)
- ✅ Multi-pane iPad: outline sidebar + editor cùng lúc (**KHÔNG** Pencil trong MVP)
- ✅ Cmd+S/B/I/U/F/Z hoạt động
- ✅ Comment thêm/reply/resolve — file export mở bằng Word thật vẫn thấy comment
- ✅ E-signature vẽ tay (custom canvas, không PencilKit) đặt được lên PDF, giữ vị trí đúng khi mở lại
- ✅ Watermark áp lúc export PDF
- ✅ Face ID lock chạy đúng
- ✅ Không crash khi filesystem empty, file corrupt, mất kết nối giữa lúc iCloud sync, **bookmark revoke, thư mục cấp quyền bị xoá**
- ✅ Unit tests pass, coverage >70% ViewModels
- ✅ TestFlight beta submit thành công

---

## 9. Rủi ro & mitigation

| Rủi ro | Xác suất | Impact | Mitigation |
|---|---|---|---|
| **Folder bookmark revoke → tủ hồ sơ im lặng trống → aha moment biến mất** | Cao | Rất cao | Bắt buộc UI `ReauthorizePermissionCTA` khi resolve fail hoặc `isStale`; test manual scenario: cấp quyền → tắt trong Settings → mở lại app → phải hiện CTA (`Phase0-Implementation-Logic-v2.md` §10.3) |
| **Persistence backend chọn sai (Core Data vs GRDB vs SwiftData) → refactor giữa Sprint 0.3** | Trung | Cao | Spike 1 ngày ngày đầu Sprint 0.2, quyết định trước khi viết `MetadataStoreImpl`. Nếu SwiftData chưa đủ query filter → dùng GRDB (đơn giản, mature, đã dùng nhiều production) |
| **`documentID` dùng nhầm file path → file di chuyển trong thư mục → mất metadata** | Cao (nếu để nhỡ tay) | Cao | Bookmark data + hash content (`URL+DocumentID` extension), KHÔNG path. Unit test scenario: rename file → metadata vẫn theo đúng file |
| **Auto-suy luận status (mở file = "đã xem lại") → phá tín hiệu "còn nợ việc" của core loop** | Trung (dễ bị đề xuất "cho tiện") | Rất cao | Chốt cứng: status đổi CHỈ khi user thao tác thủ công (menu/swipe). Không có code path nào auto-update status trừ khi user explicit action |
| Mac Catalyst NavigationSplitView edge case (columnVisibility sync, sidebar hover) → vỡ Sprint 0.4 multi-pane muộn | Trung | Cao | **PoC riêng Sprint 0.1 ngày đầu** (C1) — verify 3-column split + toolbar + hover trước khi commit architecture. Sẵn `#if targetEnvironment(macCatalyst)` fallback pattern |
| Artifex license với sales chậm/failed → block Sprint 0.2 | Trung | Cao | Sprint 0.1 dựng Mock SDK layer đầy đủ + Tủ hồ sơ (mục 10) chạy 100% không phụ thuộc SDK, có thể ship non-editing MVP nếu license kẹt. Escalate sales sau tuần 3; fallback: PSPDFKit Nutrient PDF-only + scope-down Office edit |
| Artifex ObjC types không `Sendable` → Swift 6 strict concurrency spam warning không xử lý được | Trung | Trung | Bọc trong `@unchecked Sendable` wrapper + isolate qua actor + chú thích rõ lý do mỗi lần (C4). KHÔNG downgrade concurrency mode để "cho qua" |
| Runtime DI toggle Mock↔Real làm mất session state giữa lúc doc mở | Cao (nếu để runtime) | Cao | Dùng **compile-time** flag `#if USE_MOCK_SDK` từ Sprint 0.1 (C3) — không tạo runtime toggle |
| `AppState` phình god object → mọi view re-invalidate khi mở/đóng doc → hitch UI | Trung | Cao | Tách **4 store** theo domain từ Sprint 0.1 (C5) + `LibraryStore` riêng cho Tủ hồ sơ — không gộp session/library vào AppState |
| Artifex license về nhưng round-trip fidelity thực tế thấp hơn expectation | Trung | Cao | Sprint 0.2 gate cứng — test với file thật user cấp trước khi tiếp tục |
| SDK không cho embed view (chỉ full-screen) → hỏng multi-pane Sprint 0.4 | Trung | Cao | Kiểm tra ngay Sprint 0.1 với PoC nhỏ, không đợi Sprint 0.4 |
| Round-trip fidelity <70% với file user thật | Trung | Rất cao | Sprint 0.2 gate — nếu fail, escalate Artifex support hoặc adjust MVP scope (drop XLSX/PPTX edit tạm) |
| Files Provider extension debug tốn thời gian (compliance + edge cases) | Cao | Trung | Bắt đầu sớm, dùng `NSFileProviderManager.enableTestingMode`, không đợi cuối Sprint 0.3. **MetadataStore share App Group phải setup xong ở Sprint 0.2** để Sprint 0.3 dùng ngay |
| OOXML merge tự viết ra file "app tự đọc được" nhưng Word thật báo hỏng | Cao | Trung | Bắt buộc test round-trip bằng MS Word thật (không chỉ chính app), gate qua Sprint 0.3 |
| Timeline 13 tuần vẫn trượt (dù đã cắt Pencil/Compress/AI) | Trung | Trung | Sẵn sàng cắt tiếp: (a) E-sig PKI → Phase 2, (b) OCR output DOCX editable → Phase 2, (c) DOCX/PPTX merge → Phase 2 (giữ PDF merge/split) |
| Design system chưa gửi → phải rework UI Sprint 0.5 | Trung | Thấp | Dùng system default xuyên suốt, không invest UI polish sớm |
| Marketing áp lực thêm AI vì đối thủ có → phá scope Phase 0 | Trung | Trung | Confirm bằng chứng: static analysis đã xác nhận 0/3 đối thủ có AI thật; MVP không AI vẫn khác biệt rõ ở **core loop Tủ hồ sơ (0/N đối thủ có)** + PDF tools + iPad-native + on-device |
| Giả thuyết "user có đủ tài liệu dở dang thường xuyên" (core loop Tủ hồ sơ dựa vào) chưa kiểm chứng | Trung | Cao | **Không** đầu tư thêm gamification/streak cho tới khi có data thật từ TestFlight beta xác nhận loop chạy (ghi ở `product-strategy-master.md` §7 + `Phase0-Implementation-Logic-v2.md` §10.5) |

---

## 10. Handoff Phase 1

Kiến trúc Phase 0 đã chuẩn bị sẵn cho Phase 1 vì mọi thứ đi qua protocol:

- **Apple Pencil** (dời từ MVP v2.1):
  - Enable `PKCanvasView` trong `SignatureCanvasView` (giờ dùng custom UIView) + `UIPencilInteraction` cho double-tap switch tool
  - Logic vẽ tay/Scribble giữ nguyên ở `Phase0-Implementation-Logic.md` §6.2 bản gốc, dùng lại không viết lại
- **Compress PDF/DOCX/PPTX** (dời từ MVP v2.1):
  - Enable `PDFKitCompressor` + `OOXMLMediaCompressor` (`CGImage` downsample)
  - Logic giữ nguyên ở `Phase0-Implementation-Logic.md` §8.1/8.2 phần compress bản gốc
- **AI tóm tắt tài liệu** (dời từ MVP v2.1, ưu tiên #1 Phase 1):
  - Logic đầy đủ ở `Phase0-Implementation-Logic-v2.md` **Phụ lục A** — thu hẹp scope so với "tóm tắt/viết lại/hỏi-đáp" cũ, chỉ còn tóm tắt
  - Backend `Backend/ai-proxy/` — Cloudflare Workers free tier + Hono + TypeScript
  - App Attest verify (`DeviceCheck.framework`)
  - Provider adapter: Anthropic Claude Haiku (đề xuất) hoặc OpenAI
  - Service protocol: `DocumentSummarizing` — inject impl `ProxyAI*` qua DI
  - View: `AISummarySheet` — side panel, KHÔNG chèn vào tài liệu (khác Phụ lục B)
  - Cache theo `documentID + lastModifiedHash` — dùng lại `documentID` bền vững từ MVP (§10.2)
  - Trigger UI: nổi bật ở tài liệu `.draft` lâu chưa mở lại → điểm nối với core loop Tủ hồ sơ (mục 10 MVP)

## 11. Handoff Phase 2

- **AI tạo văn bản từ mô tả (chat-to-document)** — logic đầy đủ đã viết ở `Phase0-Implementation-Logic-v2.md` **Phụ lục B**:
  - `GeneratedContent` schema (JSON có cấu trúc, không markdown tự do)
  - `DocumentBuilder.build(from:) -> DocumentSession` — cùng interface với file mở từ đĩa
  - `clauseLibrary` cho hợp đồng/báo giá (KHÔNG để AI tự bịa điều khoản pháp lý)
  - Chip chọn loại tài liệu trước khi mô tả (không auto-classify)
  - Streaming thẳng vào canvas (không bubble chat riêng)
  - Backend proxy DÙNG CHUNG với AI tóm tắt (Phase 1) — không xây 2 hệ thống
- **E-sig PKI** (nếu chưa vào MVP) = enable `ArtifexPKISigner` hoặc `Security.framework` impl
- **Widget + Siri Shortcuts** = extension target mới, dùng lại `MetadataStore` App Group
- **Dropbox/Google Drive** = thêm impl `DocumentListing`/`DocumentReading` cho từng cloud, swap trong DI
- **Vertical templates freelancer** = thêm module `Templates/` + preview + inject vào `DocumentCreating` — **liên kết trực tiếp với `clauseLibrary` Phụ lục B.3**, xây thư viện điều khoản này SỚM trong Phase 1 để Phase 2 dùng ngay

Phase 3+ tiếp tục open — Mac app thật (Mac Catalyst → SwiftUI native macOS), Family/Team seat, visionOS.

---

## 12. Open Questions còn lại (không blocking Sprint 0.1)

1. **A6 — Bundle ID + Apple Developer team ID** — user gửi sau, cần trước Sprint 0.3 (Files Provider entitlement)
2. **A9 — Design system ETA** — không có thì Sprint 0.5 UI polish giới hạn, giữ system default
3. **Persistence backend cho `MetadataStore`** — Core Data vs GRDB vs SwiftData — spike ngày đầu Sprint 0.2

Đã confirm (2026-08-27): A1 Artifex ✅ · A2 Mock skeleton + license đang với sales ✅ · A3 iOS 17 ✅ · **A5 AI hoàn toàn ngoài MVP** ⏸️ · A7 English only MVP ✅ · **A11 Core loop = Tủ hồ sơ** ✅ · **A12 Add file = folder-scan luồng chính** ✅

---

*Doc v2.2 gộp scope MVP mới (v2, 27/08 + user override giữ Autosave) vào kiến trúc + Sprint plan thống nhất. Logic chi tiết per feature tra cứu `Phase0-Implementation-Logic-v2.md` (mục 1–10 + Phụ lục A/B). Định vị & priority tra cứu `product-strategy-master.md`. **Sprint 0.1 đã DONE — resume tại Sprint 0.2, xem `GUIDELINE.md` "Where we left off".***
