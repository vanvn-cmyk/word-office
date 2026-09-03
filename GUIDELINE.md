# Word Office — Guideline bám theo (Sprint 0.1 → 0.2 gate)

> **Mục tiêu file này:** danh sách công việc **theo thứ tự** để bạn tự làm được.
> **Cập nhật:** 2026-09-03 (session 10 — đóng lại 2 vòng review dở dang từ Session 9 (`/code-review` + `/swiftui-expert-skill`, tổng 8 finding fix hết) + fix bug FAB "+" menu tràn phải màn hình (user tự phát hiện trên iPhone 16e sim) + upgrade tab bar pill lên **Liquid Glass** (iOS 26 native, nhất quán màu giữa các tab) + outside-tap-to-dismiss cho FAB menu. Chi tiết đầy đủ ở `CHANGELOG.md` Session 10.)

---

## ⭐ Where we left off — resume ở đây khi mở lại project

**Session 10 (2026-09-03) end state:**

- ✅ **Fix FAB "+" menu tràn phải màn hình** — restructure `LibraryAddButton.body` từ `VStack(alignment: .trailing)` bao (menu+FAB) — kiến trúc cũ đẩy `HStack` `customTabBar` phồng 220pt vượt available width → sang `fabButton.overlay(alignment: .bottomTrailing) { menu.fixedSize().padding(.bottom, fabDiameter + DSSpacing.lg) }`. Padding trick vì `.alignmentGuide(.top)` không propagate qua overlay chain khi có `.transition` (verified thực tế).
- ✅ **Liquid Glass tab bar pill** — chọn Option A qua `/swiftui-expert-skill` tư vấn (3 option). Lý do: `.regularMaterial` cũ adaptive → pill khác màu giữa Library vs Settings tab. Glass render surface độc lập → nhất quán. Extension `tabBarPillStyle()` collapse thành 1 dòng direct call sau finding review (fallback iOS <26 là dead code do `IPHONEOS_DEPLOYMENT_TARGET = 26.2` + không hỗ trợ Mac Catalyst).
- ✅ **Outside-tap-to-dismiss FAB menu** — lift `isMenuOpen` state từ `LibraryAddButton` `@State private` → `RootView` `@Binding`. Thêm scrim `Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture` giữa content ZStack và `customTabBar`. `.onChange(of: selectedTab)` auto-close khi đổi tab. `withAnimation(.easeOut(duration: 0.15))` matched giữa 2 helper cho animation identical.
- ✅ **Accessibility grouping menu** — `.accessibilityElement(children: .contain) + .accessibilityLabel("Add options")` trên `addMenuContent`, `.accessibilityAddTraits(.isHeader)` trên section header, `.contentShape(RoundedRectangle)` để hit-test absorb toàn card (fix tap fall-through qua dead area vào fabButton).
- ✅ **2 vòng review đầy đủ** (`/code-review` + `/swiftui-expert-skill`) — 8 finding trong 2 vòng, fix hết. Session 9's "hold" đã xử lý xong.
- ✅ **Build sạch + install lên iPhone 16e sim** (`iOS 26.3`) qua CLI `simctl install/launch` sau mỗi fix để user verify bằng mắt.

**Resume session sau**: bạn chọn 1 trong 3 track (recommendation của session 10):
1. **Small polish**: fix nit hiệu năng `LibraryView` (computed properties `dueEntries`/`groupedSections` gọi 2-3x/render, gom vào `let` cục bộ) + xoá dead views `Views/Sidebar/DocumentListView.swift` + `Views/Tabs/FilesTabView.swift` (đã bị `RootView.customTabBar` thay từ Session 6, giờ orphan) + quyết định wire hoặc ẩn Premium `TODO(paywall)` icon.
2. **Sprint 0.3 non-UI** (không blocked bởi Artifex hoặc Team ID): PDF Merge/Split thật (mục 8 MVP, PDFKit native — protocol đã có, cần thay stub) → OCR Vision native (mục 7 MVP, `VNRecognizeTextRequest`) → AirPrint wrapper.
3. **Sprint 0.4+ MVP items lớn**: iPad adaptive layout (`NavigationSplitView` + size classes, mục 3 + 6), Comment/note (mục 9), E-signature vẽ tay + Watermark (mục 11), Crash-recovery UI banner (backend ready từ Session 4, UI wire chưa xong).

**External blockers không đổi**: Artifex license (Sprint 0.2 gate cứng), Bundle ID + Team ID (App Group cho `FilesProviderExtension`).

---

**Session 9 (2026-09-02) end state:**

- ✅ **Library Home v10 xong** — Favourite (field + filter + toggle UI), Search (`.searchable`, flat result), Grid/List view toggle, FAB đổi thành Menu 3 nhóm (Create new — chỉ Word thật, Excel/PPT "Coming soon" vì SDK Mock no-op 2 format đó / Add existing / Scan — tái dùng đúng `OCRViewModel` Tools tab). Title "Your Library" → "Your Cabinet". Chi tiết đầy đủ + toàn bộ file đụng tới ở `CHANGELOG.md` Session 9.
- ✅ **FAB "+" cạnh tab bar — kiến trúc cuối: `RootView` tự vẽ tab bar riêng, bỏ hẳn `TabView`/`Tab`.** Lý do: `.overlay` lên `TabView` gây vệt cắt góc thật trên tab bar; `.tabViewBottomAccessory` (API chính thức iOS 26) bọc nội dung trong pill cố định, clip mất menu khi mở. Không còn API native nào phù hợp → tự vẽ. Cả 3 tab giữ sống song song (không dùng `switch`) để không mất navigation state khi đổi tab.
- ✅ **App icon + Splash screen mới** — icon áp ảnh user cung cấp (fix lỗi góc trắng do source có bo góc+shadow riêng), splash tagline "From draft to signed — all on your device" (chốt qua brainstorm định vị, 5 phương án).
- ✅ **Bỏ dấu chấm cuối câu toàn bộ text UI** — 67 chỗ/30 file, verify lại 2 lần.
- ✅ **2 đợt `/code-review`, 15 finding (1 crash), đã fix hết** — xem danh sách đầy đủ ở `CHANGELOG.md` Session 9. Đáng chú ý nhất: `AutosaveScheduler` rò rỉ task lặp 30s không ai từng `cancel()` (mọi editor đóng lại vẫn âm thầm ghi đè file cũ mãi mãi); Split PDF crash gần 100% lần đầu chọn file (`Stepper` range không hợp lệ lúc `pageCount` chưa fetch xong).
- ⏳ **User yêu cầu "hold" cuối session** — đã dừng agent `/code-review` đợt 3 đang chạy nền (kể cả sub-agent con) qua `TaskStop`, KHÔNG chờ kết quả. Đợt review này chưa xác nhận diff cuối (search field placement fix + tăng size tab bar) sạch. Build (`xcodebuild ... BUILD SUCCEEDED`) đã pass sau mọi đợt sửa trong session — chỉ phần review là dở dang.
- 🚧 **Artifex SDK thật — vẫn đang bị chặn**, không đổi (xem memory `artifex-sdk-integration-blocked`).

**Resume session sau**: khi user báo "okie" → chạy lại `/code-review` (medium) trên diff hiện tại để xác nhận sạch, đặc biệt soát lại đợt fix cuối (search field `.navigationBarDrawer` + size tab bar tăng). Sau đó hỏi user có muốn tiếp tục polish FAB/tab bar tự vẽ (đã mất behavior native "tap-to-pop-root"/"auto-minimize on scroll", có thể cần bù thủ công nếu user muốn) hay chuyển sang mục khác trong roadmap.

---

**Session 6 (2026-09-01) end state:**

- ✅ **Library core loop — code SwiftUI thật xong** (không còn dừng ở mockup): `RootView` bọc `TabView` 3 tab (Library/Tools/Settings, dùng `Tab(...)` API vì deployment target 26.2) — gap "chưa có TabView" ghi ở session 5 đã fix. `LibraryView` viết lại hoàn toàn theo đúng bản mockup `Wireframe/Library-Home-v7.html`: navbar 2 lớp thật (`.navigationTitle` + toolbar, không tự vẽ), icon Filter trần đổi outline→filled + `.badge()` khi active (không nền, đúng HIG), stat-hero card, type-tabs cuộn ngang (enum `DocumentTypeFilter` mới — All/Word/Excel/PowerPoint/PDF), `List` `.insetGrouped` với section "Needs Attention" (due reminders) + section theo `DateBucket` — nối vào đúng `heroCopy`/`dueReminderEntries()`/`groupedEntries()` đã có sẵn trong `LibraryViewModel+Grouping.swift` từ trước nhưng chưa ai gọi tới (dead code, giờ đã dùng). FAB nổi cho Add (tái dùng `AddFileMenu.supportedTypes`). `SettingsView` thêm "Change folder…".
- ✅ **Fix gap 2-source merge** (ghi ở session 5): `LibraryViewModel.loadLibrary()` giờ quét song song cả thư mục cấp quyền lẫn sandbox `Documents/`, merge theo `documentID` (thư mục cấp quyền thắng nếu trùng) — bỏ qua quét lần 2 nếu 2 thư mục trùng nhau (tránh double I/O). `importFiles()` giờ `upsert` ngay vào store, không cần đợi lần load sau.
- ✅ **`/code-review` bắt được 3 vấn đề, sửa 2, báo lại 1**: (1) `count(for:)` badge số trên type-tab không tính `statusFilter` dù docstring nói có — đã sửa khớp lại; (2) `loadLibrary()` quét trùng 2 lần nếu thư mục cấp quyền chính là `Documents/` — đã sửa bằng so sánh đường dẫn; (3) **bug nghiêm trọng có sẵn từ trước, KHÔNG thuộc phần Library đang làm**: `DOCXCodec.write()` đã đúng khi từ chối ghi đè file có bảng/ảnh (throw `.richContentUnsupported`), nhưng `AutosaveScheduler.performSave`/`flush` nuốt âm thầm mọi lỗi (`catch { }` rỗng, comment "Sprint 0.1: swallow") — user sửa file .docx có bảng/ảnh thì tưởng đã lưu nhưng chưa bao giờ ghi xuống đĩa, `isDirty` còn bị `flushIfNeeded()` xoá sai kể cả khi lưu thất bại.
- ✅ **Fix luôn bug #3 trong session này** (user yêu cầu ưu tiên vì rủi ro mất dữ liệu thật): `AutosaveScheduling` protocol thêm `onResult: (AutosaveOutcome) -> Void` báo kết quả mỗi lần lưu (kể cả lúc flush). `EditorViewModel` chỉ tắt `isDirty` khi lưu thật thành công, lưu lỗi thì giữ `isDirty = true` + set `errorMessage`. Thêm mới `ErrorBanner` (trước là file rỗng TODO Sprint 0.5) — hiện banner đỏ trong Editor khi lưu thất bại, có nút tắt.
- ✅ Build sạch nhiều lần (`xcodebuild ... BUILD SUCCEEDED`) sau từng đợt sửa + launch thử trên Simulator (iPhone 17) — xác nhận app chạy, màn hình cấp quyền hiện đúng copy mới. **Chưa xác nhận được bằng mắt màn hình Library thật** (cần cấp quyền 1 thư mục qua system picker — không tự động hoá được vì thiếu quyền Accessibility trên máy dev).
- ✅ **HTML mockup dọn vào 1 chỗ** — tạo folder `Wireframe/` ở gốc repo, gom hết 7 file `.html` (kể cả 2 file cũ đã commit từ trước) vào đó bằng `git mv`/`mv`. Từ giờ tìm mockup thì vào `Wireframe/`, không phải gốc repo.
- ⛔ **PDF Tools View layer — vẫn stub, đang ở bước mockup**: mockup cũ (session 5 nói "đã duyệt bố cục") đã KHÔNG còn trong repo (nằm ở scratchpad phiên cũ, mất). Đã dựng mockup mới `Wireframe/PDFTools-Mockup-v1.html` (Tools home, Merge, Split, Scan & OCR) — giới hạn đúng phạm vi `PDFToolsViewModel`/`OCRViewModel` đã wire (chỉ PDF, chưa DOCX/PPTX merge), màu lấy đúng hex thật từ `Assets.xcassets`. **Đang chờ user duyệt** trước khi viết SwiftUI thật cho `MergeSplitCompressView`/`ScanFlowView`/`OCRPreviewView`/`ToolsTabView`.
- 🔄 **Scope PDF Tools mở rộng (2026-09-01, cùng session)** — user yêu cầu thêm 4 chiều convert: Office (Word/Excel/PPT)→PDF, PDF→Word, PDF→Image, Image→PDF (mục cuối chưa từng ghi ở đâu, bổ sung mới hoàn toàn). Đã cập nhật `Phase0-Implementation-Logic-v2.md` §7.4 (logic + code sketch cho cả 4, tái dùng `exportAs` SDK/`DOCXCodec`/`PDFKit`/`UIGraphicsPDFRenderer` có sẵn — không viết engine mới) + bảng effort. Đang dựng `Wireframe/PDFTools-Mockup-v2.html` (Tools home thiết kế lại + 4 luồng convert mới) theo yêu cầu "đẹp/xịn hơn, chuẩn iOS native hơn" — **cũng đang chờ duyệt cùng đợt với v1**.
- 🔄 **Định nghĩa lại Scan & OCR (2026-09-01, cùng session)** — 2 thay đổi lớn so với bản gốc §6, đã sửa trong `Phase0-Implementation-Logic-v2.md`:
  1. **Input mở rộng từ 1 → 3 nguồn** (§6.1): camera scan (như cũ) + ảnh có sẵn trong Thư viện ảnh (viết tay/đánh máy) + file PDF sẵn có dạng ảnh scan (không có lớp chữ số) — cả 3 quy về chung 1 pipeline OCR, không viết riêng.
  2. **Output đổi ưu tiên** (§6.5): user cần "sửa được" (editable) là chính, không phải chỉ "tìm/copy được" — `.docx` sửa được (tái dùng `DOCXCodec.write`) lên làm output CHÍNH, PDF searchable lùi thành tuỳ chọn phụ (cho chọn cả 2, không ép 1).
  - Kéo theo: **"PDF → Word" (§7.4) phải tự phát hiện PDF có lớp chữ số hay không** (`needsOCR()`) — có thì đọc thẳng `page.string` (rẻ), không có (PDF scan cũ) thì fallback OCR dùng chung engine §6.
  - Mockup v2 đã cập nhật đủ 2 thay đổi này + concept "Native Depth" (icon gradient badge, category header, Scan hero đứng riêng không lồng trong category, Convert gộp 4 ô thành 2 cặp) — **đã được user duyệt**.
- ✅ **Code SwiftUI thật xong toàn bộ PDF Tools (2026-09-01, cùng session)** — theo đúng mockup v2 đã duyệt, chia 2 đợt review theo rule.md #4:
  - **Đợt 1 (Service + ViewModel)**, review bằng `/code-review`, 2 lỗi thật bắt được + sửa: `OCRViewModel.recognize()` thiếu reentrancy guard (có thể crash do `Dictionary(uniqueKeysWithValues:)` trùng key khi gọi 2 lần liên tiếp); `PDFKitTextExtractor.extractText()` quyết định OCR theo cả document thay vì theo từng trang (PDF trộn — vài trang có chữ, 1 trang scan — sẽ mất trắng trang đó).
  - **Đợt 2 (View SwiftUI)**, review bằng `/swiftui-expert-skill`, 4 lỗi thật bắt được + sửa: 4 chỗ dùng `.offset`/index làm `ForEach` id trên list có xoá/kéo-thả (Split ranges, Image→PDF photos, Scan pages, OCR page tabs) — vi phạm hard rule, gây sai animation/identity khi xoá — đổi hết sang wrapper struct `Identifiable`. Cũng tự bắt + sửa 1 lỗi thiếu `import PDFKit` và 2 chỗ compiler timeout ("unable to type-check... in reasonable time") do toolbar/body quá phức tạp — tách thành computed property riêng.
  - File mới: `MockArtifexDocumentExporter`, `PDFKitTextExtractor`, `PDFKitImageExporter`, `UIGraphicsImagePDFExporter`, `CGSearchablePDFRenderer` (+ 4 protocol tương ứng) ở tầng Service; `ToolsTabView`/`MergeSplitCompressView`/`ConvertFlowView`/`ScanFlowView`/`OCRPreviewView`/`DocumentCameraScanner`/`PDFToolsSharedUI`/`PDFToolDestination` ở tầng UI. Mở rộng `PDFToolsViewModel` (4 method convert mới) + `OCRViewModel` (multi-source + export kép) + nối `DependencyContainer`.
  - **CHƯA build/chạy trên Xcode/Simulator** — cần user tự build + test, đặc biệt: (1) `CGSearchablePDFRenderer`'s toạ độ text vô hình (raw CGContext, chưa test thật trên device), (2) `Menu { PhotosPicker(...) }` pattern trong `ScanFlowView`, (3) `EmptyStateView(...action: (tuple literal))` cú pháp tuple chưa compile-verify được.
- 🚧 **Artifex SDK thật — vẫn đang bị chặn** (không đổi so với session 5, xem memory `artifex-sdk-integration-blocked`).
- ⏳ **Chưa làm**: code SwiftUI thật cho PDF Tools (chờ duyệt mockup), Files Provider Extension, View Comment/Signature/Watermark (vẫn stub) — không đổi so với session 5.

**Resume session sau**: nếu user đã duyệt `PDFTools-Mockup-v2.html` (thay v1 — có thêm 4 tool convert) → code thật `ToolsTabView`/`MergeSplitCompressView`/`ScanFlowView`/`OCRPreviewView` + 4 view convert mới nối vào `PDFToolsViewModel`/`OCRViewModel` (mở rộng theo §7.4), review bằng `/code-review` + `/swiftui-expert-skill` theo đúng rule.md #4. Nếu chưa duyệt → hỏi lại feedback trước khi code. Riêng phần Library core loop coi như DONE về mặt logic — còn lại là user tự test bằng cách cấp quyền 1 thư mục thật trên Simulator/device rồi xem lại toàn bộ luồng (due section, date bucket, type-tab filter, status filter, FAB import).

---

**Session 5 (2026-09-01) end state:**

- ✅ **PDF Tools ViewModel layer wired** — `PDFToolsViewModel` (merge/split, có reentrancy guard) + `OCRViewModel` (OCR concurrency-capped ~3 trang, per-page error resilience, confidence tracking) viết mới + đăng ký vào `DependencyContainer` (`makePDFToolsViewModel()`/`makeOCRViewModel()`). Engine phía dưới (`PDFKitMerger`/`PDFKitSplitter`/`VisionTextRecognizer`/`AirPrintCoordinator`) đã có từ trước — session này nối nốt lớp ViewModel giữa engine và View (View vẫn còn stub).
- ✅ **`/code-review` trên đợt diff này bắt được + đã fix 4 bug thật**: OCR mặc định ngôn ngữ hard-code thay vì lấy theo hệ thống; `PDFKitSplitter` ghi đè âm thầm file trùng tên khi split lại; `PDFToolsViewModel.merge()` có race condition nếu bấm 2 lần liên tiếp; logic đặt tên tránh trùng bị lặp lại 3 nơi → gom về `Extensions/FileManager+NonConflictingURL.swift`, `LocalFileServiceImpl`/`DocumentImporter` dùng lại.
- ✅ Build sạch (`xcodebuild ... BUILD SUCCEEDED`) sau mỗi đợt sửa.
- ⛔ **View cho PDF Tools vẫn là stub 4 dòng** — `MergeSplitCompressView`/`ScanFlowView`/`OCRPreviewView`/`ToolsTabView`. Đã có HTML mockup (Tools home, Merge, Split, Scan/OCR) được duyệt về mặt bố cục — chưa viết SwiftUI thật.
- 🚧 **Artifex SDK thật — ĐANG BỊ CHẶN** (xem memory `artifex-sdk-integration-blocked`) — đối tác gửi nhầm PyMuPDF Pro (Python-only), app cần đúng Smart Office SDK (SODK)/MuPDF iOS SDK như 2 đối thủ đang dùng. Chờ user hỏi lại đối tác. Vẫn đang chạy Mock SDK.
- 🚧 **App shell/navigation đã chốt qua chat + mockup, CHƯA code** — `TabView` 3 mục (Library/Tools/Settings, bỏ tab Files), navbar Library có Add (+import) + Filter (Status × Type, AND) kèm chip filter tháo được, bỏ "Rescan folder" (đã có `.refreshable`), "Change folder…" dời sang Settings. Spec đầy đủ + link mockup (2 vòng, bản mới nhất đổi lại copy header "Tủ hồ sơ của bạn") ở memory `app-shell-navigation-decided`. **2 gap thật phát hiện được, phải fix cùng lúc lúc wiring chứ không phải sau**: (1) `RootView` hiện chưa bọc `LibraryView` trong `NavigationStack`/`TabView` nào — toolbar/title hiện không có nơi hiển thị; (2) `LibraryViewModel.loadLibrary()` chỉ quét folder đã cấp quyền, không quét sandbox `Documents/` (nơi `importFiles()` thực sự ghi file vào) — file import xong không hiện trong list nếu không vá 2-source merge.
- ⏳ **Chưa làm trong session này**: toàn bộ code SwiftUI cho mục trên (đang chờ user chốt cuối cùng copy header + navbar), Files Provider Extension (dời lại — chưa có Bundle ID/Team ID thật), View Comment/Signature/Watermark (vẫn stub).

**Resume session sau**: hỏi user chốt copy header "Tủ hồ sơ của bạn" + navbar (đang chờ trả lời), rồi làm 1 đợt: `RootView` → `TabView` 3 tab + `LibraryTabView` mới (theo đúng pattern `FilesTabView`) + navbar Library (Add/Filter/chip) + enum `DocumentTypeFilter` + fix `LibraryViewModel` 2-source merge + `SettingsView` thêm "Change folder…" — xong build + chạy Simulator chụp screenshot cho user duyệt (theo memory `rule-html-mockup-before-swiftui` — hành vi native chrome duyệt ở đó, không phải trên HTML).

---

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
