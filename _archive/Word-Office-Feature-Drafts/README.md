# Word-Office-Feature-Drafts

Folder-drop chứa các UI feature đang phát triển riêng lẻ trên máy này — **thêm UI vào các
luồng hiện có** của app Word Office, không phải app/module độc lập. Mục đích: copy nguyên
folder này sang máy công ty để merge tay vào project chính, theo đúng pattern đã dùng ở
Session 19 với `Word-Office-Session14-Delta`.

**Không phải Xcode project** — không có `.xcodeproj`, không tự build/preview được ở đây.
Không `git add` folder này vào repo chính (giữ untracked, giống `Word-Office-Session14-Delta`).

## Cách dùng

- Mỗi feature mới = 1 subfolder trong `Views/<TenFeature>/`, chứa file `.swift` (View, và
  ViewModel/Model nếu cần) tương ứng với chỗ nó sẽ merge vào trong project chính.
- Muốn xem SwiftUI Preview khi đang code ở đây: copy tạm file vào đúng chỗ trong
  `Word Office/Word Office/Views/...` của project chính, chạy thử, rồi **xoá bản copy tạm**
  (không để lẫn 2 bản trong project chính).
- Ghi rõ trong mục "Danh sách feature đang phát triển" bên dưới: file nào map vào file/folder
  nào trong project chính — để lúc merge trên máy công ty không phải đoán.

## Quy tắc merge sang project chính (trên máy công ty)

1. Đọc `rule.md` và phần đầu `CHANGELOG.md` của project chính TRƯỚC — code chính có thể đã
   đổi từ lúc file draft được viết ở đây.
2. Merge tay **từng file** (không copy đè cả thư mục) — đọc + diff trước khi merge, giữ
   nguyên phần đã có ở project chính nếu có conflict, chỉ cộng thêm phần mới.
3. Sau khi merge, chạy qua `/swiftui-expert-skill` (SwiftUI) + `/code-review` (logic/service)
   theo rule.md #4 trước khi coi task là "done".
4. Ghi lại vào `CHANGELOG.md` của project chính: đã merge feature nào, từ file nào trong
   `Word-Office-Feature-Drafts/`.

## Danh sách feature đang phát triển

_(cập nhật khi thêm feature mới — tên feature, mô tả ngắn, map vào đâu trong project chính)_

### Templates gallery (2026-09-13) — **đã tích hợp vào FAB thật trên máy này**

Màn "Templates" full-screen mở khi user chọn 1 loại tài liệu ở FAB (`LibraryAddButton`),
thay vì tạo blank ngay như trước. Thiết kế theo ảnh reference user gửi (segmented
DOCX/XLS/PPT + grid 2 cột, "Blank Document" card luôn đứng đầu). Toàn bộ nội dung
template (Business Proposal, Invoice, Medical Report...) là **mock/placeholder** — chưa
có content pipeline thật, tap vào 1 template hiện "Coming soon" giống pattern
`LibraryAddButton` đã có cho blank kind chưa hỗ trợ.

**Khác với quy trình chuẩn của folder này** — feature này đã được merge thẳng vào
`Word Office/Views/Library/` thật trên máy này rồi (không chỉ nằm ở draft), vì user
confirm muốn nối FAB thật ngay trong session. Bản copy ở đây vẫn được giữ **đồng bộ**
với bản thật, đúng mục đích ban đầu của folder (mang sang máy công ty). Nếu máy công ty
đã pull được commit này qua git bình thường thì không cần merge tay nữa — chỉ cần khi
máy công ty CHƯA có các commit tương ứng.

File (giống hệt bản trong `Word Office/Views/Library/` — đã build + qua
`/swiftui-expert-skill` review, không còn `/code-review` do user tạm tắt review trong
session này):

- `DocumentTemplate.swift` — model `DocumentTemplate` (struct + `ThumbnailStyle` enum) thôi,
  không chứa data.
- `TemplateCatalog.swift` — enum điều phối `templates(for kind:)`, switch sang 3 file dưới.
- `TemplateCatalog+Word.swift` / `TemplateCatalog+Excel.swift` / `TemplateCatalog+PowerPoint.swift`
  — mỗi file 1 mảng `[DocumentTemplate]` mock riêng cho DOCX/XLSX/PPTX (tách theo yêu cầu
  user "chia ra từng loại 1" — trước đó gộp cả 3 mảng trong 1 file khó đọc). Thêm loại thứ 4
  sau này = thêm 1 file `TemplateCatalog+<Loại>.swift` mới, không sửa 3 file hiện có (OCP,
  rule.md #5).
- `TemplateGalleryView.swift` — màn chính + segmented tab + grid + blank card + template
  card + thumbnail placeholder (vẽ bằng SwiftUI, không cần asset ảnh thật).
- `LibraryAddButton.swift` **thật** (không có bản copy ở đây — file đã tồn tại từ trước) đã
  sửa: 3 dòng menu Word/Spreadsheet/Presentation không gọi `handleCreate` trực tiếp nữa, mà
  set `templateGalleryKind` + `isPresentingTemplateGallery = true`, mở qua
  `.fullScreenCover(isPresented:)`. `onCreateBlank` closure của `TemplateGalleryView` gọi lại
  `handleCreate(kind:)` y nguyên logic cũ (kể cả `comingSoonKind` cho xlsx/pptx chưa hỗ trợ).
  Máy công ty merge tay phần này bằng cách áp lại đúng diff (xem git log/diff của
  `LibraryAddButton.swift` nếu không pull được trực tiếp).
- `PressableCardButtonStyle` trong `TemplateGalleryView.swift` là bản copy riêng của bản
  `private` đã có trong `ToolsTabView.swift` — nên hoist thành 1 component dùng chung trong
  `DesignSystem/Components/Buttons/` một dịp khác thay vì giữ 2 bản trùng nhau (chưa làm,
  không phải blocking).
- **Cập nhật 2026-09-14**: bản `LibraryAddButton.swift` đầy đủ (đã có cả patch FAB này lẫn
  mọi thay đổi khác tới ngày 14/9) giờ nằm trong
  `Home-Status-Update-2026-09-14/Views/Library/LibraryAddButton.swift` bên dưới — không cần
  tự áp diff tay nữa như ghi chú cũ ở trên, copy nguyên file đó là đủ.

### Home — status grouping + connector line + Mark as Done (2026-09-14) — **code thật đã có sẵn trên máy này, đây chỉ là bản mirror để mang đi**

⚠️ Khác hẳn Templates ở trên: đây **không phải feature độc lập mới**, mà là hàng loạt sửa đổi
trực tiếp vào các file **đã tồn tại** của Home/Library (status system, cách nhóm danh sách,
Mark as Done, v.v.). Toàn bộ đã chạy thật trên máy này (build sạch + test pass), nhưng
**chưa hề commit git** (repo có remote `origin` GitHub thật, nhưng commit gần nhất là
Session 10 ngày 2026-09-03 — mọi thứ từ đó tới giờ chỉ nằm ở working tree). User chủ động
chọn KHÔNG đẩy lên git, copy tay sang máy công ty thay vào đó.

**Tóm tắt nội dung** (chi tiết đầy đủ xem `CHANGELOG.md` của project chính, mục Session 22,
Nhóm 2 → Nhóm 14 — rất nhiều vòng lặp sửa theo screenshot, đừng chỉ đọc code mà bỏ qua lý do):

- `DocumentStatus` rút từ 4 còn 3 trạng thái (bỏ `Sent`, đổi `Signed` → `Done`), thêm
  `tintColor` làm nguồn màu duy nhất cho toàn bộ status.
- Home đổi từ nhóm theo ngày (`DateBucket`) sang nhóm theo status (Draft/Reviewed/Done) —
  đúng lời hứa của onboarding S3. Filter ngày cũ nay nằm trong popover filter thay cho
  filter status (dư thừa vì status giờ là cách nhóm chính).
- Section header dạng "Draft (5)" kèm thanh màu + stub nối ngắn tự thân mỗi header (**không
  phải 1 đường liền mạch thật** — bản đầu dùng anchor preference đo vị trí thật giữa các
  header đã bị lỗi mất đường khi cuộn nhanh do `List` lazy-render, đã lùi về bản stub an
  toàn hơn — xem CHANGELOG Nhóm 14 để hiểu tại sao, đừng làm lại bản anchor preference nếu
  không chuẩn bị xử lý đúng vụ lazy-render này).
- Mở file Draft → tự động chuyển Reviewed (`recordOpen`) — **quyết định đảo ngược có chủ ý**
  khỏi nguyên tắc "không auto-suy luận status" gốc trong `Library-Architecture.md` §9 risk #2;
  file đó KHÔNG được sửa lại, chỉ có code thật đổi hành vi.
- Thêm "Mark as Done" 1-chạm vào kebab menu (`FileActionsMenu`), song song với "Change status"
  long-press cũ.
- Bỏ hẳn Liquid Glass ở chip lọc loại tài liệu (`TypeTabButton`) — glass tự gây vệt đen mờ,
  đã thử sửa sai 2 lần trước khi tìm đúng nguyên nhân.

**File** (nằm trong `Home-Status-Update-2026-09-14/`, path bên trong khớp path thật trong
`Word Office/`):

| File trong draft | Merge vào |
|---|---|
| `Models/DocumentStatus.swift` | `Word Office/Models/DocumentStatus.swift` |
| `App/LibraryStore.swift` | `Word Office/App/LibraryStore.swift` |
| `ViewModels/LibraryViewModel.swift` | `Word Office/ViewModels/LibraryViewModel.swift` |
| `ViewModels/LibraryViewModel+Filtering.swift` | `Word Office/ViewModels/LibraryViewModel+Filtering.swift` |
| `ViewModels/LibraryViewModel+Grouping.swift` | `Word Office/ViewModels/LibraryViewModel+Grouping.swift` |
| `Views/Library/LibraryView.swift` | `Word Office/Views/Library/LibraryView.swift` |
| `Views/Library/DocumentGrid.swift` | `Word Office/Views/Library/DocumentGrid.swift` |
| `Views/Library/DocumentCard.swift` | `Word Office/Views/Library/DocumentCard.swift` |
| `Views/Library/LibraryAddButton.swift` | `Word Office/Views/Library/LibraryAddButton.swift` (đã bao gồm cả patch Templates FAB ở trên) |
| `Tests/LibraryViewModelTests.swift` | `Word OfficeTests/LibraryViewModelTests.swift` |
| `Tests/MetadataStoreImplTests.swift` | `Word OfficeTests/MetadataStoreImplTests.swift` |

Lưu ý quan trọng khi merge trên máy công ty: máy công ty gần như chắc chắn cũng đang có
những file này ở trạng thái KHÁC (đã qua bao nhiêu session riêng rồi) — đây là 11 file **đè
nguyên bản**, không phải patch/diff, nên **đọc kỹ bản máy công ty trước, diff bằng tay từng
file**, đừng copy đè thẳng như 1 khối. Nếu 2 bên đã lệch nhiều, thà merge logic thủ công còn
hơn mất code máy công ty đã làm riêng.

Sau khi merge: chạy `/swiftui-expert-skill` (LibraryView.swift đụng nhiều SwiftUI View/state)
+ full test suite (`Word OfficeTests`, đang là 37 test) trước khi coi xong.

---
*Folder này không đi qua git — chỉ là nơi giữ code nháp giữa 2 máy (giống
`Word-Office-Session14-Delta`). Toàn bộ quy tắc làm việc chính xem ở `rule.md`.*
