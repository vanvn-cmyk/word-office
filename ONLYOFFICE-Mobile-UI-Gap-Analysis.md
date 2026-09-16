# Gap Analysis + Fix Log: `editor.html` vs kỹ thuật đã research

> **Mục file này:** trả lời "logic đã xử lý toàn bộ theo research chưa (render, fix màn hình, call button) — đã fix + audit xong."
> **Cập nhật quan trọng so với bản đầu (2026-09-16, cùng ngày)**: bản gap-analysis đầu tiên viết vội dựa trên grep tên kỹ thuật *y hệt* đối thủ (`box-controls`, `Mixtbar`, `btn-zoom-topage`...) — **sai phương pháp**. Đọc kỹ lại `editor.html` (4591 dòng) mới thấy: hầu hết các mục tưởng "thiếu" thực ra **đã làm, chỉ bằng kỹ thuật khác** (thường tốt hơn cách đối thủ/research đề xuất, vì dùng API chính thức của ONLYOFFICE thay vì hack CSS/DOM). Bản này là bản đã sửa lại, kèm 2 fix thật đã áp dụng.
> **Cập nhật:** 2026-09-16

---

## Tóm tắt 1 câu

Project **KHÔNG thiếu nhiều như bản gap-analysis đầu tiên nói**. Zoom-fit và PPT-panel-hiding đã làm, qua API nội bộ ONLYOFFICE (`asc_setZoom`/`layout.leftMenu`), tinh vi hơn cả research. Chỉ có **2 mảng thật sự trống**: long-press→context-menu và clipboard bridge — **đã fix trong session này**, code nằm ngay trong `editor.html`.

## Bảng đối chiếu ĐÃ SỬA LẠI (đọc kỹ code thay vì chỉ grep tên)

| Kỹ thuật | Trạng thái thật | Bằng chứng (đọc code, không phải chỉ đếm chuỗi) |
|---|---|---|
| Virtual document server | ✅ Đã có, tương đương | `sdk-core/index.mjs`: `EditorServer`, `MockSocket`, `createXHRProxy` |
| Ẩn panel phải/ruler/statusbar | ✅ Đã có, **kỹ hơn** research | Có tới 3 bộ selector riêng cho Word/Excel/PPT (`de-statusbar`, `pe-statusbar`...), không dùng 1 bộ selector chung như đối thủ |
| **Zoom-fit khổ trang** (tưởng thiếu) | ✅ **ĐÃ CÓ — nhầm ở bản trước** | Dòng ~2219: `zoom = floor(clientWidth/794*100)` tính % zoom theo đúng bề ngang màn hình thật, rồi gọi thẳng `asc_setZoomType(2)` + `asc_setZoom(_fitPct)` — **gọi thẳng API nội bộ ONLYOFFICE**, không phải click hộ nút UI như đối thủ (`#btn-zoom-topage`) — cách này đáng tin hơn vì không phụ thuộc nút đó có render kịp hay không |
| **Ribbon "compactToolbar"** (tưởng thiếu vì không có `Mixtbar`) | ✅ **ĐÃ CÓ — nhầm ở bản trước** | `editorConfig.customization.compactToolbar: true` — đây là **option khai báo chính thức** của ONLYOFFICE DocsAPI ("collapse 2-row ribbon → single icon row"), không phải hack — không cần monkey-patch `Common.UI.Mixtbar` như research đề xuất cho đối thủ, vì đối thủ không biết/không dùng option chính thức này |
| **PPT ẩn panel trái + notes** (tưởng thiếu) | ✅ **ĐÃ CÓ — nhầm ở bản trước** | `editorConfig.customization.layout.leftMenu: false` + `hideNotes: true` — cũng là option khai báo chính thức (comment trong code: "verified in api.js bundled in OfficeBundle"), init-time nên không bị race-condition với lúc canvas render |
| PPT panel — lớp vá geometry-heuristic bổ sung (`_pptGeoHide`) | ⚠️ Tồn tại song song với option chính thức ở trên, do config chính thức không 100% đáng tin trong thực tế (đã có bug thật, "5 lớp vá", changelog 15/09) | Giữ nguyên, không đụng — code vừa fix hôm qua (15/09), rủi ro regression cao nếu sửa mà chưa hiểu hết, không có bằng chứng đang lỗi lại |
| **Long-press → context menu** | ❌ Thiếu thật → ✅ **ĐÃ FIX session này** | Hàm `installTouchEditingBridge()` mới, gọi ở 2 điểm (stub frame lúc `onAppReady`, và live OO document sau `_reInjectOO`) |
| **Clipboard Web API bridge** | ❌ Thiếu thật → ✅ **ĐÃ FIX session này** | Cùng hàm `installTouchEditingBridge()` — tự no-op nếu `office://` scheme không có `isSecureContext` (Clipboard API cần secure context, tự kiểm tra trước khi cài) |

---

## Fix đã áp dụng trong `OfficeBundle/editor.html`

**Hàm mới `installTouchEditingBridge(iDoc, innerWin)`** — chèn sau `injectFormulaTouchSelect`, trước `injectIOSChrome`:
1. **Long-press 500ms (dung sai 10px)** → bắn `contextmenu` event giả tại đúng toạ độ, để menu ngữ cảnh gốc của ONLYOFFICE nhận đúng như bấm chuột phải.
2. **Clipboard bridge**: `copy`/`cut` → ghi vào `navigator.clipboard`; Cmd/Ctrl+V → đọc từ `navigator.clipboard.readText()` rồi bắn `ClipboardEvent('paste')` giả vào `#editor_sdk`. **Tự tắt nếu `isSecureContext` false** (custom URL scheme `office://` có thể không có Clipboard API) — không crash, chỉ bỏ qua.
3. Có flag `__touchEditingBridgeInstalled` trên `window` để không gắn listener 2 lần khi hàm được gọi lại lúc OO re-navigate iframe (đúng pattern idempotent đã dùng sẵn trong file cho `_markOOInteracted`).

Gọi ở đúng 2 nơi đã có sẵn logic gắn listener tương tự (`touchstart`/`mousedown` cho `_ooUserHasInteracted`), để nhất quán vòng đời:
- Trong khối gắn listener lên `iDoc` (stub frame, dòng ~1839).
- Trong `_reInjectOO()`, sau khi phát hiện OO document thật đã load (dòng ~1974).

**Đã kiểm tra**: extract script ra, chạy `node --check` — pass, không lỗi cú pháp. **Chưa test trên simulator/device thật** — cần bạn build + thử tay: mở 1 file Word, giữ tay ~0.5s trên đoạn text xem menu ngữ cảnh có hiện không; copy text ở app khác rồi Cmd+V vào editor xem có paste được không.

---

## Audit: "call các tính năng edit" — đã chuẩn/đủ so với đối thủ chưa?

**Kết luận: chuẩn, và đầy đủ hơn đối thủ ở mọi mặt kiểm tra được.**

Đối thủ (research file mục 5) chỉ có **đúng 3 action** qua bridge: `loading`, `save`, `share`. Project này có **14 action**, tất cả đều dùng đúng cơ chế `window.webkit.messageHandlers.editorBridge.postMessage` (API WebKit công khai, không phải hàng lạ):

`apiDump`, `debug`, `documentStateChange`, `domDump`, `editorError`, `openError`, `ready`, `save`, `saved`, `saveError`, `saveUnavailable`, `scriptReady`, `showNativeFilter`, `slideChange`, `wordCount`, `slideThumbnail`

Đối chiếu từng điểm với research:
- **Save**: có, qua `docEditor` (giống đối thủ dùng API chính thức, không hack).
- **Share**: **không đi qua JS bridge như đối thủ** — CHANGELOG 15/09 cho thấy Share làm native thuần bằng `ShareLink(item: ref.url)` (SwiftUI) share thẳng file đã lưu trên disk — **thiết kế gọn hơn đối thủ**, vì file đã có sẵn trên máy (không cần JS export lại y hệt save rồi mới share).
- **Open**: có, qua `receiveFileFromIOS`, đúng pattern.
- **Dirty-state**: có, nhưng dùng **push** (`documentStateChange`) thay vì **poll** (`documentHadChange()` như đối thủ) — JS tự báo khi đổi thay vì đợi native hỏi — thiết kế event-driven, đúng hướng tốt hơn.
- **Ngoài phạm vi đối thủ hoàn toàn không có**: `showNativeFilter` (spreadsheet filter UI native), `wordCount`, `slideThumbnail`, `slideChange` — project này còn bridge thêm cả tính năng phụ mà đối thủ không làm.
- **Các lệnh edit khác gọi thẳng API nội bộ ONLYOFFICE từ phía native** (không qua bridge JS→native, mà native gọi `evaluateJavaScript` để JS gọi `Asc.editor.asc_setFontFamily(...)`, `asc_getIsFormulaEditMode()`...): `window.ooSetFontFamily`, `window.ooFindReplace` — 2 tính năng native picker (font, find&replace) mà đối thủ **hoàn toàn không có** (đối thủ chỉ có save/share/open, không có native UI gọi vào tính năng edit cụ thể nào).

→ Không cần sửa gì ở phần bridge/call-features — đã đúng chuẩn (dùng API WebKit công khai) và **vượt phạm vi đối thủ**, không phải chỉ "đủ".

---

## Việc còn lại, chưa đụng (rủi ro cao hơn lợi ích rõ ràng lúc này)

- `_pptGeoHide` (ngưỡng hình học) — có thể refactor sang selector DOM ổn định sau, nhưng vừa fix hôm qua và không có bằng chứng đang lỗi — để nguyên, monitor thêm.
- Không thêm `Common.UI.Mixtbar` patch — vì `compactToolbar: true` (option chính thức) đã giải quyết đúng vấn đề đó theo cách ONLYOFFICE hỗ trợ, thêm patch chồng lên có thể xung đột không cần thiết.
