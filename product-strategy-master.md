# Định vị sản phẩm, tính năng, và thứ tự phát triển

Gộp lại từ 3 vòng nghiên cứu trước (competitor analysis, deep-dive iPad/Fold, feature full audit) + các ý tưởng bổ sung, thành một bản định hướng sản phẩm duy nhất: định vị là gì, nhắm ai trước, USP nào là cốt lõi, và phát triển tính năng nào trước — sau.

- **3** đối thủ đã phân tích trực tiếp
- **4** USP pillar
- **3** giai đoạn roadmap
- Cập nhật: **26/08/2026**

---

## 1. Định vị sản phẩm

> Một app Office/Word editor được **thiết kế thật** cho từng thiết bị Apple — không phải app iPhone phóng to lên iPad — xử lý tài liệu **ngay trên máy**, đi kèm bộ công cụ PDF đầy đủ mà không app nào trong 3 đối thủ trực tiếp đã nghiên cứu có, và giá minh bạch không dark pattern. Giải quyết trọn vòng đời tài liệu (soạn → xử lý PDF → ký → lưu trữ an toàn), thay vì chỉ dừng ở "đọc và sửa cơ bản" như 3 đối thủ đang làm.

**Tagline:** "Made for iPad, not scaled from iPhone" · "Your documents never leave your device" · "No paywall surprises"

### Đối thủ đang định vị này chống lại ai

**Office Word: Edit Document** — *Mới, update liên tục*
- Publisher: BEGAMOB GLOBAL LIMITED
- Rating: 4.68★ (1.000) · Ra mắt: 04/2026 · Free trial: Không
- **Điểm yếu:** không có trial rõ ràng, charge ngay — nguồn gốc nhiều review "not free"; publisher là app-factory 8 app đa ngành, không chuyên Office.

**Office Word: Edit Word Document** — *Không update >1 năm*
- Publisher: Rhophi Analytics LLP
- Rating: 4.63★ (9.413) · Ra mắt: 02/2023 · Free trial: Có (3 ngày)
- **Điểm yếu:** nhiều rating nhất nhóm nhưng đã ngừng cập nhật hơn 1 năm — dễ bị vượt qua bằng maintain đều đặn.

**Word Editor: Docs & Docx Files** — *Update liên tục*
- Publisher: RHO APPS / RHO DEVELOPERS LLC
- Rating: 4.70★ (1.378) · Ra mắt: 11/2024 · Free trial: Có (3–7 ngày)
- **Điểm yếu:** cùng nhóm publisher "Rho" với app #2 (dùng chung ảnh/template marketing) — sản phẩm gần như bản sao, không có khác biệt rõ.

---

## 2. Người dùng mục tiêu

Tập trung vào **1 persona duy nhất** — theo data thật từ Sensor Tower (User Breakdown by Age, 01/08/2025–31/07/2026, US, cả 3 đối thủ), 35–44 là nhóm tuổi đông nhất thật (22–30%), không còn là suy đoán từ vài review.

### 🟢 Anchor — có data thật
### Dân pro 35–44

> "Tôi cần xử lý tài liệu công việc ngay trên điện thoại/iPad, đủ tin cậy để thay một phần công việc trên máy tính."

- Nhóm tuổi đông nhất thật ở cả 3 đối thủ (Sensor Tower) — không còn là suy đoán từ vài review
- 2 biến thể JTBD trong cùng persona: **(a)** doanh nhân/dân pro dùng iPad Pro thay laptop để xử lý văn bản — cần multitasking/Pencil/keyboard, đây là target chính cho iPad-native UI; **(b)** freelancer/chủ SMB — cần hợp đồng, invoice, e-signature nhanh gọn
- Sẵn sàng trả Pro tier — khớp trực tiếp USP pillar 01, 04

**Nguồn data demographic:** Sensor Tower — "User Breakdown by Age", 01/08/2025–31/07/2026, US, Any Gender, Any Age (ảnh chụp màn hình người dùng cung cấp 25/08/2026). Giới tính khá cân bằng ở cả 3 app (49–55% nam tuỳ app) — không cần thiết kế lệch giới. Lưu ý: data chỉ đại diện thị trường US; nếu nhắm global cần kiểm tra lại theo từng quốc gia.

---

## 3. 4 trụ cột USP

1. **Bộ công cụ PDF trọn vẹn** — OCR, merge/split/compress, e-signature, watermark — giải quyết trọn vòng đời tài liệu thay vì chỉ "xem và sửa cơ bản". *(Cả 3 đối thủ: 0/6 tính năng này)*
2. **Minh bạch & an toàn dữ liệu** — free trial rõ ràng, huỷ 1 chạm, autosave chống mất dữ liệu, Face ID khoá app, xử lý on-device — không upload tài liệu đi đâu. *(Cả 3 đối thủ: nguồn gốc >70% review 1★ chính là nhóm này)*
3. **AI thật sự hữu ích** — tóm tắt tài liệu dài, viết lại đoạn văn, hỏi-đáp nội dung file — đúng việc AI làm tốt nhất cho document editor. *(Cả 3 đối thủ: chỉ 1 app có nhắc mơ hồ "AI-assisted formatting")*
4. **Mô hình giá linh hoạt** — free thật cho tác vụ cơ bản + Pro subscription rõ giá cho dân pro/freelancer + gói Family Sharing/Team-seat cho nhóm nhỏ — thay vì chỉ 1 tier cá nhân dạng weekly như cả 3 đối thủ. *(Cả 3 đối thủ: chỉ bán 1 tier cá nhân, ưu tiên gói tuần)*

---

## 4. Roadmap phát triển — 3 giai đoạn

> **MVP đã mở rộng đáng kể (26/08/2026):** theo yêu cầu mới nhất, MVP giờ gồm cả OCR, iPad-native UI, merge/split/compress, e-signature/watermark, note/comment và AI — vốn trước đây trải dài qua Phase 2–3. Đây là MVP "đầy đặn" hơn nhiều so với bản gốc, nên mốc thời gian bên dưới đã giãn ra tương ứng (1–5 tháng thay vì 1–3) — cân nhắc lại timeline thật với team dev vì khối lượng việc đã tăng đáng kể.

### Phase 0 — MVP · Tháng 1–5

| Tính năng | Ghi chú | Vì sao |
|---|---|---|
| Core editing DOC/DOCX, XLS/XLSX, PPT/PPTX, xem & convert PDF | | Table-stakes — không có thì không vào được thị trường |
| Autosave + crash-recovery | | Đúng review thật "crash mất 4 giờ làm việc" |
| Kiến trúc layout adaptive (size classes/NavigationSplitView) ngay từ đầu | | Nền tảng dùng lại được cho iPad-native VÀ iPhone Fold sau này — không phải làm lại |
| Files app provider + AirPrint | | Chi phí kỹ thuật thấp (API iOS sẵn có), tăng cảm giác "app native" |
| Add file — import từ Local + iCloud | ý mới | Điểm vào tối thiểu để có tài liệu mà thao tác — Dropbox/Google Drive mở rộng ở Phase 2 |
| iPad multi-pane UI thật + Apple Pencil + keyboard shortcuts | chuyển từ Phase 2 | Nhắm thẳng doanh nhân/dân pro dùng iPad Pro xử lý văn bản thay laptop — nhánh (a) của persona anchor |
| OCR — scan giấy thành văn bản | chuyển từ Phase 2 | Tính năng PDF-tool giá trị cao nhất, dùng hàng ngày |
| Merge / Split / Compress — Word, PDF, PowerPoint | chuyển từ Phase 2, mở rộng | Merge/compress PPTX khả thi tương đương PDF (gộp slide, nén ảnh nhúng) — không rào cản kỹ thuật để loại PPT ra; Split bổ sung theo yêu cầu 26/08 |
| Note / comment dạng text (không cần Pencil) | ý mới | Bổ sung cho Apple Pencil — annotate bằng gõ text/để lại comment ở lề trang, tiện hơn khi không cầm Pencil |
| E-signature + watermark | chuyển từ Phase 3 | Hoàn thiện nhánh (b) freelancer/SMB trong persona anchor 35–44 |
| AI tóm tắt / viết lại / hỏi-đáp tài liệu | chuyển từ Phase 3 | USP pillar 03 — chưa ai trong nhóm có thật |

### Phase 2 · Tháng 5–7

| Tính năng | Ghi chú | Vì sao |
|---|---|---|
| Home widget + Siri Shortcuts | | Tăng engagement, cảm giác app "thuộc về hệ điều hành" |
| Add file — mở rộng sang Dropbox/Google Drive | ý mới | Mở rộng từ Local/iCloud đã có ở MVP, không phải table-stakes ngày 1 |
| Face ID/Touch ID khoá app | chuyển từ MVP | Tính năng bảo mật cơ bản — **cập nhật 26/08: static analysis phát hiện cả Word Office lẫn A1 đều import `LAContext` (LocalAuthentication) ngay trong binary chính, nhiều khả năng đã có Face ID/Touch ID ở đâu đó trong app (chưa rõ khoá toàn app hay chỉ 1 hành động cụ thể) — không còn chắc là "0/3" như ghi trước đây. Vẫn giữ ưu tiên Phase 2, chỉ không dùng "đối thủ chưa ai có" làm lý do nữa** |
| Vertical template cho freelancer (invoice/hợp đồng) | ý mới | Phục vụ nhánh (b) của persona anchor 35–44 — freelancer/SMB |

### Phase 3 — Khám phá · Tháng 7–12+

| Tính năng | Ghi chú | Vì sao |
|---|---|---|
| App macOS thật (Mac Catalyst) + Handoff | ý mới | 0/3 đối thủ có app macOS thật — cơ hội trống hoàn toàn |
| Gói Family Sharing / Team-seat | ý mới | Mô hình giá khác biệt, giảm churn so với chỉ bán 1 tier cá nhân |
| Stage Manager, external display, trackpad polish | | Hoàn thiện trải nghiệm cho nhóm dùng iPad Pro nghiêm túc |
| Layout iPhone Fold — chốt theo spec chính thức khi Apple công bố (dự kiến 09/2026) | | First-mover — chưa app nào trong ngành chuẩn bị cho form-factor này |
| Định vị "on-device, không upload cloud" thành thông điệp marketing chính | ý mới | USP pillar 02 — khai thác cho nhóm business/legal nhạy cảm dữ liệu |
| visionOS — đọc/annotate tài liệu dạng spatial | ý mới, blue ocean | Rủi ro cao, audience nhỏ — chỉ làm nếu có bandwidth dư |
| Cân nhắc mở rộng Android | ý mới | Ngoài phạm vi nghiên cứu này (chỉ có dữ liệu iOS) — đánh giá riêng khi cần |

---

## 5. Bản đồ cạnh tranh — tóm tắt nhanh

| Trục | 3 đối thủ hiện tại | Sản phẩm của bạn (mục tiêu) |
|---|---|---|
| Core editing (Word/Excel/PPT/PDF) | Có cả 3 | Có — bắt buộc từ MVP |
| iPad native UI + Apple Pencil/keyboard | 0/3 | **MVP** |
| PDF power tools (OCR/merge/split/compress/e-sign/watermark) | 0/3 | **MVP** |
| Autosave / chống crash mất dữ liệu | 0/3 quảng cáo | **MVP** |
| AI thật (tóm tắt/viết lại/Q&A) | 0/3 | **MVP** |
| App macOS thật + Handoff | 0/3 | Phase 3 |
| iPhone Fold-ready | 0/3 (chưa ai chuẩn bị) | Phase 3 |
| Gói Family/Team | 0/3 | Phase 3 |

---

## 6. Logic tham khảo từ đối thủ (static analysis IPA thật)

> Nguồn: `Artifex-SODK-Analysis.md` + `Feature-Integration-Comparison.md` (cùng thư mục `Competitor/`) — đọc trực tiếp từ IPA của đối thủ #1 (Word Office/Begamob) và đối thủ #2 (Word Editor–A1/Rho) bằng `otool`/`nm`/plist, không phải suy đoán từ App Store listing hay marketing copy. Đây là **logic kiến trúc** đáng cân nhắc học theo, không phải "sao chép feature".

| # | Logic quan sát được | Ai đang làm | Áp dụng vào đâu trong roadmap |
|---|---|---|---|
| 1 | Paywall render từ config từ xa (`productID`/`title`/`subtitle`/`isSpecial`), không hardcode UI trong app | Word Office — 7 biến thể `iap_v1`–`iap_v7` cùng tồn tại, chọn qua config | Pillar 4 + Phase 0 — build màn paywall data-driven ngay từ MVP dù ngày 1 chỉ bán 1 gói, để sau này test Free/Pro/Family không cần chờ Apple review |
| 2 | Bọc toàn bộ ads/tracking/remote-config sau 1 lớp interface nội bộ riêng, code app không gọi thẳng SDK bên thứ 3 | Word Office — `iKameSDKCore` (`IKTracking`, `IKRemoteConfig`) | Kiến trúc Phase 0 — tránh vendor lock-in trước khi growth stack phình ra ở Phase 2–3 (widget, Family/Team...) |
| 3 | Share/Action Extension tách riêng theo từng tác vụ cụ thể, đặt tên rõ hành động thay vì 1 action chung | A1 — 3 extension: "Docx to PDF" / "Edit Docx" / "Copy to Docx Editor" | Phase 0/2 — mỗi PDF-tool đã có trong MVP (Compress/OCR/Merge/Split) nên có action riêng trong share sheet của Mail/Files |
| 4 | Không có bất kỳ framework AI/LLM/CoreML nào trong danh sách link của cả 2 app | Cả 2 đối thủ | Bằng chứng kỹ thuật cứng cho pillar 3 (mục 1) — "0/3 đối thủ có AI thật" không chỉ suy từ copy marketing, mà xác nhận bằng static analysis |
| 5 | Có module nội bộ dùng chung, không lộ ra trong symbol table chính (xem giải thích bên dưới) | A1 — `A1AppSDK.bundle`, cùng pattern kiến trúc với `iKameSDKCore` của Begamob | Củng cố nhận định mục 1: đối thủ #2/#3 (cùng nhóm Rho) nhiều khả năng share hạ tầng kỹ thuật thật, không chỉ ảnh/template marketing — **chưa xác nhận trực tiếp trên IPA #3, mới là suy luận từ pattern** |
| 6 | Push (production APNs) + Universal Links + in-app chat (Intercom) + session-replay (Clarity) | A1 | Gap trong roadmap hiện tại — chưa có mục nào cho push/deep-link/support ở cả 3 phase, cân nhắc gộp vào Phase 2 cùng nhóm "widget + Siri shortcuts" |
| 7 | Cloud import (Google Drive/Dropbox) chỉ là static-link SDK chuẩn (GoogleSignIn+GTMSessionFetcher+SwiftyDropbox), không phải custom nặng | Cả 2 đối thủ đã có sẵn từ lâu | Đáng hỏi lại team dev có nên đẩy sớm hơn Phase 2 hay không — mức độ tốn công có thể thấp hơn ước tính hiện tại |

### Vì sao đoán được `A1AppSDK` là module dùng chung nhiều app (mục 5)

Đây là suy luận từ 2 quan sát kỹ thuật cộng lại, không phải đọc thấy trực tiếp:

1. **Có bundle resource tên `A1AppSDK_A1AppSDK.bundle` ở root app, nhưng không có `A1AppSDK.framework` riêng trong thư mục `Frameworks/`.** Cách đặt tên `<Tên>_<Tên>.bundle` là chuẩn resource-bundle của CocoaPods — nghĩa là có 1 thư viện tên "A1AppSDK" thật sự tồn tại và được build vào app. Nhưng khác với `sodk.framework`, `Clarity.framework`, `Intercom.framework`... (đều là dynamic framework tách riêng, thấy rõ trong `Frameworks/`), "A1AppSDK" **không xuất hiện dưới dạng framework độc lập** — tức code của nó bị compile thẳng (static-link) vào chung 1 khối với executable chính, không phải 1 file `.framework` riêng để mở ra xem.
2. **Vì vậy nó biến mất khỏi symbol table đọc được.** Khi liệt kê "undefined symbol" của binary chính (`nm -m ... | grep undefined`), mỗi symbol đều gắn nhãn "from thư-viện-nào" — thấy rõ `(from Clarity)`, `(from Intercom)`, `(from FBSDKCoreKit)` vì đó là framework tách rời, linker phải ghi rõ nó vay symbol từ đâu. Nhưng code của A1AppSDK đã hoà vào chung 1 khối với code app từ lúc build, nên không có cách nào tách "hàm nào là A1AppSDK, hàm nào là code app gốc" chỉ bằng đọc symbol table — nó trông y hệt code của chính app A1. Cộng thêm việc **executable chính bị FairPlay-encrypt** (chính sách của chúng ta là không đụng vào phần này), nên toàn bộ logic thật bên trong A1AppSDK là vùng mù hoàn toàn với static analysis không-decrypt — chỉ còn lại đúng 1 dấu vết: cái tên bundle resource còn sót lại.

**Vì sao dấu vết này gợi ý "dùng chung nhiều app"**: cách đặt tên "A1AppSDK" không đọc như "SDK viết riêng cho app A1" theo nghĩa hẹp — nó đọc như 1 module nội bộ generic (kiểu "AppSDK" là tên chung, "A1" là namespace/target cụ thể) mà công ty Rho build 1 lần, rồi link tĩnh vào từng app trong danh mục của họ, chỉ đổi phần UI/content riêng theo từng app. Đây **đúng hệt kiến trúc đã xác nhận chắc chắn ở phía Begamob**: `iKameSDKCore` cũng là 1 module nội bộ bọc ads/tracking/remote-config, dùng chung cho cả danh mục nhiều app của họ (khác biệt duy nhất: Begamob ship nó dưới dạng dynamic framework nên ta lần được tận API bên trong `IKTracking`/`IKRemoteConfig`; Rho ship static nên chỉ thấy được cái tên, không lần được logic).

Ghép với việc chính roadmap này đã ghi nhận đối thủ #2 và #3 "cùng nhóm publisher Rho... dùng chung ảnh/template marketing" — phát hiện kỹ thuật này gợi ý sự dùng-chung có thể sâu hơn marketing, tới tận hạ tầng kỹ thuật (paywall engine, onboarding flow, growth SDK). **Nhưng đây vẫn chỉ là suy luận theo pattern, chưa phải bằng chứng trực tiếp** — vì bản IPA đối thủ #3 ("Word Editor: Docs & Docx Files") chưa được tải về/phân tích trong nghiên cứu này. Nếu muốn xác nhận chắc, cần tải IPA #3 và kiểm tra có cùng bundle `A1AppSDK`/entitlement team ID `Y8RSTMVX24` hay không.

### Đối chiếu từng feature trong roadmap Phase 0/2/3 với 2 đối thủ đã phân tích (26/08/2026)

> Đọc trực tiếp từ toàn bộ class list của `sodk`/`mupdfdk` (627 class ObjC, quét bằng `nm -g` + `otool -ov` trên 2 framework — không bị FairPlay-encrypt nên đọc được đầy đủ, khác với executable chính của app) + symbol table 2 app + config file thật. "Đã có" nghĩa là có bằng chứng kỹ thuật cụ thể, không phải suy đoán từ mô tả App Store.

**Phase 0 — MVP**

| Tính năng trong roadmap | Đối thủ đã có? | Logic/bằng chứng cụ thể |
|---|---|---|
| Core editing DOCX/XLSX/PPTX + xem/convert PDF | **Có, cả 2** | Chung 1 lõi Artifex (`SODKDoc`/`SODKDocSession`) + rẽ nhánh riêng: `SODKSheetViewController` cho Excel (kèm engine công thức `SODKFormula*`), animation engine riêng cho PPT transition (`AnimLayer`/`FadeTask`/`MoveTask`...), PDF là module tách biệt gọi thẳng `MuPDFDKBasicDocumentViewController` (Word Office xác nhận gọi trực tiếp, không chỉ "đi kèm") |
| Autosave + crash-recovery | Không xác định | Logic autosave nằm trong document-session, không lộ qua tên class — không có class nào tên gợi ý autosave/crash-recovery ở tầng SDK; có thể nằm trong phần code app đã bị encrypt |
| Kiến trúc layout adaptive (size classes/NavigationSplitView) | Không xác định | Đây là kiến trúc UI runtime (SwiftUI/UIKit), không lộ ra qua symbol tĩnh bằng phương pháp này |
| Files app provider | **Chưa có ở cả 2** — gap thật | Không app nào có File Provider Extension (`com.apple.fileprovider*`) trong danh sách `.appex` — nghĩa là không app nào xuất hiện như 1 vị trí duyệt được trong app Files kiểu Dropbox/Google Drive. Cơ hội differentiation thật nếu làm được |
| AirPrint | **Có, cả 2** | Cả 2 gọi thẳng `ARDKPrintPageRenderer`/`UIPrintPageRenderer` — nằm trong 15-class core mà cả 2 app cùng gọi |
| Add file — Local + iCloud | **Có, cả 2 (gần như miễn phí)** | Cả 2 dùng `UIDocumentPickerViewController` chuẩn của Apple — iCloud Drive tự động có kèm trong picker này, không cần tích hợp riêng |
| iPad multi-pane UI + Pencil + keyboard shortcuts | **Chưa xác nhận có ở cả 2** | A1 có tự build lại lớp điều hướng (`ARDKContainerViewController`/`ARDKPagesViewController` thay vì UI mặc định SDK) nhưng đây là customize bên trong editor, không phải bằng chứng multi-pane app-shell hay Pencil support riêng — khớp với nhận định gốc "0/3" ở mục 5 |
| OCR — scan giấy thành văn bản | **Chưa có ở cả 2, và SDK cũng không có sẵn** | Quét toàn bộ 627 class `sodk`+`mupdfdk`: không 1 class nào liên quan OCR/text-recognition. A1 có "convert photos into PDF" (`BSImagePicker`) nhưng chỉ là chụp/chọn ảnh ghép PDF, không nhận diện chữ. → Nếu tự build: không cần SDK riêng, `VNRecognizeTextRequest` (Vision framework, native iOS 13+) là lựa chọn rẻ |
| Merge / Split / Compress — Word/PDF/PPT | **Chưa có ở cả 2, và không có sẵn ở tầng SDK** | Quét toàn bộ class list Artifex — không có Merge/Split/Compress. Nghĩa là kể cả đối thủ muốn thêm cũng phải tự viết ngoài SDK. **Lưu ý ước lượng effort**: đây là công sức dev thật, không "rẻ" như nghe tên gọi — không giả định SDK có sẵn nên làm nhanh |
| Note / comment dạng text | **SDK có sẵn, chưa rõ ai bật** | Phát hiện mới: `SODKReviewRibbonViewController` (ribbon "Review" chuẩn kiểu MS Word — nơi chứa Comment/Track Changes) + `SODKAnnotateRibbonViewController` tồn tại trong `sodk`; tầng PDF có `MuPDFDKAnnotateRibbonViewController`+`MuPDFDKAnnotInfoViewController` (sticky note trên PDF). Không thấy trong danh sách class mà 2 app gọi trực tiếp — khả năng cao là "SDK có nhưng app chưa bật", giống pattern e-signature ở Word Office |
| E-signature | **Có ở A1, sâu hơn "vẽ tay"** | Không chỉ vẽ chữ ký — có cả hạ tầng PKI cert-based: `ARDKOpenSSLCert*`, `ARDKOpenSSLKeychain`, `ARDKOpenSSLPKCS12Importer`, `ARDKOpenSSLSigner`/`Verifier`, `ARDKCertPickerDialogViewController`, `ARDKCertVerifyDialogViewController`, `MuPDFDKSigFinder`, `MuPDFDKWidgetSignedSignature` — ký số kiểu doanh nghiệp thật (chọn certificate, verify chữ ký), không chỉ vẽ tay lên màn hình. Word Office có sẵn class này trong SDK nhưng không dùng. Nếu build tính năng này, nên nhắm độ sâu ngang A1 (verify + cert chain) chứ không chỉ vẽ tay |
| Watermark | **Chưa có ở cả 2, và không có ở tầng SDK** | Không tìm thấy class "Watermark" nào trong 627 class quét được — gap thật nhưng phải tự build hoàn toàn, không có sẵn để gọi (khác e-signature) |
| AI tóm tắt/viết lại/hỏi-đáp | **Chưa có, xác nhận chắc** | Không 1 framework AI/LLM/CoreML nào trong toàn bộ `Frameworks/` của cả 2 app — không chỉ "marketing không nhắc", mà thật sự không có code gọi AI |

**Phase 2**

| Tính năng trong roadmap | Đối thủ đã có? | Logic/bằng chứng cụ thể |
|---|---|---|
| Home widget | **Có ở Word Office** — cần sửa lại giả định "0/3" | `MyOfficeWidgetExtension` (`com.apple.widgetkit-extension`) có thật trong `.appex` của Word Office. A1 thì không có |
| Siri Shortcuts | Không xác nhận ở cả 2 | Không có Intents Extension nào trong danh sách `.appex` của app nào |
| Dropbox/Google Drive | **Có, cả 2 — đã có từ lâu, không phải "mở rộng sau"** | Static-link `GoogleSignIn`+`GTMSessionFetcher`+`GoogleAPIClientForREST` (Drive) và `SwiftyDropbox` (Dropbox), xác nhận qua URL scheme riêng (`db-xxxx`, query scheme `dbapi-2`). Đối thủ coi đây là bắt buộc từ sớm — đáng cân nhắc lại timing (xem thêm bảng logic #7 phía trên) |
| Face ID/Touch ID khoá app | **Nhiều khả năng có ở cả 2** — sửa lại giả định "0/3" (đã cập nhật trực tiếp vào bảng roadmap Phase 2 ở mục 4) | Cả Word Office lẫn A1 đều import `LAContext` (`LocalAuthentication`) ngay trong binary chính. Static analysis không biết chính xác nó khoá gì (toàn app hay 1 hành động), nhưng chắc chắn code gọi biometric auth tồn tại thật ở cả 2 |
| Vertical template freelancer (invoice/hợp đồng) | **Chưa có ở cả 2** | Không thấy template file nào đặt tên liên quan invoice/hợp đồng trong resource — chỉ có blank/welcome template chung chung |

**Phase 3**

| Tính năng trong roadmap | Đối thủ đã có? | Logic/bằng chứng cụ thể |
|---|---|---|
| App macOS thật + Handoff | Ngoài phạm vi | Chỉ có IPA iOS, không có bản Mac riêng để kiểm tra |
| Family Sharing / Team-seat | **Chưa có ở cả 2, xác nhận khá chắc** | A1's `.storekit` config khai báo rõ `"familyShareable": false` trên product Yearly; Word Office's `iap_product_id_config` chỉ toàn auto-renewable cá nhân, không group/seat nào |
| Stage Manager/external display/trackpad | Ngoài phạm vi | Cần test UI runtime thật, không lộ qua static symbol |
| iPhone Fold-ready | Chưa ai chuẩn bị (đúng ghi nhận) | Thiết bị chưa ra mắt chính thức |
| "On-device, không upload cloud" làm thông điệp marketing | Không mâu thuẫn | Cả 2 đều tích hợp cloud (Drive/Dropbox) nhưng ở dạng optional/opt-in — không thấy app nào định vị rõ "không upload" trong Info.plist hay privacy description, vẫn là khoảng trống định vị thật |
| visionOS | Ngoài phạm vi | Chỉ có IPA iOS |
| Android | Ngoài phạm vi | Roadmap đã tự ghi nhận đây là nghiên cứu chỉ có data iOS |

**2 điểm cần sửa lại trong các mục trước của tài liệu này** (dựa trên bằng chứng nhị phân, không phải suy đoán):
1. **Widget**: Word Office đã có Home Screen Widget thật — mục 4/Phase 2 nên bỏ ngầm định "đối thủ chưa ai có" khi ưu tiên hạng mục này.
2. **Face ID/Touch ID**: đã sửa trực tiếp vào bảng Phase 2 ở mục 4 — không còn dùng "0/3 đối thủ có" làm lý do.

---

## 7. Rủi ro & điều cần theo dõi

**MVP giờ đã rất đầy — cân nhắc nguồn lực thực tế.** Theo quyết định mới nhất, MVP gom gần hết 4 trụ cột USP vào Phase 0 (PDF-tool trọn vẹn, AI, một phần iPad-native) thay vì trải đều qua nhiều giai đoạn. Điều này giúp khác biệt rõ ngay từ ngày 1 so với cả 3 đối thủ, nhưng đổi lại timeline MVP đã giãn ra đáng kể (1–5 tháng) — cần đối chiếu lại với năng lực team dev thực tế, và cân nhắc launch dạng beta/TestFlight từng phần nếu 11 hạng mục MVP là quá nhiều để làm đồng thời.

**iPhone Fold vẫn là tin đồn.** Toàn bộ phần Fold trong roadmap dựa trên rumor báo chí (MacRumors, Macworld), chưa có xác nhận chính thức từ Apple tại thời điểm nghiên cứu. Kiến trúc layout adaptive ở Phase 0 là khoản đầu tư "không mất gì" dù Fold có ra đúng như đồn hay không — vì nó cũng chính là nền tảng cho USP iPad native. Riêng việc tối ưu chi tiết theo đúng spec màn hình nên đợi Apple công bố chính thức.

**Persona anchor giờ có data thật, không còn là giả định — nhưng chỉ đúng cho US.** Trước đây persona "dân pro" chỉ dựa trên ~5% review chi tiết. Sensor Tower demographic data (01/08/2025–31/07/2026, US) xác nhận 35–44 là nhóm đông nhất thật ở cả 3 đối thủ — độ tin cậy cao hơn hẳn bản trước. Rủi ro còn lại: data này chỉ đại diện thị trường US; nếu roadmap nhắm thêm thị trường khác, cần kiểm tra lại demographic riêng cho từng nước trước khi áp dụng nguyên bản kết luận này.

---

*Product Strategy Master tổng hợp, cập nhật 26/08/2026 · Dựa trên các tài liệu nghiên cứu trước trong cùng thư mục: `competitor-analysis.html`, `deep-dive-ipad-fold-strategy.html`, `feature-full-audit.html`, `product-description.html`.*
