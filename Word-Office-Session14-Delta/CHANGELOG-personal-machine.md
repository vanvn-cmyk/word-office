# Changelog — Word Office Project

Lịch sử toàn bộ hoạt động, quyết định, và thay đổi trong quá trình phát triển app **Word Office**.

Format tham khảo [Keep a Changelog](https://keepachangelog.com/). Entry mới nhất ở trên cùng.

---

## [Unreleased] — 2026-09-09 (Session 14 — Test target + Settings redesign + Paywall screen + Tools tab icon)

Session bắt đầu bằng setup portable giữa 2 máy (thêm Unit Test target vào Xcode project — trước đó `Word OfficeTests/` chỉ là 4 file `.swift` nằm trên đĩa, chưa gắn vào `project.pbxproj`, không compile/run được). Phần lớn thời gian còn lại là redesign toàn bộ màn Settings qua rất nhiều vòng phản hồi trực quan từ user (chụp màn hình thật trên simulator/device sau mỗi lần sửa), rồi mở rộng sang xây mới màn Paywall và đổi icon tab bar Tools.

### 🧪 Nhóm 1 — Test target setup

- `Word Office.xcodeproj/project.pbxproj` — thêm Unit Test target "Word OfficeTests" qua script Ruby dùng gem `xcodeproj` (an toàn hơn sửa tay `.pbxproj`). Trước đó target này không tồn tại dù 4 file test đã có sẵn trên đĩa.
- Verify: `xcodebuild test` → 36/36 pass (`DocumentLibraryScannerTests`, `FolderBookmarkStoreTests`, `LibraryViewModelTests`, `MetadataStoreImplTests`).

### 🎨 Nhóm 2 — Settings screen redesign (nhiều vòng lặp)

- **Banner đầu trang**: từ "app info" (icon+tên+version) đổi hẳn sang **Premium upsell banner** dùng ảnh raster user tự generate ("Your Office, Upgraded" + "Explore Premium" CTA baked sẵn trong ảnh).
  - Bản đầu AI-generate KHÔNG có alpha thật — checkerboard giả vẽ chết vào pixel RGB (`sips -g hasAlpha` → `no`, dù nhìn preview tưởng trong suốt). Bản thay thế (v2) mới có alpha thật.
  - `Assets.xcassets/SettingsPremiumBanner.imageset` — cropped tight vào bbox thật; phát hiện + sửa 1 lần crop sai do bị 1 điểm highlight cyan ở viền đánh lừa phép đo bbox.
  - Banner full-bleed gần hết chiều rộng, `contentMode: .fit` (không crop nội dung ảnh), shadow 2 lớp dùng đúng công thức có sẵn `ToolsTabView.toolCardSurface` (tight+soft, đen, tăng opacity dark mode) thay vì bịa hiệu ứng glow màu mới.
- **Icon row** (Change folder / Theme / Share app / Rate app / Privacy Policy / Terms of Service):
  - Bản đầu style sai — nền đặc + icon trắng kiểu app Settings gốc Apple, không khớp design system RIÊNG của project (đã có sẵn 2 công thức: `DSDocumentTypeBadge` + `ToolsTabView.IconBadge`, đều dùng nền tint mờ opacity 12-18% + icon cùng màu đó). Fix lại đúng công thức có sẵn.
  - Gold cho "Rate app" ban đầu dùng `dsPremiumGoldStart` (vàng sáng) → vỡ contrast (nền tint quá gần độ sáng icon, nhìn dính thành khối mờ). Đổi `dsPremiumGoldEnd` (cam đậm hơn) — khớp đúng bài học app đã tự rút ra trước đó ở `LibraryView.premiumButton` (Session 13).
  - "Privacy Policy" icon đổi từ `lock.fill` (tự chọn, không tiền lệ) sang `lock.shield.fill` — khớp icon `FolderPermissionOnboarding` đã dùng sẵn cho đúng ngữ cảnh "riêng tư".
  - Cả 4 row trong "General" ép `foregroundStyle(Color.dsTextPrimary)` cho chữ — tránh lệch màu tự động accent-blue mà Button/ShareLink/Link tự áp trong Form.
  - Gộp Privacy Policy + Terms of Service vào chung section "General" (bỏ section "Legal" riêng) — 2 lần đổi ý qua lại từ user trước khi chốt bản cuối.
- **Rating dialog** (`Views/Settings/RatingDialogView.swift` — file mới):
  - **Fix HIG violation thật**: bản đầu chỉ gọi `requestReview()` khi rating ≥ 4 — đúng pattern "review gating" mà Apple HIG (Ratings and Reviews) khuyến cáo không làm (chỉ hỏi review từ user đã lộ hài lòng). Fix: gọi `requestReview()` cho MỌI rating, sao picker không còn quyết định ai được hỏi.
  - Sao đổi từ `.onTapGesture` sang `Button` thật (trước đó mất free VoiceOver/focus handling), thêm `.frame(44,44)` (dưới chuẩn touch-target HIG), `@ScaledMetric` cho icon size (Dynamic Type).
  - **Bug thật tự gây ra rồi tự fix**: thử tự đo chiều cao sheet bằng `GeometryReader` đọc lại CHÍNH view đang bị `.presentationDetents` điều khiển bởi số đo đó → vòng lặp phản hồi, sheet co sập gần bằng 0 (bug thấy rõ qua screenshot user gửi). Revert về cách đơn giản/đáng tin cậy: `Spacer` cố định + hằng số `.height(340)`.
  - Mặc định rating = 5 sao (thay vì 0, Submit sáng ngay), icon header đổi tim → sao (khớp icon "Rate app" ở Settings).
- **Spacing fixes rải rác**: `.listSectionSpacing(.compact)` (khoảng cách giữa section), `.contentMargins(.top, ...)` (khoảng cách title→banner) — 2 API hiện đại thay vì đoán padding tuỳ ý.

### 💳 Nhóm 3 — Paywall screen (mới, CHƯA xong)

- `Views/Paywall/PaywallView.swift` — full màn paywall theo mockup user tự generate: hero gradient + illustration, headline "Your Office, Upgraded", feature grid 2×2 (Edit Office Files/PDF Tools/Scan & OCR/Sign Documents), plan picker Weekly/Yearly (Yearly có badge "BEST VALUE"), nút Continue, footer Terms · Privacy · Restore Purchases.
- Gradient hero vẽ NATIVE bằng SwiftUI (không dùng ảnh nền raster) — 2 màu lấy mẫu trực tiếp (`sips`/PIL) từ chính `SettingsPremiumBanner.png` đã duyệt, không bịa màu mới, để 2 màn "premium" đồng bộ ngôn ngữ hình ảnh. Glow radial + fade-to-white ở đáy hero cũng phải chỉnh lại nhiều lần (glow `.screen` blend 0.9 opacity ban đầu tẩy trắng cả nền → hạ xuống 0.35 opacity thường; fade bắt đầu từ 60% chiều cao ăn quá nhiều diện tích → dời xuống 80%).
- `Assets.xcassets/PaywallHeroIllustration.imageset` — cùng lớp bug checkerboard-giả-alpha như banner Settings. Lần này xử lý bằng script Python tự detect đúng pattern caro (2 tông xám cố định trong dải sáng cụ thể, lọc theo saturation thấp) rồi convert thật ra alpha=0, verify bằng cách composite thử lên nền magenta để phân biệt vùng trong suốt thật với phần ảnh giữ lại.
- **Theo đúng yêu cầu user, CHƯA wire thật**: chọn gói chỉ là `@State` cục bộ (`enum Plan`), không hiển thị giá (mockup gốc cũng không có), Continue/Restore/Terms/Privacy đều `TODO(paywall)` placeholder — nhất quán với cách `LibraryView.premiumButton` đã để trống từ Session 13.
- Đã nối 2 điểm entry vào paywall: `LibraryView.premiumButton` (crown ở toolbar) và `SettingsView`'s premium banner — cả 2 đều mở `PaywallView` qua `.sheet`.
- ⚠️ **CHƯA XONG — session bị ngắt giữa chừng đang sửa**: hero illustration để lại 1 khoảng trống phẳng (dead space) giữa icon minh hoạ và vùng fade-trắng phía dưới, do ảnh neo top (padding cố định) thay vì tự canh giữa khoảng trống hero còn lại. Đang định chuyển sang `VStack` + `Spacer` 2 đầu để tự động canh giữa thì user chuyển hướng sang task icon Tools tab. **Resume tại đây trước tiên ở session sau.**

### 🔧 Nhóm 4 — Tools tab icon

- Thử icon custom (`IconOfficeSupplies.imageset`, PNG line-art template do user generate — pen holder + giấy + kẹp giấy) cho card "Fill Form" trong Tools tab — thêm cờ `isCustomAsset` vào `IconBadge`/`ToolCard` để hỗ trợ ảnh custom bên cạnh SF Symbol.
- User chỉnh hướng: ý thật là muốn đổi icon **tab bar** "Tools" (`RootView.tabBarButton`), không phải card Fill Form. Revert Fill Form về `square.and.pencil` cũ, dọn sạch cờ `isCustomAsset` thừa ở `IconBadge`/`ToolCard` (không còn chỗ dùng).
- Đổi thật ở tab bar: thêm cờ `isCustomAsset` riêng cho `tabBarButton` (trước chỉ nhận SF Symbol `wrench.and.screwdriver` xám, không có variant filled/outline để so sánh khi custom nên giữ nguyên 1 icon bất kể selected state, dựa vào màu + nền capsule để thể hiện selection).
- Thử 2 icon: `IconOfficeSupplies` rồi `IconPencilCase` (64×64px nguồn, hơi thấp res cho chuẩn @3x nhưng chấp nhận được ở size hiển thị 24pt) — **`IconPencilCase` đang là bản active, user CHƯA xác nhận chốt cuối cùng** (mới nói "thử xem sao").

### Build & Test state

- Build sạch (`xcodebuild ... BUILD SUCCEEDED`) sau mọi thay đổi, kiểm tra lại nhiều lần trong session.
- `xcodebuild test` → 36/36 pass xuyên suốt (không có test case mới cho Paywall/RatingDialog — thuần UI, chưa viết unit test).
- SwiftLint sạch trên mọi file đụng tới.
- Test bằng mắt: dựa hoàn toàn vào screenshot user tự chụp trên simulator/device sau mỗi vòng sửa (máy dev vẫn thiếu quyền Accessibility để tự động hoá tap-through onboarding, biết từ Session 6/13) — CHƯA tự click-through full flow Paywall (Continue/Restore/dismiss) lần nào.

### Trạng thái cuối session — vẫn UNCOMMITTED

Cộng dồn từ Session 10 chiều → 13 (chưa commit từ trước) + toàn bộ Nhóm 1-4 session này.

**Còn tồn lại cho session sau:**

1. **Ưu tiên trước hết** — fix nốt dead-space gap ở Paywall hero illustration (xem Nhóm 3).
2. Chốt icon tab bar Tools cuối cùng (`IconPencilCase` vs `IconOfficeSupplies` vs giữ nguyên SF Symbol cũ `wrench.and.screwdriver`).
3. Paywall chưa có StoreKit product thật/giá — chờ user quyết khi nào làm tiếp ("gói cứ để thế đã" — quyết định có chủ đích, không phải quên).
4. `privacyPolicyURL`/`termsOfServiceURL` vẫn `nil` ở CẢ `SettingsView` và `PaywallView` (2 hằng số riêng biệt, chưa share 1 nguồn chung) — chờ user gửi link thật rồi wire cả 2 chỗ.
5. Paywall "Restore Purchases"/"Restore" (top-left) chưa wire `AppStore.sync()` (StoreKit 2) — còn TODO.
6. Toàn bộ 6 finding hoãn từ Session 13 vẫn y nguyên, chưa động tới (xem `GUIDELINE.md` Session 13 block).

### 🔨 Code Deliverables — Session 14

**NEW**: `Views/Settings/RatingDialogView.swift`, `Views/Paywall/PaywallView.swift`, `Assets.xcassets/SettingsPremiumBanner.imageset`, `Assets.xcassets/PaywallHeroIllustration.imageset`, `Assets.xcassets/IconOfficeSupplies.imageset` (hiện không dùng, giữ lại phòng cần), `Assets.xcassets/IconPencilCase.imageset` (đang active ở tab bar).

**EDITED**: `Word Office.xcodeproj/project.pbxproj` (Unit Test target), `Views/Settings/SettingsView.swift`, `Views/Library/LibraryView.swift` (wire paywall sheet), `Views/Root/RootView.swift` (tab bar icon custom-asset support), `Views/Tabs/ToolsTabView.swift` (thử rồi revert Fill Form icon, dọn code thừa).

---

## [Unreleased] — 2026-09-05 (Session 13 — Code-review backlog cleanup + Premium crown icon)

Session tập trung dọn nợ review: Session 12 kết thúc với 1 đợt `/code-review` chưa chạy hết + nhiều bug thật chưa fix. Lần lượt chạy 4 vòng `/code-review medium` trên toàn bộ diff Session 10-12 (không chỉ diff riêng session này) — mỗi vòng verify đợt fix trước sạch, nhưng vì scope là TOÀN BỘ project nên liên tục phát hiện thêm finding pre-existing mới. Đã fix 3 đợt (21 finding), đợt thứ 4 (8 finding) nhận nhưng dừng lại để hỏi ý user thay vì tự ý tiếp tục — xem "Trạng thái cuối session".

### 🟢 Nhóm 1 — Backlog Session 10 (6 finding, fix hết)

- `DSToastPresenter.Item` — bỏ `Equatable` giả (id là `UUID()` random mỗi lần tạo nên `==` luôn `false`, dead code gây hiểu lầm).
- 3× `@MainActor` thừa (`EditorViewModel.handleAutosaveOutcome`, `RootView.initializeViewModelsIfNeeded`, `Word_OfficeApp.handleScenePhaseChange`) — type đã `@MainActor`/View/App rồi.
- `ToolResultGalleryView`'s `ShareLink` thêm `preview:` (`SharePreview(Text(url.lastPathComponent))`) — trước đó share file mới tạo (chưa Spotlight-index) hiện icon chung/"N Items".
- `DocumentPickerExporter` double-dismiss trên iPad — picker tự bubble dismiss lên sheet cha (do `presentingViewController` đi qua containment chain), cộng thêm code cũ CŨNG tự gọi `onDismiss()` → 2 animation dismiss chồng nhau. Fix: bỏ hẳn coordinator/delegate, đổi 2 call site (`LibraryView`, `ToolResultGalleryView`) sang `.sheet(item:onDismiss:)`/`.sheet(isPresented:onDismiss:)` — để duy nhất SwiftUI chịu trách nhiệm dismiss.
- `ScanFlowView.loadPhotos` — `try?` nuốt lỗi khi 1 ảnh trong Photos picker load fail (iCloud chưa tải/format lạ) → mất ảnh âm thầm. Fix: đếm `failedCount`, báo qua `errorMessage`.

### 🟡 Nhóm 2 — Đợt review thứ 2, full-project scan (8 finding, fix hết)

- **[HIGH] `RootView.swift`** — `TabBarVisualHiddenPreferenceKey` reduce bằng `||` trên cả 3 tab mount song song → 1 destination ẩn tab bar ở tab KHÔNG active vẫn ẩn tab bar app-wide tới khi quay lại pop ra. Fix: `suppressTabBarHiddenPreference(unless:)` mới trong `View+HidesTabBar.swift`, `transformPreference` zero-out contribution của tab không active.
- `SignaturePlacementView.swift` + `FillFormView.swift` — rect đặt chữ ký/text tap gần mép không clamp vào mediaBox → crop âm thầm khi lưu. Fix: `PDFPage+ClampedRect.swift` mới (`clampedToMediaBox`), áp dụng 4 chỗ (tap + drag, cả 2 file).
- `DocumentCard.swift` — regression thật: `.sensoryFeedback(.selection, trigger: isFavourite)` bị mất khi gộp nút Favourite vào kebab menu `FileActionsMenu`. Fix: thêm lại.
- `SignFlowView.swift` / `FillFormView.swift` — `commitSave` gọi `previewPayload = nil` + `dismiss()` cùng lúc → double-dismiss race (sheet đóng + NavigationStack pop chồng animation). Fix: `shouldDismissAfterPreviewCloses` flag, pop chuyển vào `.sheet(onDismiss:)` — chỉ chạy SAU KHI sheet đóng xong hẳn.
- `DSToastPresenter.swift` — vi phạm `~/CLAUDE.md` Toast Notifications: mọi style auto-dismiss 3s cứng thay vì success=4s/error=persistent/info=6s. Fix: `Style.defaultAutoDismissDuration`. Phần "queue tối đa 3 thay vì replace" — **giữ nguyên hành vi cũ theo quyết định user** (đã hỏi lại, xác nhận replace là chủ đích để tránh toast cũ kẹt khi batch nhiều thao tác).
- Dedupe `PDFView` wrapper — `PDFPreviewPane` (`EditorPlaceholderView`) và `PreviewPDFPane` (`PreviewConfirmSheet`) giống hệt nhau byte-for-byte, gộp về `Views/Common/ReadOnlyPDFPreviewPane.swift` mới. 2 wrapper tap-interactive (`SignPDFView`/`FillFormPDFView`) giữ riêng vì khác nhau thật (currentPageIndex tracking).
- `FillFormViewModel.commitPreview` — doc comment nói sai ("staged file left in place để retry") trong khi code xoá ngay khi fail. Sửa comment khớp code.

### 🟠 Nhóm 3 — Premium crown icon (redesign theo yêu cầu user)

- `LibraryView.premiumButton`: `Image(systemName: "sparkles")` → badge tròn gradient `crown.fill` + ring highlight top + shadow màu theo tint.
- **Vòng 1 dùng `Color.dsStatusWarning`** — user chụp screenshot phản hồi "có phải chuẩn Apple design system không" vì màu ra nâu/đồng (`dsStatusWarning` = `#A75D00` thật, màu "warning" cho status draft, không phải gold).
- **Vòng 2 sửa đúng**: 2 token mới `dsPremiumGoldStart`/`dsPremiumGoldEnd` (2 colorset mới trong `Assets.xcassets`) lấy đúng hex hệ thống của Apple — `systemYellow`/`systemOrange` (light `FFCC00`→`FF9500`, dark `FFD60A`→`FF9F0A`) — cặp màu Apple dùng cho badge premium/subscription (News+, Podcasts).

### 🔵 Nhóm 4 — Đợt review thứ 3 (8 finding, fix hết)

- `SignFlowView`/`FillFormView.commitSave` — khi `commitPreview()` fail (disk full...), code cũ chỉ `return` mà không đóng `previewPayload` → sheet kẹt vĩnh viễn, `.errorAlert` nằm dưới sheet không hiện được. Fix: đóng sheet (không pop nav, không reset VM) để user thấy lỗi + retry được.
- `PDFKitSignatureStamper.swift` — chữ ký lưu ra PDF bị stretch méo so với preview (preview aspect-fit trong rect, code stamp cũ `context.draw(cgImage, in: pageRect)` luôn stretch-to-fill). Fix: `aspectFitRect(imageSize:in:)` helper, tính sub-rect đúng tỉ lệ trước khi draw.
- `MergeSplitCompressView.swift` (Merge + Split) + `ConvertFlowView.swift` — bấm nút hành động 2 lần trên CÙNG 1 selection chưa đổi → tạo file trùng "(2).pdf" âm thầm (file list/ranges/images cố ý giữ lại sau thành công để re-run với input mới — không thể disable cứng). Fix: snapshot input tại thời điểm thành công cuối (`lastMergedSnapshot`/`lastSplitSnapshot`/`ConvertSnapshot`), disable nút chỉ khi input CHƯA đổi so với snapshot đó.
- `ScanFlowView.swift` — mở từ FAB Library (`onOpenFile`/`onShowGallery` đều nil, khác Tools-tab push) → sau save sheet kẹt lại, Save vẫn bấm được lần 2. Fix: `dismiss()` khi cả 2 callback đều nil.
- `SignFlowView.swift`/`FillFormView.swift` — `signatureVM`/`fillFormVM` sống suốt vòng đời Tools tab (tạo 1 lần), back giữa chừng không save thì không reset → mở lại dính state cũ. Fix: `.onDisappear { viewModel.reset() }`.
- `PrintFlowView.swift` + `MergeView`/`SplitView`/`ConvertFlowView.swift` — dùng chung 1 `pdfToolsVM`, lỗi cũ từ tool A còn sót trong `errorMessage` hiện nhầm sang tool B khi chuyển tab. Fix: `.onAppear { viewModel.errorMessage = nil }` ở cả 4 view.
- `SignFlowView.SignatureDrawSheet` — nút "Clear" xoá chữ ký đang vẽ ngay lập tức, không confirm, không undo — vi phạm rule destructive-action trong `~/CLAUDE.md`. Fix: `.confirmationDialog`.
- 4 magic number tách rời cho khoảng chừa tab bar (`RootView` 150, `ToolsTabView` 100, `LibraryView`/`SettingsView` 80) không có nguồn chung. Fix: `DesignSystem/Foundations/DSTabBarMetrics.swift` mới gom cả 4 (giữ nguyên giá trị — mỗi cái tune riêng cho loại content khác nhau, chỉ gom thành hằng số có tên).

### 🟣 Nhóm 5 — Đợt review thứ 4 (8 finding): 2 fix, 6 hoãn có lý do

Không tự động fix tiếp cả 8 — dừng lại trình bày lý do cho từng cái trước, vì bắt đầu lấn sang finding cần verify thật (không đọc code suông đoán được) hoặc là quyết định kiến trúc/UX chứ không phải bug cơ học. User xác nhận cách tiếp cận, chỉ 2 cái được fix:

- ✅ **`PDFToolsViewModel.print()` thiếu `isProcessing` guard** — Print giờ share `pdfToolsVM` với Merge/Split/Convert (ghép từ Session 12), thiếu guard này thì lỗi/trạng thái xử lý của Print có thể ghi đè/bị ghi đè bởi 1 trong 3 tool kia nếu chạy chồng lúc chuyển tab. Fix: thêm guard giống hệt 5 method còn lại.
- ✅ **Animation/spring chưa gate `accessibilityReduceMotion`** — 7 tool card + Scan hero (`PressableCardButtonStyle`), tab-bar slide + FAB menu open/close (`RootView`, `LibraryAddButton`), 3 chỗ toast show/dismiss (`DSToastPresenter`, dùng `UIAccessibility.isReduceMotionEnabled` vì class này không phải View, không có `@Environment`). Fix: `withAnimation(reduceMotion ? nil : ...)` / `.animation(reduceMotion ? nil : ..., value:)` ở tất cả các chỗ trên.
- ⏸️ **4 cái hoãn vì cần verify thật, không đoán được từ code**: (1) nghi vấn `TabBarVisualHiddenPreferenceKey` có thể vẫn stuck — suy đoán theo tương tự bug cũ, nhưng cơ chế `PreferenceKey` của SwiftUI tính lại theo cây view mỗi render (không phải kiểu event có thể miss), nhiều khả năng KHÔNG phải bug thật, cần test tay mới chắc; (2)+(3) rotation chưa xử lý ở Sign/Fill Form placement — cả tap-placement lẫn PDF write đều dùng API cấp cao PDFKit (`pdfView.convert`, `page.draw`) vốn tự xử lý rotation nhất quán với nhau, nhiều khả năng code hiện tại đã đúng, cần test trên 1 file PDF scan bị xoay thật mới biết chắc.
- ⏸️ **2 cái hoãn vì là quyết định UX/kiến trúc, không phải bug cơ học**: nút "Print" mất sau khi Merge (tính năng bị rớt khi refactor, cần chốt lại luồng trước khi code theo rule.md #2) và Library full-rescan mỗi lần save (đọc code thấy đây là quyết định có chủ đích từ Session 12 — comment ghi rõ lý do lấy đúng metadata/iCloud state — đổi sang upsert là đánh đổi hiệu năng vs độ chính xác, cần user quyết chứ không tự tiện đổi).

**Gap nhỏ phát hiện thêm khi review scope hẹp đúng 2 fix trên (agent bị dừng giữa chừng theo yêu cầu user, nhưng đã kịp trả về finding)**: guard `isProcessing` mới thêm cho `print()` chặn đúng race, nhưng `PrintFlowView`'s nút Print chỉ `.disabled(sourceURL == nil)`, không tham chiếu `viewModel.isProcessing` — nếu guard thật sự chặn (Merge đang chạy), user bấm Print sẽ thấy nút nhấp nháy mà không có gì xảy ra, không toast/spinner/lỗi báo. Ghi nhận, chưa fix — để dồn cùng đợt sau nếu cần.

### Build & Review state

- Build sạch (`xcodebuild ... BUILD SUCCEEDED`) sau mỗi đợt fix, kể cả đợt Nhóm 5.
- 4 vòng `/code-review medium` scope toàn project (3 đợt đầu, 21 finding, fix hết) + 1 vòng scope hẹp đúng 5 file Nhóm 5 (dừng theo yêu cầu user giữa chừng, đã kịp trả 5 finding — 1 finding thật liên quan trực tiếp fix vừa làm (note ở trên), 4 finding còn lại là duplication/design-taste pre-existing từ Session 12, không phải regression từ session này).
- **Chưa test bằng mắt trên simulator** cho toàn bộ session — cài lại app xoá state onboarding (chưa cấp quyền thư mục), không tự động hoá được tap "Skip for now" (thiếu quyền Accessibility trên máy dev, biết từ Session 6). User cần tự bấm qua onboarding rồi test thủ công.

### Trạng thái cuối session — vẫn UNCOMMITTED

Cộng dồn với Session 10 chiều / 11 / 12 (chưa commit từ trước) + toàn bộ Nhóm 1-5 session này — vẫn giữ nguyên "tạm để local, commit sau" theo yêu cầu user đầu Session 12.

**Còn tồn lại cho session sau** (không phải bug khẩn — xem lý do chi tiết ở Nhóm 5): 4 mục cần verify thật trên simulator/device trước khi quyết fix hay không (tab-bar preference stuck nghi vấn, rotation Sign/Fill Form nghi vấn), 2 mục cần user chốt hướng trước khi code (Print shortcut sau Merge, Library rescan-vs-upsert), 1 gap nhỏ mới phát hiện (`PrintFlowView` nút Print không phản ánh `isProcessing`), và 4 finding duplication/design-taste pre-existing (2 cặp code trùng nhau gần như y hệt — `LibraryEditorSheet`/`ToolsEditorSheet`, `RootView.closeFABMenu`/`LibraryAddButton.closeMenu` — + `IconBadge` trùng ý tưởng với `DSDocumentTypeBadge` có sẵn + `PressableCardButtonStyle` dùng `.interactiveSpring` vốn vi phạm thẳng rule "no spring physics for UI chrome" trong `~/CLAUDE.md`, không chỉ vấn đề reduce-motion).

### 🔨 Code Deliverables — Session 13

**NEW** (5): `Extensions/PDFPage+ClampedRect.swift`, `Views/Common/ReadOnlyPDFPreviewPane.swift`, `DesignSystem/Foundations/DSTabBarMetrics.swift`, `Assets.xcassets/PremiumGoldStart.colorset`, `Assets.xcassets/PremiumGoldEnd.colorset`.

**EDITED** (~22): `DesignSystem/Components/Feedback/DSToastPresenter.swift`, `DesignSystem/Foundations/DSColor.swift`, `ViewModels/EditorViewModel.swift`, `Views/Root/RootView.swift`, `App/Word_OfficeApp.swift`, `Views/PDFTools/ToolResultGalleryView.swift`, `Views/Common/DocumentPickerExporter.swift`, `Views/Library/LibraryView.swift`, `Views/Library/LibraryAddButton.swift`, `Views/OCR/ScanFlowView.swift`, `Extensions/View+HidesTabBar.swift`, `Views/Signature/SignaturePlacementView.swift`, `Views/PDFTools/FillFormView.swift`, `Views/Library/DocumentCard.swift`, `Views/PDFTools/SignFlowView.swift`, `Views/PDFTools/PreviewConfirmSheet.swift`, `Views/Editor/EditorPlaceholderView.swift`, `ViewModels/FillFormViewModel.swift`, `ViewModels/PDFToolsViewModel.swift`, `Services/Implementations/Native/PDFKitSignatureStamper.swift`, `Views/PDFTools/MergeSplitCompressView.swift`, `Views/PDFTools/ConvertFlowView.swift`, `Views/PDFTools/PrintFlowView.swift`, `Views/Tabs/ToolsTabView.swift`, `Views/Settings/SettingsView.swift`.

---

## [Unreleased] — 2026-09-04 (Session 12 — Fill & Sign category + Tools redesign)

Session dài nhất từ đầu project. Bắt đầu từ 1 user request nhỏ ("thêm Compress?" — user hủy sau khi tôi flag scope reverse) rồi mở rộng thành: (1) full Fill & Sign category với 3 features (Print + Sign Tier 1 + Fill Form), (2) redesign Tools home thành 2-col card grid, (3) upgrade tab bar Liquid Glass native iOS 26, (4) auto-hide tab bar on scroll, (5) preview + confirm flow trước khi save. Loop 5-6 vòng iterations về spacing dưới do 1 bug root cause bị mãi không tìm ra tới khi `/code-review` chỉ ra ở cuối session.

### 🔴 Nhóm 1 — Fill & Sign category (3 features)

**Trigger**: user hủy Compress ("effect chưa lớn"), yêu cầu "để ở ngoài tính năng print, sign & fill form, gom vào 1 category". Category name chốt **"Fill & Sign"** (Adobe pattern). Mockup `Wireframe/FillAndSign-Mockup-v1.html` — 4 lane (Tools entry + Print + Sign + Fill Form).

- ✅ **Print** — reuse `AirPrintCoordinator` backend Session 6 (`PDFToolsViewModel.print()`). Chỉ thiếu UI entry. NEW `PrintFlowView.swift` giống MergeView pattern (fileImporter PDF + toolbar Print → system AirPrint sheet). **Không toast** post-save (backend collapses cancel/success into same code path — nói dối user nếu cancel).
- ✅ **Sign Tier 1 (drawing)** — spec §9.1 "làm trước". 6 file replace stub:
  - `Models/Signature.swift` (real: `id, imageData: Data, createdAt`)
  - `Services/Protocols/Signature/SignatureStamping.swift` (NEW)
  - `Services/Implementations/Native/PDFKitSignatureStamper.swift` (NEW) — CGPDFContext re-render approach (KHÔNG PDFAnnotation stamp — subclass appearance stream không persist qua Preview/Acrobat)
  - `ViewModels/SignatureViewModel.swift` (real, 2-stage: pickPDF → fill với tap-to-place + bottom sheet canvas)
  - `Views/Signature/SignatureCanvasView.swift` (PKCanvasView UIViewRepresentable)
  - `Views/Signature/SignaturePlacementView.swift` (SignPDFView + SignPDFCanvas với tap-place + drag reposition)
  - `Views/PDFTools/SignFlowView.swift` NEW orchestrator + `SignatureDrawSheet` bottom sheet canvas
- ✅ **Fill Form (Option B — free-text overlay, Adobe Fill & Sign pattern)** — không có trong spec Phase0-v2, user request mới. 5 file new:
  - `Models/FormFill.swift` (`TextAnnotation: id, pageIndex, pageRect: var, text, fontSize`)
  - `Services/Protocols/Form/FormFilling.swift` (NEW)
  - `Services/Implementations/Native/PDFKitFormFiller.swift` — `PDFAnnotation.freeText` + `PDFDocument.write` (persists reliably vì PDFKit tự sinh appearance stream cho freeText)
  - `ViewModels/FillFormViewModel.swift`
  - `Views/PDFTools/FillFormView.swift` (FillFormPDFView + FillFormPDFCanvas + TextAnnotationOverlay với drag + long-press remove + FillFormTextEditor sheet)
- ✅ **Print scope**: PDF only cho MVP (Office → Convert → then Print). Sign scope: Tier 1 only (Tier 2 PKI cert Phase 2 per spec).
- ✅ **Sign flow refactor** (Session 12 giữa) — user feedback: "flow nên chọn vị trí rồi thực hiện bottom sheet chữ ký thì phù hợp hơn". Refactor từ 3-stage (canvas → placement) sang 2-stage (tap-position-first → sheet canvas), match Fill Form + Adobe pattern.
- ✅ **Drag gesture** cho Sign signature + Fill Form text annotation — user request "muốn di chuyển chữ ký/text". `.highPriorityGesture(DragGesture)` để không bị PDFView pan cướp; `@GestureState` per-annotation (extract subview để state isolation).

### 🟢 Nhóm 2 — Preview + confirm flow (before save)

**Trigger**: user feedback "nên cho user preview lại rồi confirm 1 lần nữa, sau đó mới hiển thị toast". Two-phase pattern:

- `stagePreview()` — ghi vào `FileManager.default.temporaryDirectory`
- `commitPreview(_ url: URL)` — move file temp → Documents/, post notification
- `discardPreview(_ url: URL)` — cleanup temp

NEW `Views/PDFTools/PreviewConfirmSheet.swift` (shared cho Sign + Fill Form) — bottom sheet `.large` detent với PDFPreviewPane + Back / "Save to Home" toolbar buttons.

### 🟦 Nhóm 3 — Auto-refresh Library sau tool save

**Trigger**: user "sau khi save file thì phải lưu lại file cũ trong app chứ nhỉ" — user không biết file đi đâu.

- NEW `Extensions/Notification+DocumentsChanged.swift` — `Notification.Name.documentsDidChange`
- Post từ 9 tool save actions: FillForm, Sign, Merge, Split, Convert (4 direction), Scan (2 exports)
- `LibraryViewModel` subscribe qua `addObserver` trong init, cleanup deinit (`nonisolated(unsafe)` observer property vì deinit của MainActor class không thể await)
- Kết quả: file save từ Tools tab → Library tab auto-appear, không cần pull-to-refresh

### 🟨 Nhóm 4 — Tools home 2-col card grid refactor

**Trigger**: user "tôi muốn gom Organize + Fill & Sign giống Convert, nhưng Convert chuyển hết thành dạng card, spacing 2 card". Rewrite ToolsTabView với unified card grid.

Files: 1 file rewrite `Views/Tabs/ToolsTabView.swift` (~450 lines)

Components mới (all private, fileprivate scope):
- `ToolCard` — single icon variant (Merge/Split/Fill Form/Sign/Print)
- `ConvertToolCard` — 2-icon + arrow variant (4 Convert directions)
- `IconBadge` — shared, gradient fill 18%→10% + top-only white highlight rim (dimensional feel, không flat)
- `PressableCardButtonStyle` — scale 0.96 + brightness -0.03 + `sensoryFeedback(.selection)` closure filter `{ _, new in new }` (one-shot on press-down)
- `ToolCardSurface` ViewModifier — shared card shell: layered shadow (tight 2pt + soft 12pt), subtle gradient fill top→bottom, hairline border (0.5pt subtle), radius 16pt, minHeight 120pt

`LazyVGrid` 2 cols × 12pt gap, shared `gridColumns` spec. Fill & Sign 3 items → LazyVGrid natural: 2 top row + 1 bottom-left (bottom-right empty cell — reads OK).

Section header refactor: brand-tinted rounded-square icon 22pt + title (giữa) + count pill (**sau đó user yêu cầu bỏ số 2/3/4**).

### 🟣 Nhóm 5 — Liquid Glass tab bar upgrade (iOS 26 native pattern)

**Trigger**: user "navbar chưa chuẩn nhiều native ios design nhỉ, có liquid glass". Consult `swiftui-expert-skill/references/liquid-glass.md`.

- **Wrap customTabBar trong `GlassEffectContainer(spacing:)`** — per skill: "Glass cannot sample other glass. Container gives grouped elements a shared sampling region." Pill + FAB giờ sample cùng region, glass tone nhất quán.
- **Tab pill button**: size 76×60 (từ 72×56), icon `.symbolVariant(isSelected ? .fill : .none)` — native pattern (Files, Notes), thêm `.sensoryFeedback(.selection)` khi đổi tab.
- **FAB (LibraryAddButton)**: replace gradient Circle → `.glassEffect(.regular.tint(Color.dsBrandPrimary).interactive(), in: .circle)`. Interactive glass = built-in press dip (native iOS 26). Diameter 56→60pt. Giữ shadow brand halo mỏng.
- **Prominent inline title** (`View+ProminentInlineTitle.swift` NEW modifier):
  - Replace `.navigationTitle(...).navigationBarTitleDisplayMode(...)` cross-app
  - `.navigationBarTitleDisplayMode(.inline)` + `.toolbar { .principal { Text.font(.title2.bold()) } }` — 22pt bold nav bar title, KHÔNG collapse trên scroll (user "khi scroll text bé quá, tăng size lên bằng size tool ở gốc")
  - Apply cho 7 tool screens (Tools home, Merge, Split, Convert 4 dirs, Scan, Sign, Fill Form, Print) + Settings
  - Support cả `LocalizedStringKey` + `String` overloads (ConvertDirection.title/ScanFlowView.navigationTitle là String)

### 🟠 Nhóm 6 — Auto-hide tab bar on scroll

**Trigger**: user "khi scroll thì sẽ ẩn navbar, dừng lại thì hiển thị". Safari/Notes pattern.

NEW `Extensions/View+AutoHideTabBarOnScroll.swift`:
- `.onScrollGeometryChange(for: CGFloat.self)` (iOS 18+) — track offset delta
- Debounce Task 350ms — sau 350ms no-offset-change → mark idle
- Publish qua `TabBarVisualHiddenPreferenceKey`
- Cleanup: cancel Task on `.onDisappear`

Apply cho 3 tab home (Tools/Library/Settings scroll containers).

### 🔵 Nhóm 7 — Editor auto-shows real PDF (không placeholder)

**Trigger**: user "editor mở ra chỉ hiện placeholder 'coming when SDK licensed', không thấy file". Fix: `EditorPlaceholderView.swift` thêm case `.pdf` dùng `PDFPreviewPane` (PDFKit native UIViewRepresentable) — sidesteps Artifex SDK block cho PDF. Tool outputs (mọi tool sinh PDF) auto-mở editor showing real PDF now.

### 🟩 Nhóm 8 — UX iteration: nav destination flow

**Trigger**: user "đối với Fill & Sign sau khi edit xong hiển thị toast, đưa về màn hình tool và báo thêm toast là đã lưu ở Home".

- Bỏ auto-navigate editor sheet sau save Fill/Sign
- Add `@Environment(\.dismiss)` — pop NavigationStack về Tools home sau commit
- Toast fire BEFORE dismiss (app-scoped presenter persist qua transition)
- Toast copy chuyển "Filled/Signed PDF saved" → **"Saved to Home"** cross-app (Merge/Split/Convert/Scan/Sign/Fill Form)

### 🔀 Nhóm 9 — Spacing saga (5+ iterations, chốt bằng code-review)

User complain overlap giữa content cuối và tab bar **6-7 lần** trên MỌI tab. Tôi loop nhiều approach:
1. `.padding(.top)` giảm dư top space, bump `safeAreaInset` 84 → 110 → 130 → 150 → 180pt
2. `.contentMargins(.bottom, X, for: .scrollContent)` — unreliable
3. Local `.safeAreaInset(edge: .bottom)` chin trên List — vẫn overlap
4. Hard `.padding(.bottom, 120)` on VStack — quá dư
5. Dial down 24pt → regress
6. Explicit `Color.clear.frame(height:)` view cuối VStack — chạy nhưng vẫn tinh chỉnh

**Root cause thật (code-review finding #1)**: dual preference (`TabBarVisualHidden` + `TabBarInsetCollapsed`) mà tôi thiết kế để split "visual hide" vs "layout hide" — `onPreferenceChange` KHÔNG fire reliably khi child unmount trong NavigationStack destination. State `isTabBarInsetCollapsed` stuck true sau khi user pop back từ Sign/Fill Form → safeAreaInset = 0 → content overlap.

**Fix triệt để**: 
- **Drop `TabBarInsetCollapsedPreferenceKey` entirely** — không còn state để stuck
- RootView safeAreaInset **CONSTANT 150pt** (never conditional)
- `.hidesTabBar()` = visual hide + `.ignoresSafeArea(.container, edges: .bottom)` internally (destinations tự reclaim strip)
- Auto-hide dùng `.hidesTabBarVisually(_ hidden)` — chỉ visual toggle
- **Explicit `Color.clear.frame(height: 100)` view cuối Tools VStack** + Section spacer 80pt cho Library/Settings — final guaranteed clearance

### 🔧 Code Review (medium) — 3 finding

`/code-review` fork chạy cuối session, scope 20+ file thay đổi Session 12:

1. **HIGH** — TabBarInsetCollapsed stuck (như trên) — FIXED bằng drop preference split
2. **MEDIUM** — PreviewConfirmSheet swipe-to-dismiss leak temp file — chỉ Back button gọi onCancel, swipe bypass. FIXED: thêm `@State didCommit` + `.onDisappear { if !didCommit { onCancel() } }` — uniform cleanup
3. **LOW** — `commitPreview` catch failure leaks staged file — FIXED: `discardPreview(stagedURL)` trong catch block

**Verified clean** (9 điểm): LibraryVM observer + nonisolated(unsafe) deinit, Task cancellation, sensor feedback pattern, PDF write persistence Sign/Fill, coord math, ForEach identity, glassEffect API usage, VMs eager-init.

### Build state

Build clean nhiều lần trong session (~15 lần `xcodebuild BUILD SUCCEEDED`). App install + launch iPhone 16e sim (iOS 26.3) sau mỗi lần fix để user test bằng mắt. Final PID 99978.

### Trạng thái cuối session — 3 lô UNCOMMITTED

1. **Session 10 chiều** (2026-09-03) — toast+kebab+7bug — chưa commit
2. **Session 11** (2026-09-04 morning) — Tool Result Gallery — chưa commit
3. **Session 12** (2026-09-04 rest of day) — Fill & Sign + Tools card grid + Liquid Glass + spacing saga — chưa commit

User yêu cầu "tạm thời lưu local, commit sau" từ đầu session — vẫn giữ nguyên. Khi resume: option B commit theo timeline (3 commits, mỗi session 1 commit).

### 🔨 Code Deliverables — Session 12

**NEW files** (17):
- Wireframe: `FillAndSign-Mockup-v1.html`, `Tools-Home-CardGrid-v1.html`
- Extensions: `Notification+DocumentsChanged.swift`, `View+AutoHideTabBarOnScroll.swift`, `View+HidesTabBar.swift`, `View+ProminentInlineTitle.swift`
- Models: `FormFill.swift`
- Services/Protocols: `Form/FormFilling.swift`, `Signature/SignatureStamping.swift`
- Services/Implementations/Native: `PDFKitFormFiller.swift`, `PDFKitSignatureStamper.swift`
- ViewModels: `FillFormViewModel.swift`
- Views/PDFTools: `FillFormView.swift`, `PreviewConfirmSheet.swift`, `PrintFlowView.swift`, `SignFlowView.swift`
- Views (already listed): stubs replaced with real — `Models/Signature.swift`, `ViewModels/SignatureViewModel.swift`, `Views/Signature/SignatureCanvasView.swift`, `Views/Signature/SignaturePlacementView.swift`

**EDITED files** (~15):
- `App/DependencyContainer.swift` — signatureStamper + formFiller + 2 factories
- `Models/PDFToolDestination.swift` — 3 new cases (.fillForm, .sign, .print)
- `ViewModels/OCRViewModel.swift`, `ViewModels/PDFToolsViewModel.swift` — post documentsDidChange
- `ViewModels/LibraryViewModel.swift` — subscribe observer + nonisolated(unsafe) deinit
- `ViewModels/SignatureViewModel.swift` — real impl (was stub) + stage/commit/discard preview + failure discard
- `ViewModels/FillFormViewModel.swift` — stage/commit/discard preview + failure discard
- `Views/Editor/EditorPlaceholderView.swift` — PDFPreviewPane for .pdf
- `Views/Library/LibraryAddButton.swift` — FAB Liquid Glass + interactive + diameter 60pt
- `Views/Library/LibraryView.swift` — trailing Section spacer + autoHidesTabBarOnScroll
- `Views/OCR/ScanFlowView.swift` — prominentInlineTitle + toast copy + onShowGallery from Session 11
- `Views/PDFTools/ConvertFlowView.swift`, `Views/PDFTools/MergeSplitCompressView.swift` — prominentInlineTitle + toast copy
- `Views/Root/RootView.swift` — dual→single preference simplification, safeAreaInset constant 150pt, GlassEffectContainer around customTabBar, prominent tab bar (76×60 + `.symbolVariant(.fill)` selected + sensor feedback)
- `Views/Settings/SettingsView.swift` — Section spacer + autoHidesTabBarOnScroll + prominentInlineTitle
- `Views/Tabs/ToolsTabView.swift` — rewrite full 450 lines (card grid + ToolCard/ConvertToolCard/IconBadge/ToolCardSurface/PressableCardButtonStyle + destinationView hidesTabBar + prominentInlineTitle + explicit 100pt trailing spacer)

**Total**: ~35 file impacted (17 new + ~18 edited).

---

## [Unreleased] — 2026-09-04 (Session 11 — Tool Result Gallery)

Session ngắn: đóng lại **open UX question** từ cuối Session 10 chiều (pdfToImage không auto-navigate, gọi tổng quát "áp dụng hết cho các feature ở tính năng tool"). Chốt phương án **gallery cho mọi output đa file**, dựng mockup HTML, review, code SwiftUI, review lại rồi build clean.

### Chốt UX — Option A + gallery cho multi-output

- **Câu hỏi paused**: 3 interpretation A/B/C (bỏ auto-navigate all / giữ + thêm cho pdfToImage cách khác / cái khác). User trả lời chọn A NHƯNG có navigate → thực chất là interpretation MỚI: **áp dụng navigate cho MỌI tool feature**, kể cả multi-output (pdfToImage sinh N ảnh, Scan both formats sinh 2 file, Split N ranges sinh N PDF).
- **Follow-up clarify**: multi-output nên navigate đi đâu? 3 option (open first file / gallery view / back to Library filtered). User chọn **gallery** — nhất quán "xem kết quả", không cần view mới cho Library filter.

### Audit toàn bộ tool outputs (không sót case)

| Tool | Output count | Behavior mới |
|---|---|---|
| Merge PDFs | 1 | Editor auto-nav (giữ) |
| Split PDF (N=1) | 1 | Editor auto-nav (giữ) |
| **Split PDF (N>1)** | N | **Gallery** (đổi từ nav-first) |
| Convert officeToPDF | 1 | Editor auto-nav (giữ) |
| Convert pdfToWord | 1 | Editor auto-nav (giữ) |
| **Convert pdfToImage** | N | **Gallery** (đổi từ toast-only) |
| Convert imageToPDF | 1 | Editor auto-nav (giữ) |
| Scan single format | 1 | Editor auto-nav (giữ) |
| **Scan both formats** | 2 | **Gallery** (đổi từ toast-only) |

3 case đổi behavior, 6 case giữ nguyên.

### Deliverables

**NEW** (2):
- `Wireframe/Tool-Result-Gallery-v1.html` (mockup 3 lane: pdfToImage grid + Split list + Scan both formats mixed) — dựng theo design language chung với `PDFTools-Mockup-v2.html`, 5 quyết định inline (sheet vs push, grid vs list, Select mode, file storage, count=1 edge case).
- `Views/PDFTools/ToolResultGalleryView.swift` — bottom sheet `.large` detent, auto-layout (grid nếu all-image, list nếu mixed/docs), action bar Save All (DocumentPickerExporter) + Share All (ShareLink). `ToolCompletion` enum + `ImageExtension` whitelist helper trong cùng file.

**EDITED** (4):
- `Views/Tabs/ToolsTabView.swift` — thêm `@Environment(DSToastPresenter.self)` + `@State galleryPayload: GalleryPayload?` + `@State pendingEditorURL: URL?`. Two-sheet handoff via `.sheet(item:onDismiss:)` — gallery `onOpenFile` set `pendingEditorURL`, `onDismiss` sau đó gọi `openFile()` để trigger editor sheet. Fileprivate `GalleryPayload: Identifiable` wrapper cho `[URL]`. Preview inject `.environment(DSToastPresenter())` để tránh trap.
- `Views/PDFTools/MergeSplitCompressView.swift` — `SplitView` thêm `onShowGallery: (([URL]) -> Void)?` param. `performSplit` branch: count==1 → `onOpenFile`, count>1 → `onShowGallery`.
- `Views/PDFTools/ConvertFlowView.swift` — thêm `onShowGallery` param. `pdfToImage` case luôn `onShowGallery` (không editor destination cho image kể cả single-image export).
- `Views/OCR/ScanFlowView.swift` — thêm `onShowGallery` param. `urls.count == 1` → `onOpenFile`, else → `onShowGallery`.

### `/code-review` — 3 finding fix hết

1. **CONFIRMED** — `ToolsTabView.swift:376` `#Preview` thiếu `.environment(DSToastPresenter())` sau khi thêm `@Environment` ở line 8 → trap-crash. Same pattern như finding Nhóm 5 session cũ. Fix.
2. **PLAUSIBLE (perf)** — `fileSizeLabel` sync disk read mỗi lần render body qua `url.resourceValues([.fileSizeKey])`. OK cho 2-6 file, hitch risk khi PDF→Image 20+ trang. Fix: `@State sizeLabels: [URL: String]` precompute qua `.task(id: urls)` off-main. Body render `sizeLabels[url]` sync.
3. **PLAUSIBLE (memory)** — `AsyncImage(url:)` load full-res PNG. Export 2x scale sinh multi-MB per page → 20 trang ~40 MB memory pressure. Fix: `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize: 600` + `kCGImageSourceShouldCacheImmediately`. Cache trong `@State thumbnails: [URL: UIImage]`. Bounded <1 MB per thumbnail regardless nguồn.

Cả 2 perf fix gộp trong 1 `Task.detached(priority: .utility)` từ `preloadMetadata()` — tránh 2 lần dispatch.

### Build state

- `xcodebuild` clean 3 lần (initial gallery + preview fix + perf fix). App install + launch iPhone 16e sim (iOS 26.3), PID 60037 → 60511 → 60911 sau mỗi rebuild.
- Fork `/swiftui-expert-skill` review bị kill sớm khi user yêu cầu narrow scope — chưa cover full SwiftUI angle. Có thể relaunch sau nếu bạn muốn cover thêm.

### 🔨 Code Deliverables — Session 11

**NEW** (2):
- `Wireframe/Tool-Result-Gallery-v1.html`
- `Word Office/Views/PDFTools/ToolResultGalleryView.swift`

**EDITED** (4):
- `Word Office/Views/Tabs/ToolsTabView.swift`
- `Word Office/Views/PDFTools/MergeSplitCompressView.swift`
- `Word Office/Views/PDFTools/ConvertFlowView.swift`
- `Word Office/Views/OCR/ScanFlowView.swift`

### Trạng thái cuối session

- ✅ Gallery view code + wire xong 3 case multi-output
- ✅ Build clean, app relaunch
- ✅ 3 review finding fix hết (1 confirmed + 2 perf)
- ⏸️ **CHƯA commit** — user muốn "tạm thời lưu local, commit sau"
- ⏸️ Chưa test bằng mắt trên simulator (chờ user)
- ⏳ FAB scan (LibraryAddButton) chưa apply gallery pattern — ngoài scope Tools tab

---

## [Unreleased] — 2026-09-03 (Session 10 continuation — chiều)

Session kéo dài sau khi Session 10 morning batch đã commit. Chủ đề: user test end-to-end 4 tool flows (Merge/Split/Convert/Scan) trên simulator, phát hiện **7 bug + UX gap thật** qua từng lần bấm; mỗi lần fix xong test tiếp phát hiện thêm. Chia làm 5 nhóm fix + 1 refactor lớn (toast system + kebab menu). **Session đóng dở** với 1 câu hỏi UX chưa chốt (auto-navigate consistency across tools) — user "để mai xử lý tiếp".

### Nhóm 1 — Fix nil-VM race Tools destinations (all blank spinner)

- ✅ **Bug user báo**: "tất cả features tool bấm vào vẫn màn hình trắng" — screenshot cho thấy `ProgressView` spinner nhỏ giữa màn hình, không phải render EmptyStateView. Root cause: `ToolsTabView.destinationView(for:)` return `else { ProgressView() }` khi `pdfToolsVM == nil`. VMs được lazy-init trong `.task { if pdfToolsVM == nil { ... = container.makePDFToolsViewModel() } }` — trong pattern `ZStack + opacity 0/1` của Session 9, `.task` KHÔNG fire đúng lúc user tap NavigationLink → destination push với nil VM → ProgressView fallback → không bao giờ re-render vì `.navigationDestination` closure không auto-invalidate khi source state đổi post-push.
- ✅ **Fix**: eager-init VMs qua `init` (`State(wrappedValue: container.makePDFToolsViewModel())`) trong `ToolsTabView` + `LibraryAddButton`. VMs guaranteed non-nil tại first push. Bỏ `.task { ... init ... }` guard.

### Nhóm 2 — ScanFlowView Cancel duplicate + empty state overflow

- ✅ **Bug user báo**: screenshot Scan & OCR sau khi navigate — thấy Cancel button ở leading (cạnh back chevron `<`) là duplicate, VÀ nút "Scan with Camera" + text "Or choose from Photos / PDF" bị tab bar che khuất phía dưới.
- ✅ **Fix Cancel**: `ScanFlowView` giờ được dùng ở 2 context (Tools push + FAB sheet). Thêm param `showsExplicitCancel: Bool = false` — Tools push dùng default (không show Cancel vì back chevron có), LibraryAddButton sheet pass `true`.
- ✅ **Fix layout**: `emptyAddPages` cũ dùng `EmptyStateView` (có `.frame(maxHeight: .infinity)` baked in) + siblings buttons → siblings bị đẩy xuống đáy = bị tab bar che. Refactor bỏ `EmptyStateView`, viết inline layout `VStack { Spacer(); icon; text; Spacer(); button; menu }` để center icon+text và giữ buttons có breathing room.
- ✅ **Audit thêm 3 view** (MergeView/SplitView/ConvertFlowView) — cũng có `ToolbarItem(placement: .cancellationAction) { Cancel }` duplicate với back chevron. Vì 3 view này chỉ được push-only (không sheet), bỏ hẳn Cancel toolbar item.

### Nhóm 3 — Bug "2 secs" đếm tăng trong DSFileRow (user phát hiện 2 lần)

- ✅ **Bug lần 1**: sau khi pick file trong ConvertFlowView, row hiển thị "2 secs" và đếm tăng lên "5 secs" liên tục. Root cause: `DocumentRef` được init với `modifiedAt: .now` (hardcode) → `Text(date, style: .relative)` render "2 secs ago" và auto-refresh mỗi giây vì `.relative` là SwiftUI live-updating DateStyle.
- ✅ **Fix step 1**: thêm URL extension `contentModificationDateOrNow: Date` đọc POSIX modification date qua `URLResourceValues`. Update 4 sites picked-file dùng `url.contentModificationDateOrNow` thay `.now`. 4 sites success-created files giữ `.now` (đúng — vừa tạo). Kết quả: row show "6 days ago" (real modify date của file).
- ✅ **Bug lần 2**: user thấy "6 days, 3 hrs" (không rõ ngữ cảnh — không có "ago" suffix, compound units) rồi "5 secs" trên success screen. Root cause chung: `Text(date, style: .relative)` compound format + live-tick. Fix: đổi `DSFileRow` sang `Text(date, format: .relative(presentation: .named))` — static, natural language ("6 days ago", "yesterday", "now"), 1 dòng change benefit toàn app.
- ✅ **Audit thêm**: `DocumentCard.swift:27` modifiedAt VÀ `ReminderChip.swift:179` reminder date đều dùng `style: .relative` — cùng bug pattern. Fix 2 chỗ nữa.

### Nhóm 4 — Toast system + kebab menu (3-phase implementation)

User yêu cầu: success screens (Merge/Split/Convert/Scan) chuyển thành **toast** (không phải full-screen), file rows có **kebab menu 3 chấm** với 4 actions (Edit / Save to Files / Share / Favourite).

Clarify với user 5 câu hỏi:
- (1) Post-success view state: giữ file đã pick
- (2) Status change menu: giữ ở long-press context menu riêng
- (3) Edit action: in-app editor Mock (A1)
- (4) Save action: Files app export (B1)
- (5) Toast style: icon+text (C2)

**Phase 1 — Toast system**:
- ✅ NEW `DesignSystem/Components/Feedback/DSToastPresenter.swift` — `@Observable @MainActor` singleton, one toast at a time, `show(_:title:filename:duration:)` cancel previous dismissTask + set current + spawn Task auto-dismiss sau 3s.
- ✅ NEW `DesignSystem/Components/Feedback/DSToast.swift` — visual card: icon (success/error/info) + title + optional filename (truncationMode `.middle`), capsule `.regularMaterial` bg + border + shadow.
- ✅ Wire trong `Word_OfficeApp` — `@State toastPresenter = DSToastPresenter()` + `.environment(toastPresenter)` inject vào tree + `.overlay(alignment: .bottom)` render toast.

**Phase 2 — Replace 4 success screens**:
- ✅ `MergeView`/`SplitView` (`MergeSplitCompressView.swift`) — bỏ `didFinish` flag, xoá `MergeSuccessView` + `SplitSuccessView` structs (~130 dòng). `performMerge/performSplit` fires `toaster.show(.success, title:, filename:)`. User stays at picker.
- ✅ `ConvertFlowView` — bỏ `didFinish` + `successState` computed. 4 direction case fires toast riêng ("Converted to PDF"/"Converted to Word"/"Exported N images"/"PDF created").
- ✅ `ScanFlowView` — bỏ `.success` từ Stage enum + `successState` computed + `savedURLs` @State. Toast fires với count/filename, stage stays at `.exportFormat`.
- ✅ Xoá `SuccessBadge` component (`PDFToolsSharedUI.swift`) — dead sau refactor.

**Phase 3 — Kebab menu (3 chấm) file rows**:
- ✅ `DocumentCard.swift` — replace `FavouriteToggleButton` sibling với `FileActionsMenu` (new struct). Menu 4 items: Edit / Save to Files / ShareLink / Toggle Favourite (natural iOS Menu, iOS 16+ inline ShareLink). Fix live-tick time cùng lượt.
- ✅ `DocumentGrid.swift` — DocumentTile cũng dùng FileActionsMenu overlay top-trailing → consistent list/grid UX.
- ✅ NEW `Views/Common/DocumentPickerExporter.swift` — `UIViewControllerRepresentable` wrap `UIDocumentPickerViewController(forExporting:asCopy:true)` với Coordinator delegate cho Save to Files action.
- ✅ `LibraryView.swift` — thêm `let onOpenEditor: (DocumentRef) -> Void` init param + `@State exportingRef: DocumentRef?` + `.sheet(item: $exportingRef)` cho DocumentPickerExporter. Wire callbacks trong `row(for:)` + `sectionRows(_:)`.
- ✅ `RootView.swift` — thêm `@State editingRef: DocumentRef?` + `.sheet(item: $editingRef)` cho `EditorPlaceholderView(container:ref:)` (LibraryView không có container access, nên editor sheet ở RootView).

### Nhóm 5 — Toast top + auto-navigate + fix 6 SwiftUI review findings

User yêu cầu: (1) chuyển toast từ **bottom → top**; (2) sau khi có toast, **auto-navigate sang màn hình file mới** sau xử lý (revert lại choice #1 "giữ file đã pick" ban đầu).

- ✅ **Toast bottom → top**: `.overlay(alignment: .top)` + `.padding(.top, DSSpacing.xs)` + `.transition(.move(edge: .top))`. Nằm dưới status bar/Dynamic Island, slide từ trên xuống.
- ✅ **Auto-navigate**: mỗi tool view thêm `var onOpenFile: ((URL) -> Void)?`. `ToolsTabView` sở hữu `@State editingRef` + `.sheet(item:)` với `ToolsEditorSheet` wrapper. Single-file outputs (Merge, Convert 3 directions, Scan single, Split first-URL) → navigate. Multi-file (pdfToImage, Scan both formats) → skip navigate.

**6 SwiftUI review findings — chạy `/swiftui-expert-skill` review qua fork, fix hết**:
1. ✅ `DocumentCard.ReminderChip` VẪN dùng live-tick `Text(date, style: .relative)` — miss ở fix Nhóm 3 → fix nốt.
2. ✅ Dead `@Environment(\.dismiss)` trong `MergeView`/`SplitView`/`ConvertFlowView` — sau khi bỏ Cancel không còn call site → remove 3 declarations.
3. ✅ `#Preview("Root — checking")` thiếu `.environment(DSToastPresenter())` — descendants sẽ trap-fatalError trong preview happy-path → thêm.
4. ✅ `DSToast` dùng `.onTapGesture` (violate core a11y principle "Prefer Button") → wrap content trong `Button(action: onTap) { ... }.buttonStyle(.plain)`.
5. ✅ Toast không announce với VoiceOver khi appear → `UIAccessibility.post(notification: .announcement, argument: title)` trong `show()`.
6. ✅ Editor sheet Done button write parent state (violate skill "sheets own actions") → extract `LibraryEditorSheet` + `ToolsEditorSheet` structs với `@Environment(\.dismiss) private var dismiss`.

**+1 CRITICAL regression từ `/code-review` fork** (fix cùng batch):
- ✅ **Toast fired từ sheet context bị sheet che khuất** — SwiftUI sheets present ABOVE scene-root overlays. Sau khi auto-navigate mở editor sheet, toast ở Word_OfficeApp scene-root sẽ ở dưới sheet → invisible. Fix: extract `toastHost(_:)` modifier + apply ở scene-root VÀ inside `LibraryEditorSheet` + `ToolsEditorSheet` + FAB scan sheet trong `LibraryAddButton`. Mỗi sheet có toast overlay riêng.

### 🚧 Open question — chờ user chốt sáng mai

**Bug/UX gap**: user test PDF→Image, thấy toast "Exported 1 image" ở top + picker view vẫn hiện (Pages to export toggle) — **không navigate**. User comment: *"ô chưa điều hướng sang màn hình mới là màn hình revert file thành công à, áp dụng cho mọi tinsh năng của tools"*.

**Ambiguity**: câu chưa rõ, có 3 interpretation:
- **A. Bỏ hết auto-navigate**, TẤT CẢ tools chỉ toast + stay at picker (như pdfToImage hiện tại) — undo work Nhóm 5.
- **B. Giữ auto-navigate**, thêm cho pdfToImage 1 cách khác (VD: gallery view / preview ảnh đầu tiên).
- **C. Cái khác**.

**Đã ask user chọn 1/2/3** — user reply: *"tạm thời lưu lại vấn đề nhé... mai tôi quay lại xử lý tiếp"*. **PENDING chờ decision sáng mai**.

### Build state

Build clean sau mọi đợt fix (`xcodebuild ... BUILD SUCCEEDED`). App install + relaunch lên iPhone 16e simulator (iOS 26.3) sau mỗi fix để user test bằng mắt. Session cuối relaunch PID 46717.

---

### 🔨 Code Deliverables — Session 10 continuation

**NEW files** (3):
- `DesignSystem/Components/Feedback/DSToastPresenter.swift`
- `DesignSystem/Components/Feedback/DSToast.swift` (bao gồm `toastHost(_:)` modifier)
- `Views/Common/DocumentPickerExporter.swift`

**EDITED files** (13):
- `App/Word_OfficeApp.swift` — inject toastPresenter env + `.toastHost(toastPresenter)` scene-root.
- `DesignSystem/Components/File/DSFileRow.swift` — `style:.relative` → `format:.relative(presentation:.named)`.
- `Extensions/URL+Documents.swift` — thêm `contentModificationDateOrNow`.
- `Views/Library/DocumentCard.swift` — replace FavouriteToggleButton với FileActionsMenu, fix live-tick time modifiedAt + ReminderChip.
- `Views/Library/DocumentGrid.swift` — DocumentTile dùng FileActionsMenu overlay.
- `Views/Library/LibraryAddButton.swift` — eager-init ocrVM, `showsExplicitCancel: true` cho scan sheet, add `.toastHost(toaster)` inside scan sheet.
- `Views/Library/LibraryView.swift` — thêm `onOpenEditor` param + `exportingRef` sheet.
- `Views/OCR/ScanFlowView.swift` — bỏ `.success` stage, add `showsExplicitCancel` + `onOpenFile` params, restructure `emptyAddPages` inline, toast trigger.
- `Views/PDFTools/ConvertFlowView.swift` — bỏ `didFinish` + `successState`, bỏ Cancel + dead dismiss env, add `onOpenFile`, toast trigger cho 4 direction, `.contentModificationDateOrNow` cho picked file.
- `Views/PDFTools/MergeSplitCompressView.swift` — bỏ `didFinish` + MergeSuccessView + SplitSuccessView + dead dismiss, add `onOpenFile`, toast trigger, `.contentModificationDateOrNow`.
- `Views/PDFTools/PDFToolsSharedUI.swift` — xoá `SuccessBadge`.
- `Views/Root/RootView.swift` — add `editingRef` + `LibraryEditorSheet` wrapper, pass `onOpenEditor` to LibraryView, thêm toastPresenter env vào Preview.
- `Views/Tabs/ToolsTabView.swift` — eager-init pdfToolsVM+ocrVM, add `editingRef` + `ToolsEditorSheet` wrapper + `openFile(_:)` helper thread `onOpenFile` xuống child views (Merge/Split/Convert/Scan).

---

## [Unreleased] — 2026-09-03 (Session 10)

Session ngắn — chủ đề duy nhất là **đóng lại các đợt review dở dang từ Session 9** (user "hold" cuối session trước) + fix 1 bug user tự phát hiện trên simulator (FAB "+" menu tràn ra ngoài cạnh phải màn hình). Trong quá trình fix bug cũng đồng thời upgrade tab bar pill lên **Liquid Glass** (iOS 26 native) qua tư vấn `/swiftui-expert-skill` để nhất quán màu tab bar giữa các tab. Sau đó chạy đủ 2 review skill theo `rule.md` #4 (`/code-review` + `/swiftui-expert-skill`) trên diff, bắt tổng 8 finding, fix hết.

- ✅ **Fix FAB "+" menu tràn phải màn hình** — user thấy trên iPhone 16e sim: menu 220pt align phải với FAB, `VStack(alignment: .trailing)` bao (menu+FAB) khiến `LibraryAddButton` phồng lên 220pt, đẩy `HStack` `customTabBar` (tab pill ~228 + spacing 12 + LibraryAddButton 220 = 460pt) vượt available width (iPhone 393 - 32 padding = 361pt), đẩy FAB + menu ra ngoài mép phải màn hình. Fix: restructure `LibraryAddButton.body` sang `fabButton.overlay(alignment: .bottomTrailing) { addMenuContent.fixedSize().padding(.bottom, fabDiameter + DSSpacing.lg) }`. Kỹ thuật: padding invisible đẩy menu lên trên FAB, alignment `.bottomTrailing` pin padded box vào FAB bottom. Thử `.alignmentGuide(.top) { $0[.bottom] + gap }` trước nhưng `.transition` không propagate `.top` guide qua overlay chain — menu render xuống dưới FAB.top thay vì lên (verified thực tế). Thêm `static let fabDiameter: CGFloat = 56` làm single source of truth cho FAB frame + menu padding. Gap chọn `DSSpacing.lg` (20pt) chứ không `DSSpacing.sm` (12pt) vì trong `HStack(alignment: .bottom)` pill cao hơn FAB 12pt (56 button + 12 padding), gap 12pt = menu bottom flush pill top = trông đè.
- ✅ **Liquid Glass tab bar pill** — chọn Option A qua `/swiftui-expert-skill` tư vấn (3 option: A=Liquid Glass, B=`.thickMaterial`, C=solid color). Lý do gốc: `.regularMaterial` cũ adaptive theo content phía sau — pill khác màu giữa Library tab (list-card trắng) vs Settings tab (grouped-form xám-tím), vi phạm cảm giác nhất quán. Liquid Glass render surface độc lập content phía sau → nhất quán. `RootView.swift` đổi từ `.background(.regularMaterial, in: Capsule()) + .overlay(strokeBorder) + .shadow(...)` sang `.glassEffect(.regular, in: .capsule)` qua helper `fileprivate extension View { func tabBarPillStyle() }`. Bỏ border+shadow vì glass tự có edge highlight + depth (skill khuyến nghị, tránh double-outline). Ban đầu có `#available(iOS 26, *)` fallback nhưng đóng session sau bằng finding review: `IPHONEOS_DEPLOYMENT_TARGET = 26.2` + `SUPPORTED_PLATFORMS = iphoneos/iphonesimulator` (không Mac Catalyst) → fallback branch không bao giờ chạy → collapse extension thành 1 dòng direct call.
- ✅ **`/code-review` + `/swiftui-expert-skill` — 5 finding CONFIRMED, fix hết**:
  1. **Outside-tap không dismiss menu**: khác native `Menu`/`.popover`. Fix: lift `isMenuOpen` từ `LibraryAddButton` `@State private` → `RootView` `@State` + `@Binding`. Thêm scrim `Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture { closeFABMenu() }` giữa content ZStack và `customTabBar` trong `libraryShell`. `withAnimation(.easeOut(duration: 0.15))` matched giữa `LibraryAddButton.closeMenu()` và `RootView.closeFABMenu()` cho animation identical.
  2. **Tap fall-through qua "dead area" menu vào fabButton**: Text section header + Divider + padding vertical giữa row không có Button absorb, `.background(Color, in: Shape)` không guarantee absorb hit-test → tap dead area = fall through xuống fabButton = menu đóng bất ngờ. Fix: thêm `.contentShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))` sau `.background(...)` trên `addMenuContent`.
  3. **Missing accessibility grouping menu**: VoiceOver announce 5 rows như buttons rời rạc. Fix: `.accessibilityElement(children: .contain) + .accessibilityLabel("Add options")` trên `addMenuContent`. Thêm `.accessibilityAddTraits(.isHeader)` trên `menuSectionHeader`.
  4. **Tab switch với menu open → menu không đóng**: `.onChange(of: selectedTab) { closeFABMenu() }` trên `libraryShell` ZStack.
  5. **Stale comment `RootView.customTabBar`**: kiến trúc cũ VStack, sau restructure `LibraryAddButton` không đổi size khi menu mở nữa. Update comment giải thích lý do `.bottom` alignment mới thuần visual baseline (pill 68pt vs FAB 56pt shared bottom).
- ✅ **`/code-review` final — 3 finding cosmetic, fix hết**:
  1. `tabBarPillStyle()` fallback iOS <26 là dead code (đã note ở trên) — collapse thành 1 dòng.
  2. Ternary as statement `isMenuOpen ? closeMenu() : openMenu()` → `if isMenuOpen { closeMenu() } else { openMenu() }` — idiomatic Swift.
  3. `LibraryAddButton.closeMenu()` thiếu idempotency guard — asymmetric với `RootView.closeFABMenu()` (có guard) → gọi vào no-op state change vẫn mở `withAnimation` transaction, tốn 1 animation frame. Fix: thêm `guard isMenuOpen else { return }`.
- ✅ **Build sạch nhiều lần** (`xcodebuild ... BUILD SUCCEEDED`) sau mỗi đợt sửa. Install + launch thẳng lên iPhone 16e sim (iOS 26.3) qua `simctl install`+`launch` để user test bằng mắt sau mỗi lần fix.

---

### 🔨 Code Deliverables — Session 10

#### FAB "+" menu positioning
- `Views/Library/LibraryAddButton.swift` (edit) — restructure body VStack → overlay+padding, add `static let fabDiameter`, lift `isMenuOpen` state → `@Binding`, add `.contentShape` + accessibility grouping on menu card, `.isHeader` on section header, idempotency guard on `closeMenu()`, ternary → if/else.

#### Tab bar Liquid Glass + outside-tap-dismiss
- `Views/Root/RootView.swift` (edit) — add `tabBarPillStyle()` extension (collapse to direct `.glassEffect` call), replace 3 chained modifiers in `customTabBar` with `.tabBarPillStyle()`, add `@State isFABMenuOpen` + `closeFABMenu()` helper, add scrim in `libraryShell` ZStack, add `.onChange(of: selectedTab)` auto-close, pass `$isFABMenuOpen` binding to `LibraryAddButton`, update stale `.bottom` alignment comment.

#### Skill metadata (auto)
- `.agents/skills/ui-ux/SKILL.md` (edit) — YAML frontmatter (name + description) auto-added by skill invocation.

---

## [Unreleased] — 2026-09-02 (Session 9)

Session dài nhất tới giờ, chủ đề chính là **thiết kế lại toàn bộ Library Home** theo mockup `Library-Home-v10-Refinements.html` (Favourite, Search, Grid view, FAB Menu 3 nhóm) — nhưng phần tốn công nhất lại không phải feature mới mà là **vị trí FAB "+" so với tab bar**: đi qua 4 kiến trúc khác nhau trong 1 session (overlay-trong-tab → overlay-trên-`TabView` → `.tabViewBottomAccessory` → tự vẽ tab bar riêng) vì 2 API native đầu đều gây lỗi hiển thị thật (không phải chỉnh số sai), phải bỏ hẳn `TabView`/`Tab` để có kiểm soát layout 100%. Cộng thêm: app icon mới, splash screen, sweep bỏ dấu chấm cuối câu toàn bộ text UI theo yêu cầu user, và 2 đợt `/code-review` riêng biệt bắt tổng 15 lỗi thật (1 crash) — đều đã fix. User yêu cầu "hold" review ở cuối session (đã dừng agent đang chạy) — **chưa có đợt review cuối cùng xác nhận trạng thái sau các fix mới nhất**.

- ✅ **Library Home v10 — Favourite/Search/Grid/FAB Menu, code thật theo mockup đã duyệt**:
  - `DocumentMetadata.isFavourite: Bool` (mới) + GRDB migration `v2_favourite` (`MetadataStoreImpl`) — trục lọc độc lập với `status`.
  - `.searchable()` trên `LibraryView`, kết quả phẳng (`searchResults`, bỏ qua due/date-bucket) khi đang gõ.
  - Grid/List view toggle — `DocumentGrid.swift` (mới, `LazyVGrid` 2 cột) song song `DocumentCard` list-row, `@AppStorage` persist chế độ xem.
  - FAB đổi từ 1 hành động thẳng (`fileImporter`) sang menu 3 nhóm: **Create new** (Word/Spreadsheet/Presentation), **Add existing** (Import — logic cũ), **Scan** (tái dùng đúng `OCRViewModel`/`ScanFlowView` Tools tab đang dùng thật). "Create new" chỉ **Word hoạt động thật** (viết OOXML thật qua `DOCXCodec`, cùng codec Scan dùng để export) — Excel/PowerPoint hiện alert "Coming soon" vì `MockArtifexDocumentWriter` no-op 2 format này thật (chưa có Artifex SDK), không giả vờ thành công với file rỗng.
  - Title "Your Library" → "Your Cabinet"; icon Premium (sparkle, không phải crown — tránh cảm giác "huy hiệu game") đặt `ToolbarItem(.topBarTrailing)`, chưa có đích đến thật (chờ paywall UI, TODO trong code).
- 🔄 **FAB "+" song song navbar — 4 vòng kiến trúc trong 1 session**, 2 vòng đầu gây bug hiển thị thật:
  1. `.overlay` trong nội dung riêng `LibraryView` — an toàn nhưng chỉ hiện ở tab Library, nổi cách tab bar 1 khoảng.
  2. `.overlay` thẳng lên `TabView` (để hiện mọi tab, đè lên trên tab bar) → **vệt đen cắt góc tab bar thật, mọi tab**.
  3. `.tabViewBottomAccessory` (API chính thức iOS 26 cho "control đi cùng tab bar") → **tự bọc nội dung trong pill full-width cố định, clip mất menu** khi mở rộng ra ngoài khung.
  4. **Quyết định cuối**: bỏ hẳn `TabView`/`Tab`, `RootView` tự vẽ tab bar (`customTabBar` — pill Library/Tools/Settings + FAB, 2 view anh em trong 1 `HStack`) — không còn tầng hệ thống nào để đá nhau. Đổi lại: mất "tap lại tab đang chọn để cuộn về đầu" + "tab bar tự thu nhỏ khi cuộn" (hành vi native miễn phí của `TabView`). Cũng phát hiện + fix theo sau: chuyển `switch selectedTab` (chỉ dựng đúng 1 tab, phá navigation state khi đổi tab) → giữ cả 3 tab sống song song qua `opacity`/`allowsHitTesting`/`accessibilityHidden`, đúng hành vi `TabView` gốc; `.searchable()` mặc định (`placement: .automatic`) từng tự thu nhỏ + gắn nhầm vào tab bar tự vẽ (không còn `TabView` thật để neo) → ép `placement: .navigationBarDrawer(displayMode: .always)`.
  - File: `Views/Root/RootView.swift` (viết lại phần shell), `Views/Library/LibraryAddButton.swift` (mới, tách riêng khỏi `LibraryView`), `Views/Library/LibraryView.swift` (bỏ FAB ra ngoài).
- ✅ **App icon** — áp ảnh user cung cấp, fix lỗi góc trắng khi hiện trên Home Screen: ảnh gốc có bo góc + đổ bóng riêng (không phải art full-bleed edge-to-edge), iOS tự mask lần 2 lộ góc trắng. Fix: dựng gradient nền khớp đúng màu icon (lấy mẫu màu từ chính ảnh) rồi composite icon gốc đè lên, lấp góc liền mạch. Sinh đủ size thật (16→1024px) cho iPhone/iPad/Mac Catalyst qua `Contents.json` mới.
- ✅ **Splash screen** (`Views/Root/SplashView.swift`, mới) — logo + "Word Office" + tagline căn giữa màn hình, `ProgressView` loading căn giữa-dưới. Tagline **"From draft to signed — all on your device"** chốt qua 1 vòng brainstorm định vị lại app (4 trụ cột USP có sẵn trong `product-strategy-master.md`, chưa có tagline chủ đạo — đề xuất 5 phương án, user chọn #2). Gắn vào `Word_OfficeApp.swift` — hiện cố định 1.2s rồi fade, không phải launch screen hệ thống thật (launch screen giữ mặc định tối giản của Xcode theo đúng khuyến cáo Apple HIG).
- ✅ **Bỏ dấu chấm cuối câu toàn bộ text UI** — rà 2 lần (Views+ViewModels rồi Services+Models, lần đầu bỏ sót tầng Services), sửa 67 chỗ / 30 file, script Python thay `."` → `"` theo từng dòng đã grep chính xác, verify lại bằng grep toàn repo = 0 kết quả còn sót.
- ✅ **`/code-review` đợt 1 (medium)** — 8 finding trên diff uncommitted rộng hơn (bao gồm code Session 7 cũ, không riêng phần mới session này), tất cả đã fix: `PDFToolsViewModel` không reset state cũ khi thao tác mới fail (hiện nhầm màn "Succeeded" với file cũ); `EditorViewModel.markDirty()`/`flushIfNeeded()` race (Task đăng ký chưa kịp chạy thì flush đã gọi, mất autosave im lặng); `DOCXCodec.read()` không cảnh báo khi docx có bảng/ảnh (khác `write()` đã từ chối ghi đè); `SettingsView`/`LibraryViewModel` race khi đổi folder giữa lúc đang scan; `OCRPreviewView` tra sai trang khi có trang OCR fail giữa chừng; `ScanFlowView`/`MergeSplitCompressView` render PDF đồng bộ trên main thread (treo UI) + thiếu `accessibilityLabel` 2 nút icon-only; `PDFToolsViewModel.checkNeedsOCR` nuốt lỗi thành "không cần OCR" (đổi `Bool` → `Bool?`).
- ✅ **`/code-review` đợt 2 (medium)** — 7 finding trên diff sau khi code xong Library v10 + custom tab bar, tất cả đã fix (1 **crash thật**): `MergeSplitCompressView` Split PDF crash gần 100% lần đầu chọn file (`Stepper(..., in: 1...pageCount)` render trước khi `pageCount` async fetch xong, `1...0` là range không hợp lệ) → `1...max(pageCount, 1)`; `LibraryViewModel.isLoading` không gate theo `loadGeneration` như các chỗ khác trong `loadLibrary()`; `EditorViewModel.markDirty()` 2 lần gõ liên tiếp không đảm bảo thứ tự đăng ký autosave (chain lên `registrationTask` trước đó); `AutosaveScheduler` task lặp 30s **không ai từng gọi `cancel(id:)`** — mọi editor đóng lại vẫn âm thầm ghi đè bản cũ mỗi 30s mãi mãi tới khi app bị kill, thêm `EditorViewModel.stopAutosaving()` gọi ở `.onDisappear`; `LibraryViewModel`/`URL+DocumentID` 2 lỗi symlink/hash khiến quét trùng thư mục hoặc va ID file cùng tên ở 2 nguồn khác nhau; `LibraryView` tự viết lại `.alert` thay vì dùng `errorAlert(_:)` helper đã tách sẵn.
- ⏳ **User yêu cầu "hold" ở cuối session** — đã dừng agent `/code-review` đang chạy nền (kể cả 2 sub-agent con) qua `TaskStop`. Đợt review này KHÔNG hoàn tất — chưa xác nhận diff cuối cùng (search placement fix + tăng size tab bar) sạch. Build (`xcodebuild ... BUILD SUCCEEDED`) đã chạy sau mọi đợt sửa trong session, kể cả đợt cuối — chỉ riêng phần review là chưa xong.

---

### 🔨 Code Deliverables — Session 9

#### Library Home v10 (Favourite/Search/Grid/FAB Menu)
- `Models/DocumentMetadata.swift` (edit) — `isFavourite: Bool`.
- `Services/Implementations/Native/MetadataStoreImpl.swift` (edit) — migration `v2_favourite`, upsert SQL + decode.
- `ViewModels/LibraryViewModel.swift` (edit) — `setFavourite`, `searchText`, `createBlankDocument(kind:)`, `documentCreator` dependency mới.
- `ViewModels/LibraryViewModel+Filtering.swift` (edit) — `favouritesOnly`, `searchResults`.
- `App/DependencyContainer.swift` (edit) — truyền `documentCreator` (`localFileService`) vào `LibraryViewModel`.
- `Views/Library/DocumentCard.swift` (edit) — `FavouriteToggleButton` sibling `Button` (không lồng trong Button chính — List cho mỗi Button top-level 1 tap target riêng).
- `Views/Library/DocumentGrid.swift` (mới) — `LazyVGrid` 2 cột, `DocumentTile`.
- `Views/Library/LibraryView.swift` (edit nhiều đợt) — title, toolbar Premium icon, `viewControlsRow` (Favourite/Grid-List/Filter), `.searchable()`, bỏ FAB ra ngoài (chuyển `LibraryAddButton`).
- `Views/Library/LibraryAddButton.swift` (mới) — FAB + menu custom (không dùng `Menu`/`.popover` — tự dựng để kiểm soát animation xoay icon + thứ tự item).
- `Word OfficeTests/LibraryViewModelTests.swift` (edit) — fix constructor call thiếu `documentsURL`/`documentCreator` (đã broken từ trước session này, không compile được — tiện sửa luôn khi đổi cùng initializer), thêm `MockDocumentCreator`.

#### FAB + tab bar (kiến trúc cuối — tự vẽ, không dùng `TabView`)
- `Views/Root/RootView.swift` (viết lại phần shell) — `customTabBar` tự vẽ, giữ cả 3 tab sống song song qua `opacity`/`allowsHitTesting`/`accessibilityHidden`.

#### Icon + Splash
- `Word Office/Assets.xcassets/AppIcon.appiconset/Contents.json` (edit) + `AppIcon-{16,32,64,128,256,512,1024}.png` (mới) — icon thật.
- `Word Office/Assets.xcassets/SplashLogo.imageset/` (mới).
- `Views/Root/SplashView.swift` (mới), `App/Word_OfficeApp.swift` (edit) — wiring splash.

#### Bug fixes — 2 đợt `/code-review` (15 finding, xem chi tiết ở mục trên)
- `ViewModels/PDFToolsViewModel.swift`, `Views/PDFTools/ConvertFlowView.swift`, `ViewModels/EditorViewModel.swift`, `Services/Implementations/Native/DOCXCodec.swift`, `Views/OCR/OCRPreviewView.swift`, `Views/OCR/ScanFlowView.swift`, `Views/PDFTools/MergeSplitCompressView.swift`, `ViewModels/LibraryViewModel.swift`, `Extensions/URL+DocumentID.swift`, `Views/Editor/EditorPlaceholderView.swift`, `Views/Library/LibraryView.swift`.

#### Text — bỏ dấu chấm cuối câu (67 chỗ / 30 file)
- Toàn bộ `Views/`, `ViewModels/`, `Services/Protocols/`, `Services/Implementations/` — không liệt từng file, xem `git diff` cho danh sách đầy đủ.

---

## [Unreleased] — 2026-09-02 (Session 8)

Session bắt đầu từ 3 lỗi build thật do Session 7 "chưa build/chạy Xcode" để lại, rồi mở rộng thêm 1 tính năng nhỏ (Skip onboarding) + review đầy đủ + 1 bug tương tác thật khá tinh vi (overlay chặn tap) phát hiện qua chính user bấm thử trên simulator. Lần đầu session này build được bằng `xcodebuild` CLI (trước giờ chỉ verify qua Xcode UI của user) — dùng để build+cài+launch thẳng lên simulator qua `simctl`, bypass việc phải nhờ user tự Run lại mỗi lần.

- ✅ **Fix 2 lỗi build thật còn tồn từ Session 7**: `MergeSplitCompressView.swift` thiếu `import UniformTypeIdentifiers` (dùng `.pdf` UTType mà không import — 2 lỗi "Static property 'pdf' is not available"); `ScanFlowView.swift` generic parameter `<Label: View>` trùng tên với `SwiftUI.Label` khiến `Label("Scan with Camera", systemImage:...)` bị resolve nhầm sang generic param → đổi tên thành `MenuLabel`.
- ✅ **Tính năng mới: "Skip for now" trên màn permission onboarding** — user có thể vào thẳng Library/Tools/Settings mà chưa cấp quyền folder, Library tự hiện empty-state riêng ("No folder yet") với CTA "Choose folder" ngay tại chỗ để cấp quyền sau. Chi tiết ở Code Deliverables.
- ✅ **`/swiftui-expert-skill` review trên diff Skip for now** — 3 finding, cả 3 đã fix:
  1. `.task { await loadLibrary() }` không tự chạy lại khi `folderPermissionState` chuyển `.notGranted → .granted` từ chính CTA trong Library (vì view không bị recreate, khác luồng cũ) → đổi `.task(id: store.folderPermissionState) { ... }`.
  2. `RootView` (1 View) ghi thẳng `libraryStore.didSkipFolderOnboarding = true`, vi phạm quy ước đã ghi sẵn trong `LibraryStore.swift` ("Writes come from ViewModels; views read only") → thêm `FolderPermissionViewModel.skipOnboarding()`, RootView gọi qua đó.
  3. `onSkip`/`onRequestPermission` khai `var` thay vì `let` (lệch convention `SettingsView.onChangeFolder` sẵn có) → đổi `let`.
- ✅ **Fix gap có sẵn từ trước: FAB "+" ở Library bị ẩn hoàn toàn khi rỗng** — `LibraryView`'s empty-state message ("No documents yet... Tap the + button...") từng hứa có nút + nhưng điều kiện hiện tại (`!store.entries.isEmpty`) lại giấu nó đúng lúc đó. Đổi điều kiện sang `folderPermissionState != .checking` — FAB giờ luôn hiện, cho user add file thủ công (`LibraryViewModel.importFiles(from:)`, độc lập hoàn toàn với việc đã cấp quyền folder hay chưa) kể cả ở màn "No folder yet" mới.
- ✅ **`/code-review` (medium) trên diff Skip for now** — 2 finding:
  1. **Đã fix**: CTA "Choose folder" mới trong empty-state của Library gọi `permissionVM.requestPermission()` không có guard chống double-tap (khác mọi CTA anh em khác đều có `.disabled(isRequesting)`) — double-tap nhanh làm `FolderPermissionPicker` (chỉ giữ 1 `continuation`) bị ghi đè, treo Task đầu + present 2 picker chồng nhau. Fix tại nguồn: thêm `guard !isRequesting else { return }` ngay đầu `requestPermission()` — bảo vệ mọi call site kể cả `EmptyStateView`'s action vốn không có chỗ gắn `.disabled` từ ngoài.
  2. **Chưa fix (nit hiệu năng nhỏ, để dành)**: `LibraryView.dueEntries`/`groupedSections` là computed property bị gọi lại 2-3 lần mỗi lần render `libraryList`, mỗi lần re-filter/sort lại từ đầu — nên gom vào `let` cục bộ trong `libraryList` nếu sau này thấy lag với thư viện nhiều file.
- ✅ **Bug thật: bấm Merge PDFs/Split PDF/4 thẻ Convert trên Tools tab không phản ứng gì** — user tự phát hiện qua test trên simulator. Nguyên nhân: `pairCard` (Convert) và `organizeList` (Merge/Split) trong `ToolsTabView.swift` đều gộp 2 `NavigationLink` cạnh nhau trong 1 HStack/VStack rồi phủ `.overlay(RoundedRectangle().stroke(...))` lên TRÊN — dù chỉ vẽ viền mỏng, SwiftUI hit-test 1 Shape theo toàn bộ diện tích path (không phải theo đường viền thực tế), nên overlay này chặn tap của toàn bộ 2 NavigationLink bên dưới. "Scan & OCR" hero không dính vì overlay nằm ngay trong label của chính NavigationLink đó (không đè lên link khác). Fix: thêm `.allowsHitTesting(false)` vào overlay ở cả 2 chỗ. Audit toàn bộ codebase tìm pattern tương tự — không còn chỗ nào khác bị (các `.overlay` còn lại đều nằm trong đúng 1 phần tử tương tác, hoặc là FAB góc màn hình).
- ✅ **Build verify liên tục** — `xcodebuild -scheme "Word Office" -destination "generic/platform=iOS Simulator" build` chạy `BUILD SUCCEEDED` sau mỗi đợt fix (5 lần trong session). Sau đợt fix cuối, `xcrun simctl install`+`launch` thẳng lên simulator "iPhone 17 Pro" đang mở của user để họ test lại ngay, không cần tự Run lại Xcode.
- ⏳ **Vẫn chưa xác nhận bằng mắt (máy dev không có quyền Accessibility cho `System Events`/coordinate-click, không tự động hoá tap được)**: kết quả sau fix overlay hit-testing trên Tools tab — user tự bấm lại xác nhận; toạ độ text vô hình trong `CGSearchablePDFRenderer` (tồn đọng từ Session 7); cú pháp `Menu{PhotosPicker(...)}` trong `ScanFlowView`.

---

### 🔨 Code Deliverables — Session 8

#### Fix 2 lỗi build tồn từ Session 7 (2026-09-02)
- `Views/PDFTools/MergeSplitCompressView.swift` (edit) — thêm `import UniformTypeIdentifiers`.
- `Views/OCR/ScanFlowView.swift` (edit) — generic param `<Label: View>` → `<MenuLabel: View>` trong `moreSourcesMenu`.

#### "Skip for now" onboarding + fix theo sau (2026-09-02)
- `App/LibraryStore.swift` (edit) — thêm `didSkipFolderOnboarding: Bool` (in-memory, không persist).
- `Views/Import/FolderPermissionOnboarding.swift` (edit) — thêm `let onSkip: () -> Void` + `skipButton`.
- `ViewModels/FolderPermissionViewModel.swift` (edit) — thêm `skipOnboarding()`; `resetPermission()` reset lại flag; `requestPermission()` thêm `guard !isRequesting else { return }`.
- `Views/Root/RootView.swift` (edit) — tách `libraryShell` (`@ViewBuilder`) dùng chung cho `.granted` và `.notGranted`+skip; case `.notGranted` gọi `permissionVM.skipOnboarding()` qua closure `onSkip`.
- `Views/Library/LibraryView.swift` (edit) — thêm `let onRequestPermission: () async -> Void`; nhánh empty-state mới khi `folderPermissionState == .notGranted`; `.task` đổi thành `.task(id: store.folderPermissionState)`; điều kiện hiện FAB đổi từ `!store.entries.isEmpty` sang `folderPermissionState != .checking`.

#### Fix bug overlay chặn tap trên Tools tab (2026-09-02)
- `Views/Tabs/ToolsTabView.swift` (edit) — thêm `.allowsHitTesting(false)` vào overlay viền của `pairCard` (Convert) và `organizeList` (Merge/Split).

---

## [Unreleased] — 2026-09-01 (Session 7)

Library core loop chuyển từ "đã chốt qua mockup" sang **code Swift thật, build xanh** — navbar/filter/FAB đi qua nhiều vòng mockup (v2→v7 trong `Wireframe/`, cộng 3 hướng chủ đề "tủ hồ sơ" A/B/C bị user bác bỏ vì chỉ đổi UI bề mặt, không đổi logic) trước khi chốt. Nhân tiện phát hiện 2 hàm gộp nhóm (`heroCopy`/`dueReminderEntries`/`groupedEntries`) đã viết từ session trước nhưng chưa ai gọi tới — nối vào lần này. Ngoài Library, fix riêng 1 bug nghiêm trọng ở tầng Autosave (mất dữ liệu âm thầm, không liên quan Library) theo yêu cầu ưu tiên của user. Cộng mockup mới cho PDF Tools (bản cũ đã mất) đang chờ duyệt, và gom toàn bộ `.html` mockup vào folder `Wireframe/` để dễ quản lý.

- ✅ **`RootView.swift`** — bọc trạng thái `.granted` trong `TabView` 3 tab (Library/Tools/Settings), dùng `Tab(...)` API (deployment target 26.2, không cần `#available`). Gap "chưa có TabView" tồn đọng từ nhiều session trước — đã đóng.
- ✅ **`LibraryView.swift` viết lại hoàn toàn** — navbar 2 lớp thật qua `.navigationTitle`+`.toolbar` (không tự vẽ), icon Filter trần đổi outline→filled (`line.3.horizontal.decrease.circle`/`.fill`) + `.badge()` khi active thay vì nền màu (v4-v6 làm sai chỗ này, user bắt lỗi qua so sánh Mail/Notes/Files thật), `List` `.insetGrouped` với section "Needs Attention" + section theo `DateBucket`, type-tabs cuộn ngang, FAB nổi thay nút Add cũ.
- ✅ **`Models/DocumentTypeFilter.swift`** (mới) — enum All/Word/Excel/PowerPoint/PDF gộp nhóm `DocumentKind` cho type-tabs.
- ✅ **`ViewModels/LibraryViewModel+Filtering.swift`** (mới) — `filteredEntries`/`isFiltering`/`count(for:)`, lọc theo `typeFilter`+`statusFilter` **trước khi** `+Grouping` chạy due/date-bucket.
- ✅ **`ViewModels/LibraryViewModel+Grouping.swift`** (edit) — `dueReminderEntries()`/`groupedEntries()` đổi nguồn từ `store.entries` → `filteredEntries`; đây là 2 hàm đã viết sẵn từ session UC16 (2026-08-28) nhưng `LibraryView` chưa từng gọi tới — dead code tới hôm nay mới sống.
- ✅ **`ViewModels/LibraryViewModel.swift`** (edit) — thêm `typeFilter`/`statusFilter`; **fix gap 2-source merge** tồn đọng nhiều session: `loadLibrary()` giờ quét song song thư mục cấp quyền + sandbox `Documents/`, merge theo `documentID` (bỏ qua quét lần 2 nếu 2 thư mục trùng nhau); `importFiles()` `upsert` ngay vào store thay vì chờ lần load sau.
- ✅ **`App/DependencyContainer.swift`** (edit) — truyền `documentsURL` vào `LibraryViewModel`.
- ✅ **`Views/Settings/SettingsView.swift`** (edit) — thêm section "Library" → "Change folder…" (nhận closure từ `RootView`); "Rescan folder" bỏ hẳn (đã có `.refreshable`).
- ✅ **`Views/Import/FolderPermissionOnboarding.swift`** (edit) — copy "Reset from the toolbar menu" → "Reset from Settings" (theo đúng chỗ mới).
- ✅ **`/code-review` (medium) trên toàn bộ diff** — 3 finding, fix 2, báo lại 1:
  1. `count(for:)` badge số trên type-tab không tính `statusFilter` dù docstring nói có tính → sửa khớp lại logic với docstring.
  2. `loadLibrary()` quét trùng 2 lần cùng thư mục nếu thư mục cấp quyền chính là `Documents/` → thêm so sánh đường dẫn, bỏ qua scan thứ 2.
  3. **Không sửa trong đợt này** (khác subsystem) — `DOCXCodec.write()` throw `.richContentUnsupported` đúng, nhưng `AutosaveScheduler` nuốt âm thầm mọi lỗi lưu → xử lý riêng ngay sau đó theo yêu cầu ưu tiên của user (xem mục dưới).
- ✅ **Fix bug Autosave silent-failure** (`Services/Protocols/Autosave/AutosaveScheduling.swift`, `Services/Implementations/Native/AutosaveScheduler.swift`, `ViewModels/EditorViewModel.swift`, `Views/Common/ErrorBanner.swift`, `Views/Editor/EditorPlaceholderView.swift`) — chi tiết ở mục Code Deliverables bên dưới.
- ✅ **Mockup PDF Tools mới** — `Wireframe/PDFTools-Mockup-v1.html` (Tools home, Merge, Split, Scan & OCR). Bản cũ (session 6 nói "đã duyệt bố cục") không còn trong repo (mất theo scratchpad phiên cũ) — dựng lại từ đầu, giới hạn đúng phạm vi `PDFToolsViewModel`/`OCRViewModel` đã wire (chỉ PDF, chưa DOCX/PPTX merge), màu lấy hex thật từ `Assets.xcassets`. **Đang chờ user duyệt**, chưa code SwiftUI.
- 🔄 **Scope PDF Tools mở rộng thêm 4 chiều convert** (Office→PDF, PDF→Word, PDF→Image, Image→PDF — mục cuối bổ sung mới hoàn toàn, chưa từng có ở bất kỳ bản MVP nào trước đó) — cập nhật `Phase0-Implementation-Logic-v2.md` §7.4 + bảng effort (cả 4 xếp vào nhóm "Rẻ", tái dùng `exportAs` SDK/`DOCXCodec`/`PDFKit`/`UIGraphicsPDFRenderer` có sẵn, không viết engine mới). Đang dựng `Wireframe/PDFTools-Mockup-v2.html` thay thế v1 — Tools home thiết kế lại (feature grid theo nhóm Convert/Organize/Scan, nav kính mờ + large-title, progress ring) theo yêu cầu "đẹp/xịn/chuẩn iOS native hơn". **Chưa code SwiftUI**, chờ duyệt cùng đợt.
- 🔄 **Định nghĩa lại Scan & OCR** — qua trao đổi phát hiện hiểu nhầm: MVP cũ định nghĩa output chính là "PDF searchable" (chỉ tìm/copy được chữ, không sửa) — user cần "sửa được" (editable) là yêu cầu chính. Sửa `Phase0-Implementation-Logic-v2.md` §6: (1) input mở rộng 1→3 nguồn (camera / ảnh thư viện / PDF scan cũ không chữ số, dùng chung 1 pipeline OCR), (2) output đổi ưu tiên — `.docx` sửa được (tái dùng `DOCXCodec.write`, rẻ) lên chính, PDF searchable lùi phụ, cho chọn cả 2. Kéo theo "PDF → Word" §7.4 phải tự phát hiện PDF có/không có lớp chữ số rồi fallback OCR khi cần. Mockup v2 đã cập nhật đủ + thêm concept "Native Depth" (Scan hero tách khỏi category, Convert gộp 2 cặp) — **đã được user duyệt**.
- ✅ **Code SwiftUI thật cho toàn bộ PDF Tools** (Merge/Split/4 chiều Convert/Scan & OCR), theo đúng mockup v2 đã duyệt. 2 đợt review liên tục (rule.md #4): Đợt 1 Service+ViewModel qua `/code-review` (2 lỗi thật: `OCRViewModel.recognize()` thiếu reentrancy guard có thể crash `Dictionary(uniqueKeysWithValues:)`; `PDFKitTextExtractor` quyết định OCR theo document thay vì theo trang, mất chữ trang scan trong PDF trộn); Đợt 2 View qua `/swiftui-expert-skill` (4 lỗi thật: dùng `.offset`/index làm `ForEach` id trên 4 list có xoá/kéo-thả — vi phạm hard rule, đổi hết sang wrapper `Identifiable`). Cả 6 đã sửa. File mới: 5 service (`MockArtifexDocumentExporter`, `PDFKitTextExtractor`, `PDFKitImageExporter`, `UIGraphicsImagePDFExporter`, `CGSearchablePDFRenderer`) + 8 file UI (`ToolsTabView` viết lại, `MergeSplitCompressView` viết lại, `ConvertFlowView`/`ScanFlowView`/`OCRPreviewView`/`DocumentCameraScanner`/`PDFToolsSharedUI`/`PDFToolDestination` mới). **CHƯA build/chạy Xcode/Simulator** — 3 điểm cần user tự verify: toạ độ text vô hình trong `CGSearchablePDFRenderer` (raw CGContext, chưa test trên device), `Menu{PhotosPicker(...)}` pattern, cú pháp tuple literal cho `EmptyStateView(...action:)`.
- ✅ **Gom toàn bộ mockup `.html` vào `Wireframe/`** (repo root) — `git mv` cho 2 file đã commit (`TuHoSo-Flow-Review.html`, `library-preview.html`), `mv` cho 5 file mới của session này/trước.
- ✅ Build verify nhiều lần (`xcodebuild ... BUILD SUCCEEDED`, cả `generic/platform=iOS Simulator` lẫn device cụ thể iPhone 17) sau từng đợt sửa. Launch thử trên Simulator xác nhận app chạy, màn hình onboarding hiện đúng copy mới.
- ⏳ **Chưa xác nhận bằng mắt** màn hình Library thật (cần cấp quyền 1 thư mục qua system document picker — không tự động hoá được vì máy dev chưa cấp quyền Accessibility cho `System Events`/coordinate-click).
- ⏳ **Chưa làm**: code SwiftUI cho PDF Tools (chờ duyệt mockup), Files Provider Extension, View Comment/Signature/Watermark (vẫn stub) — không đổi so với các session trước.

**Bước tiếp theo khi resume:**
1. User tự cấp quyền 1 thư mục thật trên Simulator/device, xem lại toàn bộ luồng Library (due section, date bucket, type-tab filter, status filter, FAB import) — chưa ai xác nhận bằng mắt.
2. User duyệt `Wireframe/PDFTools-Mockup-v1.html` (hoặc yêu cầu sửa).
3. Sau khi duyệt → code thật `ToolsTabView`/`MergeSplitCompressView`/`ScanFlowView`/`OCRPreviewView`, review bằng `/code-review` + `/swiftui-expert-skill` như đợt Library.

---

### 🔨 Code Deliverables — Session 7

#### Library core loop — code thật (2026-09-01)
- `Models/DocumentTypeFilter.swift` (new) — All/Word/Excel/PowerPoint/PDF, gộp `DocumentKind`.
- `ViewModels/LibraryViewModel+Filtering.swift` (new) — `filteredEntries`/`isFiltering`/`count(for:)`.
- `ViewModels/LibraryViewModel+Grouping.swift` (edit) — nguồn dữ liệu đổi sang `filteredEntries`.
- `ViewModels/LibraryViewModel.swift` (edit) — `typeFilter`/`statusFilter` state; `loadLibrary()` quét 2 nguồn song song + merge theo `documentID` + bỏ qua double-scan khi trùng thư mục; `importFiles()` upsert ngay; helper `mergeSecondSource(_:into:)` mới.
- `App/DependencyContainer.swift` (edit) — `makeLibraryViewModel` truyền thêm `documentsURL`.
- `Views/Root/RootView.swift` (edit) — `TabView` 3 tab thay cho `LibraryView` đơn lẻ ở case `.granted`.
- `Views/Library/LibraryView.swift` (rewrite) — navbar 2 lớp, filter menu status-only + type-tabs, `List` `.insetGrouped` với section due + date-bucket, FAB, `ContentUnavailableView` cho trạng thái lọc-ra-0-kết-quả. Sub-view `LibraryHeroCard`/`TypeTabButton` private trong cùng file (theo đúng convention `DocumentCard.swift` đã có).
- `Views/Settings/SettingsView.swift` (edit) — nhận `onChangeFolder: () async -> Void`, thêm section "Library".
- `Views/Import/FolderPermissionOnboarding.swift` (edit) — 1 dòng copy.

#### Fix bug Autosave silent-failure (2026-09-01)
- `Services/Protocols/Autosave/AutosaveScheduling.swift` (rewrite) — thêm `AutosaveOutcome` enum (`.saved`/`.failed(message:)`, `Sendable` vì convert `Error` → `String` ngay tại nguồn) + tham số `onResult: @MainActor @Sendable (AutosaveOutcome) -> Void` trên `scheduleChange`.
- `Services/Implementations/Native/AutosaveScheduler.swift` (rewrite) — `performSave`/`flush` gộp chung qua helper `attemptSave(_:)`, luôn gọi `onResult` (thành công lẫn thất bại), không còn `catch { }` rỗng.
- `ViewModels/EditorViewModel.swift` (edit) — `markDirty()` truyền `onResult` gọi `handleAutosaveOutcome`; chỉ tắt `isDirty` khi lưu thành công VÀ content chưa đổi thêm từ lúc bắt đầu lưu (tránh race với edit mới hơn); lưu lỗi → giữ `isDirty` + set `errorMessage`. `flushIfNeeded()` không còn tự ý xoá `isDirty` — để `handleAutosaveOutcome` quyết định.
- `Views/Common/ErrorBanner.swift` (implement — trước là file rỗng TODO Sprint 0.5) — banner đỏ persistent, icon + message + nút tắt.
- `Views/Editor/EditorPlaceholderView.swift` (edit) — hiện `ErrorBanner` khi `vm.errorMessage != nil`, có `.animation(.default, value:)`.

#### PDF Tools mockup + dọn Wireframe (2026-09-01)
- `Wireframe/PDFTools-Mockup-v1.html` (new) — 4 lane (Tools home/Merge/Split/Scan & OCR), 10 khung tổng.
- `Wireframe/` (new folder) — `git mv TuHoSo-Flow-Review.html`, `git mv library-preview.html`; `mv` 5 file `Library-Home-*.html` + `PDFTools-Mockup-v1.html` vào cùng chỗ.

---

## [Unreleased] — 2026-08-31 (Session 6)

Sprint 0.3 fan-out phần **native, không block bởi SPM/SDK license**: PDF Merge/Split, OCR, AirPrint. Cộng `/code-review` full pass + fix hết finding + xử lý build error thật phát sinh khi user add ZIPFoundation. Chốt luôn quy trình làm việc mới — `rule.md` mở rộng 6 mục.

- ✅ **PDF Merge/Split** (`Services/Protocols/PDFTools/PDFMerging.swift`+`PDFSplitting.swift`, `Services/Implementations/Native/PDFKitMerger.swift`+`PDFKitSplitter.swift`) — PDFKit thuần, validate re-open sau khi ghi (§7.3), chạy off-MainActor qua `Task.detached`. Khớp đúng path `PHASE_1_ARCHITECTURE.md` §5.
- ✅ **OCR** (`Models/OCRResult.swift`, `Services/Protocols/Recognition/TextRecognizing.swift`, `Services/Implementations/Native/VisionTextRecognizer.swift`) — `VNRecognizeTextRequest` `.accurate` + language correction, confidence threshold 0.5 (§6.4), chạy off-MainActor. Chưa làm: OCR concurrency queue (giới hạn 2-3 trang, §6.2), searchable-PDF output (§6.5a), `ScanFlowView` UI.
- ✅ **AirPrint** (`Services/Protocols/Print/DocumentPrinting.swift` — protocol tự thêm, không có trong `PHASE_1_ARCHITECTURE.md` §5 gốc — + `Services/Implementations/Native/AirPrintCoordinator.swift`) — `UIPrintInteractionController`, đáp ứng đúng yêu cầu feature trong `Phase0-Implementation-Logic-v2.md` §3.3 (user xác nhận giữ nguyên, không cần khớp cấu trúc `SDK/Mock/MockArtifexPrintRenderer` như `PHASE_1_ARCHITECTURE.md` gợi ý — file đó vẫn là stub, chưa đụng).
- ✅ **DI wiring**: 4 service mới đăng ký vào `DependencyContainer` (`pdfMerger`, `pdfSplitter`, `textRecognizer`, `documentPrinter`).
- ✅ **`/code-review` full pass** trên toàn bộ working-tree diff — 6 finding, tất cả đã fix:
  1. `DOCXCodec.write` phá hỏng ảnh/bảng/format khi save (Session 5's file) → thêm `containsRichContent(in:)` guard, throw `.richContentUnsupported` thay vì âm thầm ghi đè.
  2. `.docx` read path block MainActor (thiếu backgrounding) → fix bằng `Task.detached`, áp dụng luôn cho `write` (code-review không liệt kê nhưng cùng bug).
  3. `AirPrintCoordinator` leak continuation khi 2 lệnh `print()` chồng nhau → guard `continuation == nil`, throw lỗi rõ ràng.
  4. `Task.detached` pattern lặp 3 lần, quên áp dụng cho DOCX → **thử gộp thành helper `runOffMainActor` dùng chung, nhưng gây lỗi build thật** (xem bug build bên dưới) → **revert**, giữ nguyên duplicate — bài học: đề xuất "simplify" của code-review không phải lúc nào cũng an toàn với đúng compiler/toolchain version đang dùng, phải build-verify trước khi tin.
  5. `xmlEscape` không strip control char XML-illegal → thêm `isValidXMLCharacter` filter theo chuẩn XML 1.0.
  6. CRLF sót `\r` khi write → normalize `\r\n`/`\r` → `\n` trước khi split paragraph.
- 🐛 **Bug build thật phát sinh sau khi user add ZIPFoundation SPM** (không phải do `/code-review`, phát hiện qua Xcode Issue Navigator):
  - `PDFKitSplitter`: thiếu `return` trước `Task.detached{...}.value` — "Missing return in instance method".
  - `runOffMainActor` (helper gộp từ finding #4): `Task.detached` trong Swift 6.2 toolchain đòi closure `@isolated(any)`, không nhận `@Sendable` forward qua hàm generic trung gian → lỗi đỏ "Cannot convert value of type... to expected argument type '@isolat...'". **Revert hoàn toàn**, xoá `Extensions/Task+OffMainActor.swift`, quay lại `Task.detached` viết trực tiếp tại từng chỗ.
  - `isValidXMLCharacter` (mới thêm ở fix #5) main-actor-isolated gọi từ `.filter(isValidXMLCharacter)` — cùng bug class với `paragraphXML` trước đó (function reference trần thay vì closure literal) → fix `{ isValidXMLCharacter($0) }`.
  - `Archive(url:accessMode:preferredEncoding:)` deprecated warning vẫn hiện dù đã đổi `try?` — verify qua source ZIPFoundation thật: API hiện tại đúng là `init(url:accessMode:pathEncoding:) throws`, gọi đúng y hệt cách code đang viết → nhiều khả năng chỉ là diagnostic cache cũ của Xcode, chưa xác nhận lại sau Clean Build.
- ✅ **Kiến trúc audit vs `PHASE_1_ARCHITECTURE.md` §5** (toàn bộ 155 file `.swift`): phát hiện thêm — `DOCXCodec.swift` (Session 5) cũng không nằm trong spec gốc (giống AirPrint), là bridge tạm thời chỉ sống trong Mock path; đã thêm doc comment rõ số phận (giữ khi Real SDK về, hoặc revert `.docx` case về placeholder). 4 file stub Compress còn sót từ scaffold gốc mâu thuẫn quyết định "BỎ Compress" đã chốt — **đã note vào `Phase0-Implementation-Logic-v2.md` §7 là sẽ xoá, nhưng CHƯA xoá được** (bị Bash auto-mode classifier chặn `rm`, cần user tự chạy).
- ✅ **`rule.md` tạo mới rồi mở rộng thành 6 mục** (repo root): (1) không code khi chưa chốt, (2) hỏi HTML mockup trước UI, (3) `Phase0-Implementation-Logic-v2.md` là nguồn CHÍNH cho scope MVP — `PHASE_1_ARCHITECTURE.md` chỉ tham khảo pattern kiến trúc, (4) review liên tục qua `/swiftui-expert-skill` + `/code-review`, (5) đảm bảo OCP khi mở rộng, (6) app quan trọng — cẩn thận tối đa, không đoán mò.

**Bước tiếp theo khi resume:**
1. **User tự chạy** `rm` xoá 4 file stub Compress (path đầy đủ trong lịch sử chat/session trước) — bị chặn phía tôi.
2. Clean Build Folder (⇧⌘K) + build lại full, verify hết cả bug build lẫn warning `Archive(...)` deprecated còn không.
3. Unit test cho `PDFKitMerger`/`PDFKitSplitter`/`VisionTextRecognizer` — chưa viết.
4. Sprint 0.3 còn lại: DOCX/PPTX Merge (OOXML — hết block vì ZIPFoundation đã add, nhưng chưa hỏi user để bắt đầu), OCR concurrency queue + searchable-PDF output + `ScanFlowView` UI (cần hỏi mockup HTML trước theo rule.md #2), `FilesProviderExtension` target mới (cần Xcode UI, không sửa `.pbxproj` tay).

---

## [Unreleased] — 2026-08-28 (Session 5)

Item 2 + 3 từ "Bước tiếp theo" Session 4: SwiftLint SDK-boundary rule + real DOCX preview cho Mock. Xóa dead code (`DocumentListView`/`DocumentListViewModel`/`FilesTabView`) đã đề xuất nhưng **user hoãn lại, chưa làm**.

- ✅ **SwiftLint installed + `.swiftlint.yml`** (project root) — 1 custom rule `no_direct_sdk_import` chặn `import Artifex` ngoài `Services/Implementations/SDK/`. `only_rules: [custom_rules]` để không bật hàng loạt rule mặc định gây noise trên codebase chưa từng lint. Verified: flags ở `Views/`, silent ở `Services/Implementations/SDK/`, 0 false positive trên 135 file thật hiện có.
  - **Chưa làm**: wire vào Xcode Run Script build phase — để user tự thêm qua Xcode UI (tránh sửa tay `.pbxproj`, rút kinh nghiệm từ bug orphan GRDB session 4). CLI chạy tay: `swiftlint lint --config .swiftlint.yml "Word Office"`.
- ✅ **`DOCXCodec.swift`** (new, `Services/Implementations/Native/`) — đọc/ghi thật `.docx` qua ZIPFoundation (unzip/zip) + `XMLParser` thuần (không dùng XMLCoder như plan gốc — schema `w:pPr`/`w:rPr` mixed-content không hợp với declarative decoder, XMLParser SAX đơn giản + đủ). Scope: **plain text only**, không giữ bold/italic/underline — vì `EditorPlaceholderView` hiện là `TextEditor` thuần, mọi format bị strip mỗi keystroke (`AttributedString(newValue)`) nên giữ formatting trong codec là phí công.
  - Read: unzip → `word/document.xml` → nối text các `<w:t>` trong từng `<w:p>`, ngăn cách bằng `\n`.
  - Write: tạo package OOXML tối thiểu (`[Content_Types].xml` + `_rels/.rels` + `word/document.xml`) từ scratch, atomic replace file đích.
  - Wired vào `MockArtifexDocumentReader`/`MockArtifexDocumentWriter` case `.docx`; `EditorPlaceholderView` thêm `.docx` vào switch case dùng `TextEditor` thật (trước đó rơi vào `default:` → EmptyStateView placeholder).
  - **PAUSED chờ user add SPM**: `https://github.com/weichsel/ZIPFoundation` vào target "Word Office" qua Xcode UI (giống cách add GRDB trước đây) — hiện `import ZIPFoundation` chưa resolve nên SourceKit báo lỗi cascade toàn module (không phải bug thật, sẽ hết khi add package xong).
- ⏸️ **Cleanup dead code đề xuất nhưng chưa làm**: `DocumentListView.swift` + `DocumentListViewModel.swift` + `FilesTabView.swift` (zero live caller, verified qua grep) — user chọn để sau.

**Bước tiếp theo khi resume:**
1. User add ZIPFoundation SPM package → build verify → test mở 1 file `.docx` thật (vd trong `~/Desktop/TuHoSoTest/`) trong sim, xác nhận đọc/ghi text hoạt động
2. (Optional) User thêm Run Script build phase gọi `swiftlint` trong Xcode nếu muốn chặn lỗi ngay lúc build, không chỉ chạy tay
3. Xóa dead code khi user sẵn sàng (danh sách file ở trên)
4. Sprint 0.3 fan-out (item 1, chưa bắt đầu): `FilesProviderExtension` scaffold, `PDFMerging`/`PDFSplitting`, OCR (Vision), AirPrint wrapper

---

## [Unreleased] — 2026-08-28 (Session 4)

Sprint 0.2 non-SDK **effectively DONE** cả 2 nhóm A + B (trừ UI compose polish + Nhánh 3b UI wire vẫn với user). Session làm song song 4 batches theo mô hình nhánh — mỗi nhánh scope hẹp, cho phép handoff sạch giữa code (tôi) và UI (user). Chốt **English only** cho toàn bộ app + doc comments.

**Trạng thái cuối session:**
- ✅ **Nhánh 1 leaf (5 view atoms)**: `DocumentCard`, `DocumentStatusPicker`, `RemindAtField`, `FolderPermissionOnboarding`, `ReauthorizePermissionCTA`. User redesigned Onboarding + CTA với hero gradient + feature list — final versions live.
- ✅ **Nhánh 1 compose**: `LibraryView` + `RootView` (user owns UI). Session xác lập boundary rõ: tôi align signature (`onChangeFolder: () async -> Void`), user drive design + iterate.
- ✅ **Nhánh 2 unit tests**: 4 test file trong `Word OfficeTests/` với Swift Testing framework — 34+2 test cases (Scanner 7, BookmarkStore 6, MetadataStore 11, LibraryViewModel 10+2). Test target chưa tạo trong `.xcodeproj` — user cần tạo Unit Testing Bundle trước khi ⌘U.
- ✅ **Nhánh 3a services**: DI register 3 service mới (`iCloudImporter`, `documentImporter`, `crashRecoveryScanner`) + `LibraryViewModel.importFiles(from:)` method + `CrashRecoveryScanning` protocol + `CrashRecoveryScanner` impl (scan `Documents/*.autosave.tmp`) + `scenePhase` background flush trong `Word_OfficeApp` (dùng `SessionStore.currentDocument.id` + `AutosaveScheduling.flush(id:)`).
- ✅ **i18n sweep → English only** (~35 chỗ): user-facing strings trong LibraryView + 4 protocol `errorDescription` + doc comments referencing arch terms Vietnamese ("Tủ hồ sơ" → "Library", "diễn biến" → "scenario", "bẫy" → "trap", "nhóm A/B" → "group A/B"). Grep confirm 0 Vietnamese diacritics còn trong `.swift`.
- ✅ **2 bug fix runtime**: `MetadataStoreImpl.decode(from:)` cần `nonisolated` (project bật Default Actor Isolation = MainActor, GRDB closure off-main); typo `x` stray giữa `"""` delimiter trong `dueReminderIDs` SQL.
- ⏸️ **Nhánh 1 compose + Nhánh 3b UI wire vẫn với user**: LibraryView design iteration, `CrashRecoveryBanner` view, wire `AddFileMenu` vào toolbar, `EditorPlaceholderView.onDisappear` flush.
- ⏳ Vẫn chờ external: Bundle ID + Team ID, Artifex license (như session 3).

**Bước tiếp theo khi resume (user pick):**
1. Sprint 0.3 fan-out — services layer tôi làm song song với UI user: `FilesProviderExtension` scaffold, `PDFMerging`/`PDFSplitting`, OCR (Vision), AirPrint wrapper.
2. Cleanup — xoá legacy `DocumentListView`/`FilesTabView` (dead code, replaced bởi LibraryView), thêm SwiftLint rule chặn SDK import ngoài `Services/Implementations/SDK/`.
3. Real DOCX preview cho Mock — nâng qua ZIPFoundation + XMLCoder để test UI trước Artifex license.

---

### 🔨 Code Deliverables

#### Nhánh 1 leaf — 5 view atoms (2026-08-28, morning)
- `Views/Library/DocumentCard.swift` (new) — HStack row với DSDocumentTypeBadge · name/status pill/modified · reminder chip. Stateless, `onTap` callback. Preview 3 states.
- `Views/Library/DocumentStatusPicker.swift` (new) — Menu-based manual status picker. Current status disabled trong menu = "you're here" signal. `sensoryFeedback(.selection, trigger: current)` cho iOS 17+.
- `Views/Library/RemindAtField.swift` (new) — Row + sheet với DatePicker(.graphical). Bell icon toggle "Thêm nhắc" / date + clear button. `.presentationDetents([.medium, .large])`.
- `Views/Import/FolderPermissionOnboarding.swift` (new) — First-run hero (icon 64pt + title + explain + primary CTA). Fake picker/bookmark store inline cho Preview (option A user chọn).
- `Views/Library/ReauthorizePermissionCTA.swift` (new) — Bookmark stale/revoked fallback. 2 CTA: re-grant / change folder.
- `Models/DocumentStatus.swift` (edit) — `displayName` → English (Draft/Reviewed/Signed/Sent).

#### Nhánh 1 compose — LibraryView + RootView (user owns)
- `Views/Library/LibraryView.swift` (new by me, user iterated) — signature `@Bindable viewModel: LibraryViewModel` + `onChangeFolder: () async -> Void`. Handle checking/empty/list states. Toolbar Menu 3-chấm (Rescan / Change folder). Alert từ errorMessage. Context menu status change on card.
- `Views/Root/RootView.swift` (user viết) — switch trên `LibraryStore.folderPermissionState`. Lazy VM init in `.task`. Optional VM pattern.
- Word_OfficeApp — tôi edit rồi revert lại `RootView(container:)` để match user's signature.

#### Nhánh 2 tests — Swift Testing framework (2026-08-28, afternoon)
- `Word OfficeTests/` (new folder) — 4 test file, 34+2 test cases.
- `DocumentLibraryScannerTests.swift` (7 tests) — filter supported kinds, extract kind từ UTI, skip hidden/subdirectory, modifiedAt precision.
- `FolderBookmarkStoreTests.swift` (6 tests) — save/load round-trip, overwrite, delete idempotent, resolve throws cho corrupted data. Unique service per test (UUID) tránh Keychain pollution.
- `MetadataStoreImplTests.swift` (11 tests) — CRUD, fetchMany batch, draftCount, dueReminderIDs sort ASC, reset. Unique temp SQLite path per test.
- `LibraryViewModelTests.swift` (10+2 tests + 5 mocks) — @MainActor suite. Mock `MockBookmarkStore`, `MockScanner`, `MockMetadataStore`, `MockReminders`, `MockImporter` — tất cả `@unchecked Sendable` (single-threaded test flow). Test loadLibrary state transitions, mutations, importFiles delegation.
- **Test target chưa tạo** — user cần Xcode → New Target → Unit Testing Bundle.

#### Nhánh 3a services — Add file + Autosave production (2026-08-28, evening)
- `App/DependencyContainer.swift` (edit) — thêm `iCloudImporter: ICloudPlaceholderImporter`, `documentImporter: DocumentImporter`, `crashRecoveryScanner: CrashRecoveryScanner`. Update `makeLibraryViewModel` pass importer.
- `ViewModels/LibraryViewModel.swift` (edit) — thêm `importer: any DocumentImporting` property + init param + `importFiles(from urls: [URL]) async -> [ImportOutcome]` method. Batch semantics per §5.3 — one failure không kill rest. Set `errorMessage` cho first failure.
- `Services/Protocols/Autosave/CrashRecoveryScanning.swift` (new) — protocol + `CrashRecoveryOrphan` struct + `CrashRecoveryError` enum.
- `Services/Implementations/Native/CrashRecoveryScanner.swift` (new) — scan `Documents/*.autosave.tmp` orphans (string-suffix check). Discard method.
- `App/Word_OfficeApp.swift` (edit) — `@Environment(\.scenePhase)` + `.onChange` handler `handleScenePhaseChange`. Background phase → `container.autosaveScheduler.flush(id: sessionStore.currentDocument.id)`.
- `Word OfficeTests/LibraryViewModelTests.swift` (edit) — thêm `MockImporter` + 2 test case (`importFilesDelegates`, `importFilesSurfacesError`).

#### i18n sweep — English only (2026-08-28, late evening)
- **Views (7 strings)**: `LibraryView` (empty state, toolbar menu, alert title, nav title dynamic "Library · N drafts", context menu section).
- **Protocol errorDescription (14 strings)**: `DocumentImporting` (4), `FolderBookmarkResolving` (4), `FolderPermissionGranting` (3), `MetadataStoring` (3).
- **Runtime error string (1)**: `FolderPermissionPicker` — "Couldn't find a view controller to present from."
- **Doc comments (15+)**: LibraryViewModel, LibraryStore, LibraryEntry, LibraryHeroCopy, FolderPermissionViewModel, LibraryViewModel+Grouping, DocumentLibraryScanner, MetadataStoreImpl, URL+DocumentID, RootView, EditorPlaceholderView, SDKEditorHostView, MockArtifexDocumentReader, MockArtifexDocumentWriter, DependencyContainer, Models/Signature, Views/Signature/SignaturePlacementView, FolderPermissionGranting.
- Brand names kept: "Word Office", "iCloud Drive".

---

### 📚 Documentation & Design Artifacts

#### UC16 first-scan familiarity — chốt design pattern (2026-08-28)
- **Trigger:** user hỏi "làm sao tủ tài liệu thấy thân thuộc khi first-scan" — spec chưa cover first-run experience khi tất cả file default `.draft`.
- **Decision:** Idea 1 + Idea 2:
  - **Idea 1**: sort default `document.modifiedAt` desc + group by 5 `DateBucket` (Today/Yesterday/Previous 7 Days/Previous 30 Days/Older) — Files.app iOS 17 pattern
  - **Idea 2**: hero copy adaptive theo state: `draftCount == totalCount` → "Documents tracked" (welcoming) · `draftCount < totalCount` → "Drafts in progress" (Zeigarnik) · `draftCount == 0` → "All caught up" (celebration) · `entries.isEmpty` → "No documents yet"
- **Backend impact:**
  - `Models/DateBucket.swift` (new) — 5 case + `bucket(for:now:calendar:)` classifier dùng `Calendar.isDateInToday/Yesterday` + day-diff
  - `Models/LibraryHeroCopy.swift` (new) — 4-state enum + English title/subtitle
  - `ViewModels/LibraryViewModel+Grouping.swift` (new) — extension: `heroCopy`, `dueReminderEntries(now:)`, `groupedEntries(now:)` — pure computed views trên `store.entries`
- **View wire pending** — current on-disk `LibraryView` là simplified List; user sẽ quyết wire hero + sections khi iterate design.

#### `library-preview.html` — 7 UI case mockup (2026-08-28)
- Location: `/Users/admin/Desktop/Word Office/Word Office/library-preview.html`
- 7 mockup: `FolderPermissionOnboarding` (light) + `ReauthorizePermissionCTA` (light) + `LibraryView` first-scan (light) + `LibraryView` steady state (dark) + Empty state + Loading skeleton + `RemindAtField` sheet + `DocumentStatusPicker` context menu
- Design pattern: iOS 18 modern — grouped inset cards, adaptive hero với gradient text, section header có count pill chip, radial gradient overlays, hairline borders
- Palette + typography lấy từ `Native-Professional-Workspace-Design-System.md` § 6 + DSSpacing/DSFont tokens — không tự đặt lại

#### `TuHoSo-Flow-Review.md` + `.html` — flow review + UC catalog (2026-08-28)
- Location: `/Users/admin/Desktop/Word Office/Word Office/TuHoSo-Flow-Review.{md,html}`
- HTML có sticky TOC + 5 Mermaid diagrams render inline (CDN `mermaid@10`) + theme-aware:
  1. Journey timeline (linear, 2 Aha moment)
  2. High-level flowchart (branching, tất cả path)
  3. State machine `folderPermissionState`
  4. Sequence UC3 (mở app lần sau)
  5. Sequence UC4 (đổi status)
- 15 use case tổng cộng: 5 spec (UC1-UC5) + 10 potential (UC6-UC15 ⚠️) + UC16 chốt ✅
- Q1-Q10 review table với recommendation từng UC tiềm ẩn (Watch folder? Cleanup orphan metadata? APFS documentIdentifierKey verify? Prompt status sau close editor? …) — chờ user duyệt trước khi lock UC6-UC15

#### HIG audit — 6 findings + fix (2026-08-28)
- Sau khi cài `[[reference-mobile-ios-design-skill]]`, đọc 3 references (`hig-patterns.md`, `ios-navigation.md`, `swiftui-components.md`) rồi audit `library-preview.html`
- Findings + fix: F1 icon-btn 36→44pt (critical, HIG touch target); F2 sheet-close 32pt + hit padding note; F3 add `.refreshable` note; F4 draft hero informational (không tappable); F5 empty state → `ContentUnavailableView` iOS 17+; F6 sheet safe area bottom

#### `~/Desktop/TuHoSoTest/` — test fixtures (2026-08-28)
- 6 real file với UTI hợp lệ để test flow trong sim (drag-drop vào Files.app "On My iPhone"):
  - **3 DOCX** (`org.openxmlformats.wordprocessingml.document`, tạo qua `textutil -convert docx`): `hopdong-abc-2026.docx`, `quy-che-noi-bo-v3.docx`, `de-xuat-du-an.docx`
  - **2 PDF** (`com.adobe.pdf`, tạo qua `cupsfilter -m application/pdf`): `bao-gia-Q3.pdf`, `phu-luc-hopdong.pdf`
  - **1 RTF** (`public.rtf`, textutil): `bao-cao-thang-8.rtf`
- Timestamps trải đủ 5 date bucket: hôm nay / hôm qua / 3 ngày trước / 5 ngày trước / 12 ngày trước / 45 ngày trước
- Dùng để verify UC16 hero adaptive + date bucket grouping khi wire vào LibraryView

#### GRDB SPM orphan reference fix (2026-08-28)
- **Symptom**: `Unable to resolve build file: BuildFile<PACKAGE-TARGET:GRDB-5DC4DB053-dynamic::BUILDPHASE_1::0>` dù đã remove GRDB-dynamic khỏi UI + reset Package Caches
- **Root cause**: user ban đầu add cả `GRDB` (static) + `GRDB-dynamic` (dynamic) product khi Add Package Dependencies → Xcode 26 UI-remove để lại 4 orphan chunks trong `.pbxproj`
- **Fix**: manual xoá qua Edit tool:
  1. Line 11 (`PBXBuildFile section`) — build file entry
  2. Line 45 (`Frameworks build phase`) — files array member
  3. Line 90 (`packageProductDependencies`) — target product ref
  4. Line 398-402 (`XCSwiftPackageProductDependency section`) — product definition
- Kèm xóa `~/Library/Developer/Xcode/DerivedData/Word_Office-*` + `xcuserdata/`
- **Pattern to remember**: SPM package product remove qua Xcode UI thường leaves orphan trong `.pbxproj`. Verify `grep -c "GRDB-dynamic" project.pbxproj` == 0 sau khi remove UI.

#### `mobile-ios-design` skill installed (2026-08-28)
- `npx skills add https://github.com/wshobson/agents --skill mobile-ios-design`
- Symlinked vào Claude Code + Antigravity + Codex + Gemini CLI + Amp
- 3 reference files: `hig-patterns.md`, `ios-navigation.md`, `swiftui-components.md`
- Bổ trợ `[[reference-swiftui-expert-skill]]` — dùng cho HIG patterns; SwiftUI API vẫn tra swiftui-expert-skill
- Memory: `[[reference-mobile-ios-design-skill]]`

---

### 🐛 Bug Fixes

#### `MetadataStoreImpl.decode(from:)` — MainActor isolation blocker (2026-08-28)
- **Symptom**: Build error "Call to main actor-isolated static method 'decode(from:)' in a synchronous nonisolated context".
- **Root cause**: Project sets **Default Actor Isolation = MainActor** (Xcode 26 setting). Class `MetadataStoreImpl` inherits MainActor. Static `decode(from:)` inherits MainActor. `runRead`/`runWrite` closures are `@Sendable` + escape to GRDB actor — calling `Self.decode` from there fails.
- **Fix**: `nonisolated private static func decode(from row: Row)`.
- **Pattern to remember**: any static/nonclass method called from a Sendable/GRDB closure needs `nonisolated` in this project.

#### `dueReminderIDs` SQL literal — stray `x` char
- Typo giữa `"""` delimiter: `     x               """`. Fix bằng cách xoá `x`.

---

### 🏗️ Architecture Decisions

#### Nhánh model — code/UI ownership boundary (2026-08-28)
- **Trigger**: User cho biết đang làm UI ở task khác, không muốn tôi tạo View thêm.
- **Decision**: Chia work thành nhánh scope hẹp — mỗi nhánh có owner rõ ràng (code = tôi, UI compose/design = user). Nhánh 1 leaf & Nhánh 2 tests & Nhánh 3a services thuộc tôi; Nhánh 1 compose polish & Nhánh 3b UI wire thuộc user.
- **Impact**: Không thoả hiệp design decision khi user đang iterate UI. Handoff qua signature contract (VD `LibraryView(viewModel:onChangeFolder:)`) rồi user tự do redesign nội bộ.

#### English only cho toàn bộ app (2026-08-28) — overrides mixed direction
- **Trigger**: User initially confuse "chốt chỉ 1 ngôn ngữ Việt" → tôi hiểu Vietnamese only → sau đó user correct "nhầm, tôi dùng toàn bộ là tiếng anh".
- **Decision**: English only cho user-facing strings + `errorDescription` + doc comments (`///`, `//`). Không dùng String Catalog. Brand names giữ nguyên ("Word Office", "iCloud Drive").
- **Session log memory**: [[feedback-language-english]] persist decision cross-session.

#### Swift Testing framework (Xcode 16+) cho unit tests (2026-08-28)
- **Trigger**: Nhánh 2 batch. Chọn giữa XCTest và Swift Testing.
- **Decision**: **Swift Testing** (`@Test`, `#expect`, `#require`). Ít boilerplate, Xcode 26 default, better async support.
- **Trade-off**: Không Equatable-aware error assertions (`FolderBookmarkError` case `.keychainFailure(OSStatus)` không auto-Equatable → assert type thay vì specific case).

#### `@unchecked Sendable` cho mocks trong LibraryViewModelTests (2026-08-28)
- **Trigger**: Protocol conformance yêu cầu `Sendable`. Mock cần mutable state cho test setup.
- **Decision**: `final class MockX: Protocol, @unchecked Sendable` cho tất cả 5 mock (BookmarkStore, Scanner, MetadataStore, Reminders, Importer). Justify: tests chạy single-threaded từ MainActor, không có concurrent access.
- **Alternative rejected**: actor mocks — sync protocol methods (`loadSaved`, `resolve`) không expressible qua actor cleanly.

---

### 🎯 Sprint 0.2 Gate Status

| Track | Status | Blocker |
|---|---|---|
| Non-SDK backend (nhóm A) | ✅ Session 3 done (19 file) | — |
| Non-SDK UI atomics (Nhánh 1 leaf) | ✅ Session 4 done (5 file) | — |
| Non-SDK UI compose (Nhánh 1 compose) | ⏸️ User owns, iterating | — |
| Non-SDK unit tests (Nhánh 2) | ✅ Session 4 done (4 file, 36 case) | User cần tạo Unit Testing Bundle target |
| Non-SDK Add file + Autosave services (Nhánh 3a) | ✅ Session 4 done | — |
| Non-SDK UI wire (Nhánh 3b) | ⏸️ User task | — |
| Real SDK swap | ⏳ Blocked | Artifex license |
| Round-trip fidelity gate (≥70%) | ⏳ Blocked | Artifex license + real files |

**Sprint 0.2 close condition**: User complete Nhánh 1 compose + Nhánh 3b + Artifex license integration. Then run round-trip fidelity test. Nếu <70% → escalate Artifex support hoặc adjust MVP scope.

---



Scope MVP chốt lại **v2** (12 mục thực tế) sau research UI + product strategy — thêm **Core loop "Tủ hồ sơ"** (Zeigarnik habit loop) làm mục 10, bỏ Pencil/Compress/AI khỏi MVP, viết lại Add file thành folder-picker + auto-scan. Rewrite `PHASE_1_ARCHITECTURE.md` v2.1 → v2.2. Sprint 0.2 nhóm A **backend layer DONE** (19 file mới + 2 file edit), tạm dừng chờ user add file vào Xcode + add GRDB SPM + build verify trước khi vào View layer.

**Trạng thái cuối session:**
- ✅ Scope MVP v2 chốt: 12 mục = 11 mục v2 gốc + Autosave giữ theo user override. Bỏ Pencil/Compress/AI tóm tắt/AI tạo văn bản khỏi MVP
- ✅ Storage strategy chốt: **local only** cho MVP (metadata SQLite trong App Group, FolderBookmark trong Keychain, file gốc ở nguyên chỗ user cấp quyền — không copy). Chấp nhận gỡ app = mất metadata. KHÔNG sync iPhone↔iPad
- ✅ Persistence backend chốt: **GRDB.swift** (SQLite wrapper — query nhanh, Sendable free, App Group trivial)
- ✅ Sprint 0.2 nhóm A backend DONE (7/9 phase): A0 chốt backend, A1 3 model, A2 5 protocol, A3 5 impl, A4 URL+DocumentID extension, A5 LibraryStore + Word_OfficeApp inject, A6 2 VM (LibraryViewModel + FolderPermissionViewModel), A8 DependencyContainer register 5 service + 2 factory
- ⏸️ **PAUSED chờ user**: add 21 file mới vào Xcode target + add GRDB SPM (`https://github.com/groue/GRDB.swift`) + build verify. Checklist đầy đủ trong `GUIDELINE.md` "Where we left off"
- ⏳ Chưa làm: A7 (6 View + wire RootView) + A9 (4 unit test)
- ⏳ Vẫn chờ user: Bundle ID + Team ID (blocker Sprint 0.3 File Provider + App Group entitlement thật), Artifex license (blocker Real SDK swap)

**Bước tiếp theo khi resume:**
1. User add file + GRDB + build clean → gõ *"build clean, tiếp A7"* → làm 6 View + wire RootView
2. Nếu build fail: paste error → tôi fix
3. Alternative: skip Views tạm, sang A9 unit tests trước

---

### 📚 Documentation

#### `Phase0-Implementation-Logic-v2.md` — Nhận file mới từ user (2026-08-27)
- File riêng, không đè lên `Phase0-Implementation-Logic.md` gốc (giữ nguyên làm reference cho Autosave/Pencil/Compress khi Phase 1)
- Nội dung: MVP 11 mục cuối cùng + Phụ lục A (AI tóm tắt → Phase 1) + Phụ lục B (AI tạo văn bản → Phase 2)
- Điểm mới quan trọng: **mục 10 Core loop "Tủ hồ sơ"** (habit loop Zeigarnik) + **mục 4 Add file viết lại** (folder-picker + auto-scan thành luồng chính, thủ công demote thành phụ 4.5)

#### `PHASE_1_ARCHITECTURE.md` — Rewritten v2.1 → v2.2 (2026-08-27)
- Cập nhật scope theo `Phase0-Implementation-Logic-v2.md` + user override giữ Autosave = **12 mục MVP thực tế**
- §1: 12 mục MVP (thêm Tủ hồ sơ #10, giữ Autosave #2)
- §2: 2 assumption mới A11 (core loop = Tủ hồ sơ) + A12 (Add file = folder-scan)
- §3.1.1: 3-store → **4-store** (thêm `LibraryStore`)
- §4.2: bỏ Compress/Pencil khỏi tech stack, thêm metadata store (GRDB/SwiftData/CoreData chọn Sprint 0.2) + folder bookmark storage (Keychain)
- §5: folder structure thêm `Services/Protocols/Library/`, `Services/Implementations/Native/Folder*/DocumentLibrary*/MetadataStore*`, `ViewModels/LibraryViewModel`, `Views/Library/*`
- §6 Sprint reshuffle giữ 5 sprints: 0.2 dài 4 tuần (thêm Tủ hồ sơ), 0.3 bỏ Compress, 0.4 bỏ Pencil (-1 tuần), 0.5 rút (-1 tuần) → tổng vẫn 13 tuần
- §8 Success Criteria thêm 4 dòng Tủ hồ sơ, bỏ dòng Pencil/Compress
- §9 Risks thêm 5 rủi ro mới (bookmark revoke, persistence backend, documentID nhầm path, auto-status suy luận, giả thuyết loop chưa kiểm chứng)
- §10 Handoff Phase 1 (mới): Pencil + Compress + AI tóm tắt

#### `Library-Architecture.md` — Created (2026-08-27)
- File focus cho mục 10 Tủ hồ sơ vì user confused về data storage
- Location: `/Users/admin/Desktop/Word Office/Word Office/Library-Architecture.md` (~450 dòng)
- 10 section: 1 câu tóm tắt, 3 loại data 3 nơi lưu (ASCII diagram), kiến trúc code 3 layer + LibraryStore (ASCII diagram), 5 diễn biến chính step-by-step, protocol interface mẫu, 3 model A1, 5 bẫy dễ mắc, testing, điểm nối với các mục MVP khác, reference nhanh

#### `GUIDELINE.md` — Update (2026-08-27, session 3)
- "Where we left off" rewrite theo scope v2: chia 6 việc chưa làm thành nhóm A (Tủ hồ sơ + folder-scan, ưu tiên cao) + nhóm B (Add file phụ + Autosave)
- Nhóm A liệt kê 9 phase A0–A9 với ~25 task cụ thể (Models/Protocols/Impls/Extensions/Store/VM/Views/DI/Tests)
- Bản đồ tài liệu: trỏ `Phase0-Implementation-Logic-v2.md` làm file chính, bản gốc giữ tham khảo; thêm `Library-Architecture.md` cho phần Tủ hồ sơ
- Convention: thêm 4 rule mới (documentID không path, không auto-status, không push notification, folder bookmark vào Keychain)
- Cheatsheet: thêm câu ngắn cho spike backend / folder-picker / nhóm B
- Update lần 2 cuối session: cập nhật state Sprint 0.2 nhóm A backend DONE + checklist add file/GRDB cho user

---

### 🏗️ Architecture Decisions

#### Chốt MVP scope v2 (12 mục) — 2026-08-27
- **Trigger:** User research UI + product strategy, chốt lại scope trong `Phase0-Implementation-Logic-v2.md`
- **Impact:** Rewrite arch v2.1 → v2.2. Bỏ 4 mục (Pencil/Compress/AI tóm tắt/AI tạo văn bản), thêm 1 mục mới (Tủ hồ sơ), viết lại Add file
- **Core loop MVP thật:** habit loop Zeigarnik ("Tủ hồ sơ") — mở app → tủ tự đầy → thấy tài liệu dở dang → sửa/hoàn thiện → đổi trạng thái → cảm giác "dọn sạch". Chấp nhận rủi ro giả thuyết "user có đủ tài liệu dở dang thường xuyên" chưa kiểm chứng — không đầu tư gamification/streak cho tới khi có data TestFlight
- **User override:** giữ Autosave ở MVP (v2 gốc đẩy Phase 1) → MVP thực tế = 12 mục

#### Storage strategy: local only cho MVP — 2026-08-27
- **Trigger:** User confused về data lưu ở đâu, hỏi rõ; sau khi hiểu chốt "local only cho dễ, đang test MVP"
- **3 loại data / 3 nơi:**
  - Metadata (status/remindAt) → SQLite trong App Group Container (share với FileProvider Sprint 0.3)
  - FolderBookmark → Keychain (survive uninstall, encrypted at rest, KHÔNG UserDefaults)
  - File gốc `.docx`/`.pdf` → **KHÔNG copy vào app**, ở nguyên chỗ user cấp quyền (iCloud Drive/Local/...)
- **Trade-off chấp nhận:** gỡ app = mất metadata; đổi iPhone ↔ iPad = status không sync. Cân đối lại (CloudKit) sau khi có TestFlight data xác nhận core loop chạy. **KHÔNG proactive đề xuất CloudKit/backup khi user chưa hỏi**

#### Chốt GRDB.swift làm persistence backend — 2026-08-27
- **Trigger:** User confirm sau khi tôi so sánh 3 lựa chọn (GRDB / SwiftData / Core Data)
- **Rationale:** Query filter (`remindAt <= now`, `status == .draft` count) chạy hàng chục lần khi mở app → SQLite raw predictable. Sendable free (models thuần struct — không như Core Data `NSManagedObject`). App Group share với FileProvider Sprint 0.3 trivial (1 dòng `DatabaseQueue(path: appGroupURL.appendingPathComponent(...))`)
- **Trade-off chấp nhận:** thêm 1 SPM dep (không đáng kể vì project đã dự kiến ZIPFoundation + XMLCoder)
- **Alternative đã bỏ:** SwiftData (Predicate iOS 17 fail cryptic + App Group phức tạp), Core Data (boilerplate + Sendable wrap)

#### Chốt documentID design: primary APFS documentIdentifierKey + fallback SHA256 relative path — 2026-08-27
- **Trigger:** Spec Phase0-Impl-v2 §10.2 warn "KHÔNG dùng file path làm key" → tôi thiết kế URL+DocumentID extension
- **Primary:** `URL.resourceValues([.documentIdentifierKey]).documentIdentifier` — APFS-native, persistent qua rename/move/edit, chỉ mất khi delete+recreate
- **Fallback:** SHA256 12 bytes của path relative to folder gốc — ổn qua relaunch nhưng broken qua rename
- **Prefix `d`/`p`:** debug DB thấy ngay ID nào từ đâu, không mix silent
- **Escalation trigger:** nếu TestFlight cho thấy user rename thường xuyên → nâng lên bookmark-per-file approach

#### 4-store split (thêm LibraryStore) — 2026-08-27
- Extend §3.1.1 arch v2.2 từ 3-store (Theme/Session/AppState) → 4-store (thêm LibraryStore)
- LibraryStore giữ: `entries: [LibraryEntry]`, `folderPermissionState: FolderPermissionState`, `draftCount` (derived)
- **KHÔNG update AppState.folderPermissionGranted** như arch v2.2 §5 gợi ý — redundant với LibraryStore.folderPermissionState. FolderBookmarkStore.loadSaved() != nil đã cho biết "đã từng cấp quyền". Duplicate → dễ desync
- `FolderPermissionState.checking` case đầu (không `.notGranted`) → tránh flash onboarding trước khi resolve Keychain xong

---

### 🆕 Files Added (Sprint 0.2 nhóm A backend)

**A1 — Models (3 file):**
- `Models/DocumentStatus.swift` — enum 4 case (.draft/.reviewed/.signed/.sent) + displayName + systemImage
- `Models/DocumentMetadata.swift` — struct Codable Sendable Identifiable, id: String bền vững, status/lastOpenedAt/lastModifiedAt/remindAt?
- `Models/FolderBookmark.swift` — struct bookmarkData/displayPath/grantedAt

**A2 — Protocols (5 file trong folder MỚI `Services/Protocols/Library/`):**
- `FolderPermissionGranting.swift` — request folder picker → bookmark + FolderPermissionError
- `FolderBookmarkResolving.swift` — Keychain load/resolve/save/delete + FolderBookmarkError (stale/revoked/keychain/corrupted)
- `DocumentLibraryScanning.swift` — return [LibraryScanEntry] với iCloudDownloadState (ephemeral, không persist)
- `MetadataStoring.swift` — fetch/upsert/fetchMany batch/delete/draftCount/dueReminderIDs/reset + MetadataStoreError
- `RemindScheduling.swift` — thin wrapper dueReminderIDs(at:)

**A3 — Implementations (5 file trong `Services/Implementations/Native/`):**
- `FolderPermissionPicker.swift` — @MainActor NSObject, UIDocumentPickerViewController(.folder) + CheckedContinuation bridge async ↔ delegate, tự tìm topViewController qua key window scene walk
- `FolderBookmarkStore.swift` — SecItem C API wrap kín, update-then-add-on-not-found pattern, kSecAttrAccessibleAfterFirstUnlock, resolve verify TWICE (data + startAccessing), isStale refresh best-effort
- `DocumentLibraryScanner.swift` — FileManager.contentsOfDirectory + resource keys 1 lần (không N+1), UTI filter qua DocumentKind.fromUTI, iCloud state: local/notDownloaded (progress track ở layer cao)
- `MetadataStoreImpl.swift` — GRDB DatabaseQueue (không Pool), schema v1 với 2 index (status, remind_at), DatabaseMigrator sẵn cho v2/v3, raw SQL transparent, MetadataStoreLocator enum riêng để đổi App Group path khi có Team ID (FIXME A6)
- `RemindScheduler.swift` — thin adapter 15 dòng

**A4 — Extension (1 file):**
- `Extensions/URL+DocumentID.swift` — primary APFS documentIdentifierKey (`d<int>`) + fallback SHA256 relative path 12 bytes (`p<hex>`)

**A5 — Store + App (1 file mới + 1 edit):**
- `Models/LibraryEntry.swift` — struct join DocumentRef + DocumentMetadata + iCloudDownloadState, id: String { metadata.id }
- `App/LibraryStore.swift` — @Observable @MainActor, entries + folderPermissionState + draftCount derived + upsert/replaceAll/remove/clear + FolderPermissionState enum (checking/notGranted/granted/revoked)
- `App/Word_OfficeApp.swift` (edit) — thêm @State libraryStore + inject qua .environment

**A6 — ViewModels (2 file):**
- `ViewModels/LibraryViewModel.swift` — coordinator load/setStatus/setReminder/recordOpen, decompose thành joinWithMetadata + sortByDueReminders + persist helpers, first-scan tạo metadata .draft + upsert. Never auto-inferred status
- `ViewModels/FolderPermissionViewModel.swift` — 3 method checkExistingPermission/requestPermission/resetPermission. KHÔNG gọi LibraryViewModel.loadLibrary() trực tiếp — RootView observe qua onChange (decoupled)

**A8 — DI Container (1 edit):**
- `App/DependencyContainer.swift` — thêm 5 service stored (folderPermissionPicker/folderBookmarkStore/documentLibraryScanner/metadataStore/remindScheduler) + preconditionFailure nếu MetadataStoreImpl init throws + 2 VM factory nhận LibraryStore param (makeLibraryViewModel/makeFolderPermissionViewModel)

**Total: 19 file mới + 2 file edit**

---

## 2026-08-26 (Session 2)

Đảo hướng engine (SDK Artifex thay OSS combo) · MVP scope thu gọn 11→10 (dời AI Phase 2) · Sprint 0.1 skeleton hoàn chỉnh + build clean iOS Sim · bắt đầu Sprint 0.2 (Add File flow — 4/10 file done).

**Trạng thái cuối session:**
- ✅ Skeleton Sprint 0.1: 104 Swift files + 52 Asset Catalog colorsets, build clean iOS Sim (0 error, 0 warning), verified app launches trong iPhone 17 Pro sim
- ⏸️ Sprint 0.2 partial: 4 file cho Add File flow đã tạo (`DocumentImporting` protocol, `ICloudPlaceholderImporter`, `DocumentImporter`, `AddFileMenu`) — **CHƯA wire vào DocumentListView + DI**
- ⏳ Chờ user: Bundle ID + team ID (blocker Sprint 0.3 Files Provider), Artifex license (blocker Sprint 0.2 real SDK swap), design system đã có ✓

**Bước tiếp theo khi resume (chi tiết trong `GUIDELINE.md` Phần "Where we left off"):**
1. Wire `AddFileMenu` vào `DocumentListView` toolbar + register `DocumentImporter` trong `DependencyContainer`
2. Crash-recovery scan `.autosave.tmp` + banner
3. Save-on-background lifecycle (scenePhase change → flush autosave)
4. Build verify → tiếp Sprint 0.3 (PDF tools + OCR + AirPrint)

---

### 📚 Documentation

#### `GUIDELINE.md` — Created (2026-08-26)
- User yêu cầu 1 file checklist bám theo bước-bước (không phải essay)
- Location: `/Users/admin/Desktop/Word Office/GUIDELINE.md`
- Nội dung: bản đồ 6 doc, checklist ngày 1 (Xcode integration + build config + Mac Catalyst PoC), tuần 1 (unit tests + audit), Sprint 0.2 preview, cheatsheet đường dẫn + common pitfall (6→10 pitfalls sau các bug hôm nay), 5 milestone checkpoint

#### `PHASE_1_ARCHITECTURE.md` — Rewritten v2 → v2.1 (2026-08-26)
- **v2 (đảo hướng):** Đổi engine strategy từ combo Swift OSS → **SDK thương mại Artifex Smart Office SDK** (main) + Apple native + OSS fill-in. MVP mở rộng scope từ "foundation only 2 tuần" → **11 hạng mục 16 tuần** theo product-strategy.
- **v2.1 (giảm tải):** User chốt Option A — **dời AI khỏi MVP → Phase 2**. MVP còn 10 hạng mục, timeline rút 16 → ~13 tuần.
- **Patch 5 review finding từ swiftui-expert-skill:**
  - C1 Mac Catalyst PoC riêng Sprint 0.1
  - C3 Compile-time `#if USE_MOCK_SDK` (không runtime toggle — nguy hiểm)
  - C4 Swift 6 strict concurrency enabled từ ngày 1
  - C5 Tách god object AppState → `ThemeStore` + `SessionStore` + `AppState` (metadata only)
  - N3 `@SceneStorage` cho sidebar visibility persist
- **7 assumption confirmed:** A1 Artifex ✅ · A2 Mock skeleton chờ license ✅ · A3 iOS 17 ✅ · A5 Cloudflare Workers free tier (giờ Phase 2) ⏸️ · A7 English only MVP ✅ · A6 Bundle ID chờ user ⏳ · A9 Design system đã nhận ✓

#### Đọc `Native-Professional-Workspace-Design-System.md` — 2026-08-26
- User gửi design system v1.2 sau khi chốt architecture v2.1
- Brand: **Professional Cobalt** `#3267E3` (light) / `#5B8CFF` (dark) — không neon, không AI-purple
- 3-layer token: Primitive → Semantic → Component với DS prefix (`Color.dsBrandPrimary`, `DSSpacing.md`, `DSPrimaryButton`)
- 52 semantic color tokens (Brand/Background/Surface/Text/Border/Status/Document/Overlay/Selection/Button)
- iPhone: TabView 2-tab (Files + Tools). iPad: NavigationSplitView 3-column. Editor 75% attention cho content
- Feature-based folder structure §18 — mâu thuẫn với layer-based arch v2.1

#### `README-XCODE-INTEGRATION.md` — Created (2026-08-26)
- Hướng dẫn add 7 folder groups vào Xcode project, enable Swift 6 strict concurrency, tạo 2 build config Mock/Real + 2 scheme, Mac Catalyst PoC
- Location: `/Users/admin/Desktop/Word Office/Word Office/README-XCODE-INTEGRATION.md`

---

### 🏗️ Architecture Decisions

#### Đảo hướng engine: SDK Artifex thay Swift OSS combo (2026-08-26)
- **Trigger:** User chốt "Lấy SDK thương mại theo phase 0" + "Tối ưu theo product-strategy-master theo mvp = 11"
- **Trade-off chấp nhận:** Cost license Artifex vs OSS free, nhưng đổi lấy fidelity ~95% (thay vì 70–90%) và PPTX write (OSS chưa có)
- **Impact:** Rewrite arch v1 → v2, memory `reference_office_engines_ios.md` update từ "Syncfusion/Aspose loại, dùng OSS combo" → "Artifex main engine, native + OSS fill-in"

#### Dời AI khỏi MVP → Phase 2 (2026-08-26 — Option A giảm tải)
- **Trigger:** User "tạm thời phương án A luôn đi, giảm tải"
- **Impact:** Bỏ 11 file/folder AI khỏi skeleton, cắt Sprint 0.5 từ 3 tuần → 1.5 tuần, timeline MVP 16 → ~13 tuần
- **Handoff Phase 2:** AI vẫn là ưu tiên #1 khi Phase 2 mở, backend Cloudflare Workers stack đã research sẵn (`Phase0-Implementation-Logic.md` §11)

#### Structure hybrid — layer-based + DesignSystem/ folder (2026-08-26)
- **Trigger:** User trả lời AskUserQuestion — chọn "Hybrid" trong 3 options
- **Chi tiết:** Giữ layer-based (App/Models/Services/ViewModels/Views) để enforce MVVM+SOLID DIP; thêm `DesignSystem/{Foundations,Components,Styles}/` folder độc lập theo design doc §18
- **Không chọn:** feature-based (khó enforce DIP — VM/View cùng folder dễ import chéo)

#### iPhone navigation: TabView 2-tab Files + Tools (2026-08-26)
- **Trigger:** AskUserQuestion — user để tôi recommend
- **Rationale:** Design doc §5.2 recommend TabView. Tools tab visible bottom = pillar 1 "PDF power tools" hiển thị ngay (không ẩn trong menu)

#### 52 Asset Catalog color sets sinh batch script (2026-08-26)
- Python script generate 52 `.colorset` folder + `Contents.json` với Light/Dark values từ design doc §6
- Đủ cho Sprint 0.1 → 0.5, không phải quay lại tạo colorset mỗi feature

---

### ✅ Code — Sprint 0.1 skeleton (2026-08-26)

**Đã tạo 104 Swift files + 52 colorsets.** Full folder structure hybrid với 40 file real code Sprint 0.1 + 60 file placeholder Sprint 0.2–0.5 (mỗi file có `// TODO Sprint 0.X` header).

Files viết real:

**`App/` (5):**
- `Word_OfficeApp.swift` — @main entry, inject 3 store + DI container qua environment
- `AppState.swift` — @Observable metadata only (launchCount, lastVersion, firstRun)
- `ThemeStore.swift` — @Observable theme + fontSize + accentColor + preferredColorScheme
- `SessionStore.swift` — @Observable currentDocument + isDirty + autosaveStatus (enum)
- `DependencyContainer.swift` — DI factory với `#if USE_MOCK_SDK` compile-time swap Mock↔Real (C3)

**`DesignSystem/Foundations/` (5):**
- `DSColor.swift` — 52 static `Color.dsXxx` map to Asset Catalog names
- `DSFont.swift` — 10 semantic text styles
- `DSSpacing.swift` — xxs=4 → massive=64
- `DSRadius.swift` — small=8, control=10, card=12, large=16
- `DSSize.swift` — touch/button/icon/toolbar dimensions

**`DesignSystem/Components/` (5):**
- `Buttons/DSPrimaryButton.swift` — 50pt height, radius 10, dsBrandPrimary bg
- `Buttons/DSSecondaryButton.swift` — neutral bg + brand text border
- `File/DSFileRow.swift` — 64pt row với icon + name + relative date
- `File/DSDocumentTypeBadge.swift` — document-type color chỉ trên badge/icon
- `Feedback/DSSaveStatus.swift` — subtle save state indicator (idle/pending/saving/saved/failed)

**`Models/` (5):**
- `DocumentKind.swift` — 12 case enum, systemImage per kind
- `DocumentRef.swift` — Identifiable Sendable
- `DocumentContent.swift` — AttributedString wrapper
- `AppTheme.swift` — system/light/dark
- `SortOrder.swift` — 4 case sort options

**`Services/Protocols/` (7):**
- `Document/`: `DocumentSessionManaging`, `DocumentReading`, `DocumentWriting`, `DocumentListing`, `DocumentCreating`, `DocumentExporting`
- `Autosave/AutosaveScheduling`

**`Services/Implementations/SDK/Mock/` (3):**
- `MockArtifexDocumentSessionManager` — dummy session handle
- `MockArtifexDocumentReader` — real read cho RTF/TXT/Markdown (NSAttributedString), placeholder cho Office/PDF
- `MockArtifexDocumentWriter` — mirror

**`Services/Implementations/Native/` (2):**
- `LocalFileServiceImpl` — FileManager list/delete/rename/create + auto-suffix `(2)`, `(3)`
- `AutosaveScheduler` — actor với debounce 2s + hard timer 30s, staging file + atomic rename ready

**`ViewModels/` (3):**
- `DocumentListViewModel` — load/create/delete/rename/sort
- `EditorViewModel` — load/markDirty/flushIfNeeded
- `SettingsViewModel` — version/build info

**`Views/` (7):**
- `Root/RootView.swift` — adaptive TabView (iPhone) vs NavigationSplitView (iPad/Catalyst) với `@SceneStorage` sidebar visibility (N3)
- `Tabs/FilesTabView`, `ToolsTabView`
- `Sidebar/SidebarView`, `DocumentListView` (create sheet + sort menu + swipe delete + error alert)
- `Editor/EditorPlaceholderView` — TextEditor thật cho TXT/RTF/MD, EmptyState cho Office/PDF
- `Settings/SettingsView`, `Common/EmptyStateView`

**`Extensions/` (2):**
- `URL+Documents.swift`, `DocumentKind+UTI.swift` (UTI detection, unwrap safe)

**Removed:** `Word_OfficeApp.swift` + `ContentView.swift` (Xcode template scaffolding)

---

### 🐛 Fix (2026-08-26)

**3 build error phát hiện qua CLI xcodebuild verification:**

1. **`DSSaveStatus.swift`, `DSFileRow.swift`, `EmptyStateView.swift`, `SidebarView.swift`, `EditorPlaceholderView.swift`, `Word_OfficeApp.swift`** — SwiftUI shorthand `.foregroundStyle(.dsXxx)` / `.background(.dsXxx)` / `.tint(.dsXxx)` không compile
   - **Nguyên nhân:** `foregroundStyle`/`background`/`tint` nhận `some ShapeStyle` (không phải `Color` trực tiếp) → Swift compiler không auto-infer shorthand `.dsXxx` từ `Color` extension
   - **Fix:** Batch sed → explicit `Color.dsXxx`. Note vào GUIDELINE cheatsheet
2. **`MockArtifexDocumentReader.swift` + `MockArtifexDocumentWriter.swift`** — `NSAttributedString.DocumentType.rtf`, `NSAttributedString(data:options:documentType:)`, `NSAttributedString.data(from:documentAttributes:)` not available
   - **Nguyên nhân:** Xcode 26 / Swift 6 bật `MemberImportVisibility` upcoming feature — không auto-inherit UIKit từ Foundation
   - **Fix:** Add `import UIKit` explicit vào 2 file
3. **`DocumentKind+UTI.swift`** — `type == .init(filenameExtension: "md")` không compile (`UTType(filenameExtension:)` return `UTType?`)
   - **Fix:** Đổi sang `if let mdType = UTType(filenameExtension: "md"), type == mdType { return .markdown }`

**1 Xcode ↔ Simulator handshake bug (không phải bug code):**
- User gặp "Simulator device failed to launch com.app.word.office.Word-Office" + NSPOSIXErrorDomain Code 3
- Root cause: Xcode 26 race condition với sim ở half-boot state
- Verify: `simctl launch` manual thành công, PID 34836 returned, log confirmed "Launch successful"
- Note vào GUIDELINE cheatsheet với 5-step fix

---

### ✅ Code — Sprint 0.2 partial (2026-08-26)

**4/10 file cho Add File flow, dừng theo yêu cầu user "từ từ tạm thời đến đó":**

1. `Services/Protocols/FileIO/DocumentImporting.swift` (NEW) — protocol + `ImportOutcome` + `ImportError` enum
2. `Services/Implementations/Native/iCloudPlaceholderImporter.swift` (FILLED) — actor wrapper `NSMetadataQuery` cho iCloud placeholder detect + download (§5.2)
3. `Services/Implementations/Native/DocumentImporter.swift` (NEW) — orchestrator: security-scoped access + iCloud download + UTI validate + copy sandbox + auto-suffix duplicate
4. `Views/Import/AddFileMenu.swift` (FILLED) — `.fileImporter` với `allowsMultipleSelection: true` + `supportedTypes` (8 UTI)

**CHƯA làm (resume từ đây):**
- Wire `AddFileMenu` vào `DocumentListView` toolbar (thay button + sheet hiện tại thành menu with Create/Import)
- Register `ICloudPlaceholderImporter` + `DocumentImporter` trong `DependencyContainer`
- Update `DocumentListViewModel` — add `importFiles(from urls: [URL])` calling `DocumentImporter`
- Crash-recovery: scan `.autosave.tmp` khi launch + `CrashRecoveryBanner` view
- Lifecycle save: `scenePhase` change → `flushIfNeeded` (in EditorPlaceholderView + Word_OfficeApp)
- Batch import UI feedback (success N / failed N với reasons)
- Build verify

---

### 🧠 Memory Updates (2026-08-26)

| File | Change |
|---|---|
| `reference_office_engines_ios.md` | Rewrite: từ "Syncfusion/Aspose loại, dùng OSS combo" → "Artifex main engine, native + OSS fill-in cho OCR/merge/split/AI/file-provider" |
| `MEMORY.md` | Update pointer cho reference-office-engines-ios |
| `project_word_office.md` | Cập nhật state — Sprint 0.1 done + Sprint 0.2 partial (session 2) |

---

---

### 📚 Documentation

#### `CHANGELOG.md` — Created (2026-08-25)
- Tạo file changelog này theo yêu cầu user, ghi lại toàn bộ lịch sử session

#### `PHASE_1_ARCHITECTURE.md` — Updated (2026-08-25, lần 2)
- **Section 2 (Assumptions):** Cập nhật A6 → engine document đã chốt combo Swift open source (thay vì "chờ research")
- **Section 11 (Handoff Phase 2):** Rewrite hoàn toàn — bổ sung kết quả research Syncfusion/Aspose (đều không dùng được), liệt kê combo native OSS thay thế với link GitHub từng thư viện, ghi rõ preservation ceiling 70-90% DOCX / 60-80% XLSX / 50-70% PPTX

#### `PHASE_1_ARCHITECTURE.md` — Created (2026-08-25, lần 1)
- Tài liệu ~470 dòng markdown, chuẩn hoá toàn bộ kế hoạch Phase 1
- Nội dung:
  1. Mục tiêu Phase 1 (foundation only, no Office edit)
  2. Assumptions (8 giả định, đánh dấu cái nào cần confirm)
  3. Scope IN/OUT rõ ràng (IN: app shell + document mgmt + TXT/RTF editor + settings; OUT: DOCX/XLSX/PPTX/PDF/OCR/AI/Cloud/FaceID/etc.)
  4. Tech Stack (Swift 6 + SwiftUI + @Observable, zero third-party)
  5. Nguyên tắc MVVM + SOLID mapping từng principle
  6. Folder structure chi tiết (~30 file)
  7. Layer details với code example (Models / Services protocols / ViewModels / App entry / Views)
  8. Task checklist 4 sprints (8-12 ngày solo)
  9. Testing strategy (unit tests, coverage >70% VMs)
  10. Success criteria (12 checklist item)
  11. Handoff Phase 2 (add format = tạo Reader/Writer conform protocol)
  12. Open questions (6 câu cần user quyết trước khi code)
- Location: `/Users/admin/Desktop/Word Office/PHASE_1_ARCHITECTURE.md`

---

### 🔍 Research

#### Syncfusion iOS/Swift feasibility research — Completed (2026-08-25)
- **Trigger:** User yêu cầu research sâu về Syncfusion sau khi tôi khuyến nghị (sai) là "Syncfusion free tier"
- **Method:** Fork subagent research độc lập, WebSearch + WebFetch trên syncfusion.com docs, license page, và forums
- **Verdict:** **Syncfusion KHÔNG dùng được cho SwiftUI iOS app**
  - Lý do: Syncfusion chỉ ship .NET / Xamarin / .NET MAUI SDK cho document processing (DocIO / XlsIO / Presentation) — không có Swift native SDK
  - Community License điều kiện hào phóng (<$1M revenue, ≤5 devs, ≤10 employees, ≤$3M raised) — **nhưng vô nghĩa vì không có Swift SDK**
- **Bonus finding — Aspose cũng loại:** "Aspose Swift SDK" thực chất là REST API wrapper (gửi file lên cloud Aspose), vi phạm nguyên tắc "on-device" trong brief
- **Alternative recommended:** Combo native Swift open source
  | Format | Thư viện | License |
  |---|---|---|
  | DOCX | SwiftDocX | MIT |
  | XLSX | CoreXLSX (read) + XLKit (write) | Apache 2.0 |
  | PPTX | PPTXKit (read) + custom writer | MIT |
  | Legacy DOC/XLS/PPT | OLEKit + DocReader (read-only) | ? |
  | Encrypted OOXML | CryptoOffice | Apache 2.0 |
  | PDF | Apple PDFKit | native |
- **Preservation ceiling:** 70-90% DOCX / 60-80% XLSX / 50-70% PPTX với combo trên. Không có cách lên 95%+ mà vẫn native + on-device + free
- **Impact:** Sửa lại PHASE_1_ARCHITECTURE.md §11 (Handoff Phase 2), lưu memory `reference-office-engines-ios`

#### Competitor analysis — BEGAMOB (2026-08-25)
- **Trigger:** User đề cập app "begamod" (thực ra là BEGAMOB), gửi App Store link `id6759957263` và 3 screenshot editor UI của họ
- **Findings:**
  - Developer: BEGAMOB GLOBAL LIMITED
  - Size: **128.9 MB** (rất nặng cho app iOS bình thường 10-30MB)
  - Support: DOC/DOCX/XLS/XLSX/PPT/PPTX + PDF edit, native UI
  - Pricing: Free download, subscription $1.99-$9.99/tuần
  - Rating: 4.7★ (~1000 ratings)
- **Đoán cách BEGAMOB làm:**
  - UI hoàn toàn native (không phải WebView) → **KHÔNG embed OnlyOffice**
  - Nhiều khả năng: parse file → convert sang model nội bộ → editor SwiftUI/UIKit thuần → serialize lại (có thể mất định dạng phức tạp)
  - Round-trip fidelity ước tính 70-90% (khớp con số tôi đưa ra cho combo Swift OSS)
- **Insight:** Bạn hoàn toàn làm được như BEGAMOB với combo Swift open source

#### Feasibility analysis — DOCX/XLSX/PPTX editing on iOS (2026-08-25)
- **Trigger:** User hỏi "phần Core editing DOC/DOCX, XLS/XLSX, PPT/PPTX có xử lý thuật toán edit được không"
- **Kết luận:**
  - DOCX/XLSX/PPTX = OOXML (ZIP + XML), spec ECMA-376 ~5000 trang
  - DOC/XLS/PPT (legacy) = binary CFBF/OLE2, khó gấp 3-4 lần OOXML
  - **Không có "thuật toán edit đơn giản"** — Microsoft mất 30+ năm build
  - 4 con đường khả thi được liệt kê:
    - Path A: Native-first (PDF + RTF + TXT + DOCX read-only) — 70-90% preservation
    - Path B: Commercial SDK (Aspose/Syncfusion) — 95-98%, đắt hoặc không viable
    - Path C: Embed OnlyOffice WebView — 90-95%, license phức tạp
    - Path D: Hybrid (native + fallback)

---

### 🏗️ Architecture Decisions

#### Chọn kiến trúc MVVM + SOLID (2026-08-25)
- **Decision:** Áp dụng **MVVM + SOLID** cho toàn bộ codebase Word Office
- **Trigger:** User yêu cầu "apply MVVC, solid principles" (MVVC → hiểu là MVVM)
- **Override:** Skill `swiftui-expert-skill` mặc định KHÔNG enforce architecture. User override rule này chỉ cho project này.
- **Chi tiết:**
  - **M (Model):** Pure struct/enum, Codable, Equatable, Hashable
  - **V (View):** SwiftUI, chỉ presentation, không business logic, không import Foundation-internals
  - **VM (ViewModel):** `@Observable @MainActor` class, không import SwiftUI, expose state cho View
  - **S (Service):** Protocol-based, concrete impl inject qua init (DIP)
  - **SOLID mapping:**
    - SRP: 1 VM = 1 màn hình / 1 flow
    - OCP: Add format DOCX = tạo `DocxReader: DocumentReading`, không sửa VM
    - LSP: Mọi impl swappable, test dùng mock
    - ISP: Tách nhỏ protocol (`Reading` / `Writing` / `Listing` riêng, không gộp god protocol)
    - DIP: VM phụ thuộc protocol, không phụ thuộc concrete class
- **Saved to memory:** `feedback_architecture_swiftui.md`

#### Chọn Deployment Target (2026-08-25) — PENDING
- Đề xuất iOS 17.0+ (dùng `@Observable`, `SwiftData`, `NavigationSplitView`)
- **User chưa confirm** — 1 trong 6 Open Questions

#### Chọn engine document Phase 2+ (2026-08-25)
- **Iteration 1 (SAI):** Đề xuất Syncfusion free tier — tôi giả định nó có Swift SDK
- **Iteration 2 (SỬA):** Sau research → chọn combo native Swift open source (SwiftDocX + CoreXLSX + XLKit + PPTXKit + PDFKit)
- **Preservation ceiling chấp nhận:** 70-90% DOCX / 60-80% XLSX / 50-70% PPTX

#### Phase 1 = Foundation only (2026-08-25)
- **Decision:** Phase 1 chỉ làm app shell + TXT/RTF/Markdown editor + file mgmt, KHÔNG code Office format editing
- **Lý do:**
  1. Kiến trúc phải đúng trước, prove với format đơn giản
  2. Mỗi Office format là 1 sprint riêng (DOCX 3 tuần, XLSX 5 tuần, PPTX 6 tuần)
  3. Có app demo sau 2 tuần thay vì 20+ tuần
- **Chờ:** Design system từ user + trả lời Open Questions

---

### 📖 Skill Reference Reading

#### `SKILL.md` — Read (2026-08-25)
- Đọc entry point của `swiftui-expert-skill`
- Tổng hợp Topic Router (25 chủ đề), Correctness Checklist, Task Workflow
- Location: `~/.agents/skills/swiftui-expert-skill/SKILL.md`

#### `latest-apis.md` — Read (2026-08-25)
- Reference bắt buộc đọc đầu tiên cho mọi task SwiftUI
- Key takeaways cho Word Office:
  - iOS 17+: `@Observable` + `@State` + `@Bindable`
  - iOS 16+: `NavigationSplitView` thay `NavigationView`
  - iOS 26+: `TextEditor(text: $attributedString)` — native rich text
  - Deprecated cần tránh: `NavigationView`, `ObservableObject`, `foregroundColor`, `accentColor`, `cornerRadius`, `onChange(of:perform:)`, `tabItem`
- Location: `~/.agents/skills/swiftui-expert-skill/references/latest-apis.md`

#### `state-management.md` — Read (2026-08-25)
- Đọc theo lựa chọn user ("phần 1 cho tôi trước đã")
- Key takeaways cho Word Office:
  - `@Observable @MainActor` cho tất cả class VM
  - `@ObservationIgnored @AppStorage` khi ở trong `@Observable` class
  - Types phải `Equatable` cho property hay write (tránh re-invalidation)
  - `@Bindable` cho `@Observable` inject từ parent
  - `@Environment(AppState.self)` cho shared state
  - Không truyền value như `@State` trong child view
  - KeyPath binding `$model[key]` thay vì `Binding(get:set:)` closure
- Location: `~/.agents/skills/swiftui-expert-skill/references/state-management.md`

---

### 📥 Product Requirements

#### Đọc `product-description.md` — 2026-08-25
- Source: `/Users/admin/Downloads/product-description.md`
- Tổng hợp product brief cho app Word Office:
  - **Positioning:** Office/Word editor thiết kế native cho từng thiết bị Apple, không phải app iPhone phóng to
  - **USP core:** On-device processing (không upload cloud), giá minh bạch không dark pattern
  - **Persona anchor:** Dân chuyên nghiệp 35-44 tuổi (22-30% userbase competitor), 2 nhánh JTBD: (a) dùng iPad Pro như laptop, (b) freelancer/SMB
  - **Persona gián tiếp:** 55+ (22-26% userbase, hưởng lợi từ minh bạch/dễ dùng)
  - **Tính năng cốt lõi:** DOCX/XLSX/PPTX edit + PDF view/convert + iPad multi-pane UI + OCR + PDF tools + e-signature + AI + Face ID lock + free trial minh bạch
  - **Nguồn data:** Sensor Tower 01/08/2025-31/07/2026 US + 80+ review competitor thật
- **Saved to memory:** `project_word_office.md` với pointer tới file gốc

---

### 🛠️ Environment Setup

#### `swiftui-expert-skill` — Installed (2026-08-25)
- **Command:** `npx skills add https://github.com/avdlee/swiftui-agent-skill --skill swiftui-expert-skill`
- **Location:** `~/.agents/skills/swiftui-expert-skill/`
- **Symlinked into:** Claude Code, Antigravity, Codex, Gemini CLI, Amp, Antigravity CLI (+12 more)
- **Contents:** SKILL.md + 25 reference files + 2 Python scripts (record_trace, analyze_trace) + assets
- **Security check:** Gen Safe, Socket 0 alerts, Snyk Low Risk
- **Saved to memory:** `reference_swiftui_expert_skill.md`

#### Node.js — Installed (2026-08-25)
- **Command:** `brew install node`
- **Version:** node v26.7.0, npm 11.19.0, npx 11.19.0
- **Note:** Node build ẩn `Single Executable Application` và `Temporal support` vì shared libnode/ICU

#### Homebrew — Installed (2026-08-25)
- **Command:** `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **Version:** Homebrew 6.0.19
- **Location:** `/opt/homebrew/bin/brew`
- **PATH added:** `/Users/admin/.zprofile`
- **Note:** Quá trình có 1 lần gặp lỗi RPC failure khi tải, sau đó tự retry và thành công

#### Xcode project "Word Office" — Existed (before 2026-08-25)
- **Location:** `/Users/admin/Desktop/Word Office/`
- **Trạng thái ban đầu:** Template mặc định Xcode (Word_OfficeApp.swift + ContentView.swift với "Hello, world!")
- **Không thay đổi trong session này** — chưa code bất kỳ file source nào

---

### 🧠 Memory Saves

Session này save 5 file memory vào `~/.claude/projects/-Users-admin/memory/`:

| File | Type | Nội dung |
|---|---|---|
| `MEMORY.md` | Index | Index tổng hợp pointer tới 5 file memory |
| `project_word_office.md` | project | Context project, link đến product brief |
| `feedback_architecture_swiftui.md` | feedback | Quyết định MVVM + SOLID (override skill default) |
| `feedback_workflow_step_by_step.md` | feedback | User prefer step-by-step, read reference trước khi code, response Vietnamese |
| `reference_swiftui_expert_skill.md` | reference | Location + capabilities của skill đã cài |
| `reference_office_engines_ios.md` | reference | Syncfusion/Aspose bị loại, dùng combo Swift OSS |

---

## Legend

- 🛠️ **Environment Setup** — Cài đặt công cụ, dependency
- 📥 **Product Requirements** — Đọc/nhận yêu cầu sản phẩm
- 📖 **Skill Reference Reading** — Đọc tài liệu tham khảo
- 🏗️ **Architecture Decisions** — Quyết định kiến trúc
- 🔍 **Research** — Nghiên cứu công nghệ/đối thủ
- 📚 **Documentation** — Tạo/sửa tài liệu
- 🧠 **Memory Saves** — Ghi memory để phiên sau nhớ
- ✅ **Code** — Viết code (chưa có trong session này)
- 🐛 **Fix** — Sửa bug/finding
- ⚠️ **Correction** — Sửa lại quyết định/thông tin sai trước đó

---

*File này sẽ được cập nhật liên tục ở các session sau. Mỗi session mới nên thêm entry ở top với timestamp và nhóm theo category.*
