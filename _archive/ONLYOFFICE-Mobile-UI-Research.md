# Nghiên cứu: đối thủ render + tuỳ biến UI mobile cho ONLYOFFICE thế nào

> **Mục file này:** trả lời câu hỏi "PPT/Word trông như website" bằng cách bóc tách chính xác cách đối thủ (`com.codeharmonylabs.sheetai`, "Office Word – Edit Word Docs") biến editor ONLYOFFICE (vốn thiết kế cho desktop/web) thành thứ chấp nhận được trên điện thoại — rồi đề xuất áp dụng cho Word Office.
> **Nguồn:** đọc trực tiếp bundle JS/CSS thật của đối thủ, còn nguyên trên máy tại `~/OfficeWord_extracted/Payload/Sheet.app/out/` (giải nén từ IPA, static analysis, không đụng tới binary chính bị mã hoá FairPlay). Không đoán — mọi đoạn code trích dưới đây là nguyên văn (đã format lại cho dễ đọc), lấy từ `assets/index-DRqW9kMl.js`.
> **Song song với:** `project_office_competitor_ipa_teardown` (memory) — phần kiến trúc tổng (WKWebView → iframe → proxy fetch/XHR) đã ghi ở đó; và `ONLYOFFICE_OFFLINE_ARCHITECTURE.md` (cùng thư mục) — file đó nói về pipeline offline (x2t.wasm, virtual document server, bundle size) đã implement thật, file này đào sâu riêng phần **UI/rendering/bridge nút bấm** mà file kia chưa nói tới.
> **Cập nhật:** 2026-09-16

---

## Tóm tắt tổng hợp (đọc phần này trước, chi tiết ở các mục bên dưới)

**Lựa chọn kiến trúc của đối thủ (mục 1)**: ONLYOFFICE có sẵn 2 bộ UI — `main/` (ribbon desktop) và `mobile/` (chính chủ, Framework7, nhái UI iOS). Đối thủ chọn `main/` rồi tự patch xuống mobile, **không dùng** bản `mobile/` có sẵn — chưa rõ đây có phải lựa chọn tối ưu hay không, Word Office nên tự test cả 2 trước khi theo (mục 6).

**4 lớp kỹ thuật họ tự patch thêm lên `main/`, tách theo đúng vấn đề mỗi lớp giải quyết:**

| Lớp | Vấn đề | Cách giải quyết | Mục chi tiết |
|---|---|---|---|
| 1. Chrome (ribbon/toolbar/panel) | Nhìn "web" vì đầy nút/panel desktop-only (About, Comment, panel phải, ruler...) | Tiêm CSS ẩn phần vô nghĩa khi offline; ribbon giữ nguyên nhưng chuyển sang cuộn ngang thay vì thu gọn | 2 |
| 2. Touch ergonomics | Ribbon vốn thiết kế cho chuột, thiếu long-press và clipboard hệ thống | Tự bắt pointerdown 500ms giả lập `contextmenu`; tự bridge `copy/paste` sang Clipboard Web API | 3 |
| 3. Render nội dung tài liệu | Trang mặc định vẽ đúng khổ A4 thật (794×1123px), to hơn màn hình phone | Nội dung vốn đã vẽ bằng `<canvas>` (không phải HTML) — chỉ cần tự bấm hộ nút "Fit Page" có sẵn, không tự tính toán scale | 4 |
| 4. Cầu nối Native ↔ JS | Mở/lưu/chia sẻ file cần hệ điều hành, các nút khác thì không | Chỉ đúng 3 sự kiện (`loading`/`save`/`share`) đi qua bridge; **toàn bộ ribbon còn lại (Bold, Table, Insert Image...) xử lý 100% nội bộ trong ONLYOFFICE, không đụng native** | 5 |

**Điểm chốt quan trọng nhất cho Word Office**: không phải mọi thứ đều cần code riêng.
- **Việc phải tự làm**: 4 lớp patch ở trên (nếu chọn Hướng A) + đúng 3 điểm nối bridge (mở/lưu/share).
- **Việc KHÔNG cần tự làm**: mọi nút định dạng/insert/undo — ONLYOFFICE tự lo hết; scale canvas theo màn hình — chỉ cần trigger đúng API zoom-fit có sẵn, không tự viết toán resize.
- **Rủi ro thật, không phải kỹ thuật này**: license AGPLv3 của ONLYOFFICE khi bundle offline không server (đã ghi ở `project_office_competitor_ipa_teardown` trong memory, và ở mục 11 file `ONLYOFFICE_OFFLINE_ARCHITECTURE.md`) — cần hỏi sales ONLYOFFICE trước khi ship, không liên quan gì đến các kỹ thuật patch UI/bridge nói trên (những cái đó dùng toàn API WebKit công khai, không phải nguồn rủi ro Apple review).
- **Toàn bộ code logic viết lại sẵn, theo chuẩn riêng (không copy đối thủ), sẵn sàng đem dùng** → mục 7.

---

## 1. Họ KHÔNG dùng bản "mobile" chính thức của ONLYOFFICE — phát hiện quan trọng nhất

Bundle của đối thủ có đầy đủ **2 bộ UI khác nhau** đi kèm ONLYOFFICE, cho mỗi loại editor (`documenteditor`, `presentationeditor`, `spreadsheeteditor`, `visioeditor`):

```
web-apps/apps/documenteditor/
  ├── main/      ← ribbon UI cho desktop/web (chuột + bàn phím)
  ├── mobile/    ← UI RIÊNG cho di động, build bằng Framework7
  ├── embed/
  └── forms/
```

Bản `mobile/` là **hàng chính chủ của ONLYOFFICE**, không phải hàng tự chế:
- Dùng **Framework7** (`framework7.css`) — framework UI clone rất sát ngôn ngữ thiết kế iOS (navbar, tab bar, action sheet, list cell...).
- `<meta name="theme-color" content="#007aff">` — đúng màu xanh hệ thống iOS.
- `apple-mobile-web-app-capable`, `viewport-fit=cover`, `minimal-ui` — tối ưu sẵn cho chạy full-screen trong WebView/PWA.

**Nhưng đối thủ lại KHÔNG dùng bản này.** Bằng chứng: config họ truyền vào `DocsAPI.DocEditor` (API load editor) có `type:"desktop"` cứng, tức họ load bản `main/` (ribbon desktop) rồi mới tự viết code CSS/JS để "ép" nó co lại vừa màn hình điện thoại — chi tiết ở mục 2.

→ Đây là 1 lựa chọn kiến trúc **có thể không phải lựa chọn tối ưu**, không phải điều bắt buộc. Team mình nên tự hỏi: build trên nền `main/` (giống đối thủ, nhiều việc CSS/JS patch, dễ vỡ khi ONLYOFFICE ra bản mới) hay thử thẳng `mobile/` (chính chủ, đã tối ưu cho touch, nhưng chưa rõ có đủ tính năng edit như `main/` không — cần test thật, xem mục 6).

---

## 2. Cách đối thủ "show button" — patch ribbon desktop thành thanh công cụ mobile

Họ không rebuild toolbar. Họ giữ nguyên ribbon gốc của ONLYOFFICE, rồi tiêm 1 thẻ `<style>` (id `offline-toolbar-scroll-patch`) **kèm chạy lại bằng JS mỗi khi DOM đổi** (vì ONLYOFFICE tự re-render 1 số phần, style tĩnh không đủ) để:

### a) Ẩn hẳn những thứ vô nghĩa khi offline/không server
```css
/* Panel bên phải: chat, comment, collaboration — vô nghĩa vì không có server đồng bộ */
#right-menu, #right-panel, [class*="right-panel"], [class*="rightmenu"] {
  display: none !important; width: 0 !important; margin: 0 !important;
}

/* Nút About + Comment, match theo mọi kiểu attribute có thể có */
#btn-about, #btn-comments,
[data-hint*="About"], [data-hint*="Comment"],
[aria-label*="About"], [aria-label*="Comment"] {
  display: none !important;
}

/* Ruler (thước kẻ trang) — tính năng desktop-only, chiếm chỗ vô ích trên phone */
#id_vertical_ruler, #id_hor_ruler, [class*="ruler"] { display: none !important; }
```

### b) Ẩn luôn thanh tiêu đề web gốc của ONLYOFFICE (họ tự vẽ tiêu đề native của riêng mình đè lên)
```css
body > header, body > [class*="header"], body > [class*="titlebar"],
#viewport > header, #viewport > [class*="caption"] {
  display: none !important;
}
/* Bù lại khoảng trống top vừa xoá */
body, #viewport, #editor_sdk { padding-top: 0 !important; margin-top: 0 !important; }
```
Có thêm 1 đoạn JS riêng: từ `#app-title`, họ **đi ngược lên DOM tìm container cha có ≥3 sibling layout-item** rồi ẩn cả khối đó — tức không hardcode 1 selector cụ thể (dễ vỡ khi ONLYOFFICE đổi class name), mà tìm theo *cấu trúc layout* (linh hoạt hơn, ít bị vỡ khi ONLYOFFICE update).

### c) Phần ribbon KHÔNG bị ẩn — chỉ đổi cách cuộn
Đây là phần hay nhất: `.box-controls` (hàng nút định dạng thật — Bold/Italic/Insert Table...) **không hề bị đóng gói lại thành menu native**. Họ chỉ đổi CSS cho nó cuộn ngang được:
```css
.box-controls {
  overflow-x: auto !important;
  overflow-y: hidden !important;
  -webkit-overflow-scrolling: touch;   /* scroll mượt kiểu iOS, không giật */
}
.box-controls .panel.active {
  width: max-content !important;
  white-space: nowrap !important;      /* không cho wrap xuống dòng 2 */
}
```
Tức chiến lược là: **giữ ribbon gốc, biến nó thành 1 dải nút cuộn ngang** (giống kiểu segmented toolbar cuộn ngang hay thấy ở app note/spreadsheet mobile), thay vì cố nhồi hết nút vào 1 màn hình hẹp hay xây lại toolbar từ đầu bằng native UIKit.

Status bar (zoom, số trang) ở dưới cùng cũng xử lý y hệt — cho cuộn ngang, nền trắng phẳng, bỏ hết shadow/border desktop:
```css
#statusbar { overflow-x: auto; background: #fff !important; box-shadow: none !important; }
```

### d) Panel bên trái (thumbnail slide trong PowerPoint) — ẩn có điều kiện
Cờ `shouldHidePresentationLeftPane` (truyền từ ngoài vào hàm patch) quyết định có ẩn `#left-menu` (dải thumbnail slide) hay không — hợp lý vì trên iPhone màn hình hẹp, dải thumbnail chiếm chỗ quý giá; trên iPad có thể giữ lại.

---

## 3. Cách họ vá phần "touch ergonomics" mà ribbon desktop vốn không có

Ribbon desktop được thiết kế cho chuột — thiếu 2 thứ then chốt để dùng mượt bằng ngón tay, và đối thủ tự vá cả hai:

**a) Long-press → context menu (copy/cut/paste/insert...)**
Trình duyệt di động không tự bắn sự kiện `contextmenu` khi giữ tay như máy tính bấm chuột phải. Họ tự cài `pointerdown`/`touchstart`, đếm **500ms giữ + cho phép lệch tối đa 10px** (đủ để không nhầm với thao tác kéo/scroll), rồi tự bắn 1 `MouseEvent("contextmenu", ...)` giả tại đúng toạ độ đó — để menu ngữ cảnh gốc của ONLYOFFICE tưởng người dùng bấm chuột phải thật.

**b) Clipboard hệ thống ↔ Clipboard Web API**
WKWebView không tự nối copy/paste của người dùng (từ app khác, hoặc phím tắt) vào Clipboard API chuẩn của trình duyệt. Họ tự lắng nghe sự kiện `copy`/`cut`/phím Cmd+V, gọi thẳng `navigator.clipboard.writeText/readText`, rồi bắn lại 1 `ClipboardEvent("paste", ...)` giả vào đúng element `#editor_sdk` để engine ONLYOFFICE xử lý paste như bình thường.

---

## 4. Cách họ RENDER nội dung tài liệu, và scale từ khổ desktop xuống mobile

Mục 2-3 ở trên nói về **chrome** (ribbon/toolbar/panel) — còn đây mới là phần **nội dung tài liệu thật** (trang Word, slide PPT) hiển thị ra sao.

### 4.1 Nội dung KHÔNG phải HTML/DOM — nó là `<canvas>` vẽ pixel

Đọc file `sdk-all-min.js` (engine lõi ONLYOFFICE, ~1.2MB) thấy **16 lần `createElement("canvas")`, 18 lần `getContext("2d")`, 7 lần dùng `devicePixelRatio`**. Tức trang Word/slide PPT **không phải HTML dàn chữ** như 1 trang web bình thường — nó được chính engine ONLYOFFICE **tự vẽ từng pixel lên `<canvas>`** (đo, dàn dòng, kẻ chữ y hệt cách 1 trình đọc PDF/print-engine làm), rồi nhân với `devicePixelRatio` để nét chữ sắc trên màn Retina — **giống hệt cách Word/Pages thật vẽ trang**, không phải kiểu website render text bằng thẻ `<p>`/`<div>` (đó là lý do phần **nội dung** của ONLYOFFICE vốn dĩ đã KHÔNG trông giống website — cái khiến "trông như web" chính là phần **chrome** xung quanh nó, đúng như mục 2 đã mổ xẻ).

Bằng chứng thêm: khung "loading skeleton" tĩnh trong `main/index.html` (hiện ra trước khi canvas thật kịp vẽ) có kích thước cứng **`794px × 1123px`** — đúng chính xác khổ giấy **A4 ở 96 DPI** (210mm×297mm). Nghĩa là ở zoom 100%, ONLYOFFICE mặc định vẽ trang ra đúng kích thước vật lý thật của A4/Letter — **to hơn hẳn bề ngang màn hình iPhone** (iPhone ~390-430px CSS-width). Đây chính là gốc rễ của câu hỏi "render từ desktop ra mobile" — nếu không xử lý gì, user sẽ phải cuộn ngang liên tục để đọc hết 1 dòng.

### 4.2 Cách họ giải quyết: KHÔNG tự tính toán lại canvas — chỉ tự bấm hộ nút "Fit Page" có sẵn

Tìm thêm được 1 hàm nữa (gọi nó là `QE` trong code minify) mà lần trước đọc dở chưa thấy — đây mới là câu trả lời trực tiếp cho "render từ view desktop ra mobile":

```js
// Tên gốc bị minify thành QE — chức năng thật: tự bấm nút "Zoom to Page"
function autoFitPageOnMobile(win, doc) {
  let pollTimer = null;
  const stopPolling = () => { if (pollTimer) win.clearInterval(pollTimer); pollTimer = null; };

  const tryClickFitPage = () => {
    const btn = doc.querySelector('#btn-zoom-topage');
    if (!btn) return false;
    const isAlreadyActive = btn.getAttribute('aria-pressed') === 'true'
      || btn.classList.contains('active') || btn.classList.contains('pressed');
    if (!isAlreadyActive) btn.click();   // <-- chỉ đơn giản là bấm hộ nút có sẵn
    return true;
  };

  if (!tryClickFitPage()) {
    // nút chưa kịp render (ONLYOFFICE JS chưa load xong) — đợi rồi thử lại
    pollTimer = win.setInterval(() => { tryClickFitPage() && stopPolling() }, 300);
  }
  return stopPolling;
}
```

Tức là: **họ không tự viết logic scale canvas nào cả.** `#btn-zoom-topage` ("Thu phóng vừa trang" / "Fit Page") vốn đã là 1 nút **có sẵn, chính chủ** trong ribbon ONLYOFFICE (dành cho người dùng desktop muốn xem toàn trang thay vì cuộn) — họ chỉ đợi nút đó xuất hiện trong DOM rồi **giả lập bấm nó tự động ngay khi mở tài liệu** (nếu chưa ở trạng thái active). Toàn bộ việc "tính lại kích thước trang, vẽ lại canvas ở tỉ lệ mới, giữ nét chữ sắc theo `devicePixelRatio`" là **chính engine ONLYOFFICE tự lo**, vì đó vốn là code xử lý zoom desktop bình thường (khi user tự bấm nút đó) — họ chỉ mượn nguyên hành vi có sẵn, kích hoạt hộ sớm hơn (tự động, ngay khi mở) thay vì đợi user tự bấm.

**Bài học rút ra, áp dụng được luôn dù chọn Hướng A hay B (mục 6)**: không cần tự viết code resize/scale canvas — chỉ cần trigger đúng API zoom "fit width/fit page" mà ONLYOFFICE đã có sẵn (cả bản `main/` lẫn `mobile/` đều có khái niệm zoom-to-fit), việc còn lại engine tự làm đúng, kể cả phần khó (DPI, dàn lại dòng chữ theo bề ngang mới).

---

## 5. Cách native gọi các nút Save/Share/Open — cầu nối Swift ↔ JS thật sự

Đây là phần "config gọi nút edit file". Đã tìm ra đầy đủ cả 2 chiều (native gọi JS, và JS gọi ngược lại native) — không đoán, đọc trực tiếp code.

### 5.1 Chiều Native → JS: chỉ là gọi thẳng hàm global trên `window`

**Không dùng `WKScriptMessageHandler` cho chiều này.** Native chỉ cần gọi `webView.evaluateJavaScript("window.<tên hàm>()")`. App JS tự expose sẵn các hàm này lên `window`:

| Hàm global | Native gọi khi nào | JS làm gì bên trong |
|---|---|---|
| `window.save()` | User bấm nút Save | Gọi `docEditor.downloadAs(fileType)` — API **chính thức, công khai** của ONLYOFFICE DocsAPI, không phải hàng hack |
| `window.share()` | User bấm nút Share | Y hệt `save()`, chỉ khác cờ đánh dấu mục đích ("share" thay vì "save"), để lúc nhận kết quả về biết phải mở share sheet hay ghi đè file |
| `window.receiveFileFromIOS(payload)` | Native vừa có file cần mở (mới pick, hoặc mở lần đầu) | Parse payload (base64/byte-array), gọi `virtualServer.open(...)` để nạp file vào server ảo (mục kiến trúc tổng đã nói ở memory) |
| `window.documentHadChange()` | Native cần biết tài liệu có đang dirty không (trước khi cho thoát màn hình, trước khi backgroundapp...) | Trả thẳng `giá trị boolean` hiện tại — native đọc kết quả qua completion handler của `evaluateJavaScript`, kiểu poll chứ không phải push |

**Điểm hay đáng học**: `save()`/`share()` **không tự viết logic export** — chúng chỉ gọi `docEditor.downloadAs(fileType)`, đúng 1 API public ONLYOFFICE cung cấp sẵn cho mọi bên tích hợp dùng để "yêu cầu editor xuất file hiện tại ra". Không có gì bí mật/hack ở bước gọi này cả.

### 5.2 Chiều JS → Native: đây mới thật sự dùng `WKScriptMessageHandler`

Lúc đầu tìm "webkit.messageHandlers" bằng grep chuỗi y nguyên thì ra 0 kết quả — vì code bị minify tách optional-chaining (`?.`) thành biến trung gian, phá vỡ chuỗi ký tự liền. Tìm theo tên hàm mới ra:

```js
// Bản chất y hệt cách mọi app hybrid vẫn làm — không có gì lạ:
function sendToNative(win, payload) {
  const handler = win.webkit?.messageHandlers?.[BRIDGE_NAME]; // BRIDGE_NAME: 1 tên do native đăng ký
  if (!handler) return false;
  handler.postMessage(payload);
  return true;
}
```

Được gọi ở 2 chỗ:
1. **Báo trạng thái loading**: `sendToNative(window, { action: "loading", type: "word" })` — ngay khi bắt đầu mở file, để native show spinner/skeleton của riêng mình (không phải spinner web).
2. **Trả kết quả save/share**: khi `docEditor.downloadAs()` xong (ONLYOFFICE tự convert qua x2t xong), kết quả đổ vào `setExportHandler` callback, JS đóng gói lại và gửi:
   ```js
   docEditor.setExportHandler(async (result) => {
     sendToNative(window, {
       action: pendingAction,           // "save" hoặc "share", set từ bước 5.1
       type: normalizeFileType(result.fileType),  // "word"/"excel"/"ppt"/"pdf"
       base64data: bytesToBase64Chunked(result.data), // encode theo khối 32KB, tránh tràn stack với file lớn
     });
   });
   ```

**Chi tiết nhỏ nhưng đáng chú ý**: hàm encode base64 của họ xử lý theo từng khối 32.768 byte một (`String.fromCharCode(...chunk)` rồi mới `btoa`) thay vì convert nguyên khối 1 lần — vì `String.fromCharCode(...bigArray)` với file lớn (vài MB) sẽ tràn giới hạn số tham số hàm của JS engine và crash. Đây là 1 lỗi thật rất dễ gặp nếu tự viết bridge base64 mà không biết trước — đáng ghi nhớ khi Word Office tự làm bridge riêng.

### 5.3 Có phải MỌI nút đều qua native không? — KHÔNG. Chỉ đúng 3 sự kiện, còn lại 100% ở trong WebView

Đếm lại toàn bộ file host bundle (`index-DRqW9kMl.js`, phần React shell của đối thủ — chưa tính code gốc ONLYOFFICE trong `sdkjs`/`web-apps`): hàm gửi dữ liệu qua native (`AQ()`/`CB()`, tức truy cập `window.webkit.messageHandlers`) **chỉ được gọi ở đúng 3 chỗ trong toàn bộ codebase**:

| # | `action` gửi đi | Khi nào |
|---|---|---|
| 1 | `"loading"` | Vừa bắt đầu mở tài liệu |
| 2 | `"save"` | Kết quả `downloadAs()` trả về, do `save()` kích hoạt |
| 3 | `"share"` | Kết quả `downloadAs()` trả về, do `share()` kích hoạt |

**Không có bất kỳ action nào khác** — không `"bold"`, không `"insertTable"`, không `"undo"`, không `"insertImage"`... Grep `type="file"`/`input type=file` trong host bundle cũng chỉ ra **1 kết quả duy nhất, không liên quan tới ribbon** — nghĩa là kể cả "Insert Picture" (thường nghĩ sẽ cần native photo picker) **cũng không đi qua bridge custom nào** — nó dùng thẳng `<input type="file">` chuẩn của HTML, và bản thân `WKWebView` **tự động** hiện UI chọn ảnh/file gốc của iOS khi người dùng bấm vào input đó — không cần code cầu nối gì thêm, đây là hành vi mặc định của WebKit.

**Kết luận, đúng thứ bạn hỏi**: **không, các nút khác KHÔNG dùng chung cách xử lý với Save/Share/Open.**
- **Nhóm cần rời khỏi WebView** (đúng 3 việc): mở/lưu/chia sẻ file — vì đây là việc chỉ hệ điều hành mới làm được (đọc/ghi file trên máy, mở share sheet). → đi qua bridge native↔JS ở mục 5.1-5.2.
- **Nhóm không rời khỏi WebView** (100% các nút ribbon còn lại — Bold/Italic/Font/Table/Chart/Comment/Undo/Redo/Align/Insert Image từ máy...): xử lý hoàn toàn **nội bộ trong chính engine ONLYOFFICE** (`sdkjs` + `web-apps` gốc, không phải code của đối thủ) — click nút → handler nội bộ của ribbon → gọi thẳng API nội bộ của document model (ví dụ đổi bold, chèn bảng) → engine tự vẽ lại `<canvas>` (mục 4). Đường đi này không cần biết tới Swift/native tồn tại — kể cả nếu app chạy 100% trong trình duyệt thường (không phải app native) thì các nút này vẫn hoạt động y hệt.

**Ý nghĩa cho Word Office khi build thật**: KHÔNG cần tự viết bridge cho từng loại nút định dạng/insert — chỉ cần build đúng 3 điểm nối (mở file, lưu, share) như mục 5.1-5.2. Toàn bộ ribbon còn lại "cứ để ONLYOFFICE tự lo", đúng tinh thần "giữ nguyên ribbon gốc, không rebuild" đã nói ở mục 2.

### 5.4 Vì sao KHÔNG có "reject vì gọi API lạ" khi Apple review

Không cái nào ở đây đụng framework/API private của Apple: `evaluateJavaScript` và `WKScriptMessageHandler` đều là API **công khai, chuẩn** của WebKit, dùng trong mọi app hybrid (Cordova, Capacitor, React Native WebView...). Rủi ro duy nhất thật sự liên quan Apple review nằm ở **nội dung/luồng nghiệp vụ** (ví dụ pending action không rõ ràng khi review, hoặc thiếu error handling khiến app treo) chứ không phải ở kỹ thuật bridge này.

---

## 6. Đề xuất cho Word Office — 2 hướng, nên thử hướng nào trước

| | **Hướng A: Patch `main/` (giống đối thủ)** | **Hướng B: Dùng thẳng `mobile/` (Framework7, chính chủ)** |
|---|---|---|
| Effort ban đầu | Cao — phải tự viết + maintain bộ CSS/JS patch như trên (ribbon, header, context menu, clipboard) | Thấp hơn — UI mobile-first có sẵn, không cần patch gì |
| Rủi ro maintain | Cao — mỗi lần ONLYOFFICE đổi class/id nội bộ, patch có thể vỡ âm thầm (đối thủ đã tự vá bằng cách match theo cấu trúc DOM thay vì hardcode class, nhưng vẫn là kỹ thuật dễ vỡ) | Thấp — đây là API/UI được ONLYOFFICE support chính thức |
| Độ "giống app gốc" hiện tại | Cao (khi làm đúng) — vì giữ nguyên bộ tính năng ribbon đầy đủ | Chưa rõ — **cần test thật** xem bản `mobile/` có đủ tính năng edit (bảng, ảnh, comment, style...) như `main/` không, hay bị cắt bớt |
| Cảm giác native iOS | Trung bình — vẫn là ribbon desktop bị ép co lại | Cao hơn về lý thuyết — Framework7 vốn nhái UI iOS |

**Khuyến nghị**: trước khi quyết định, bỏ ra 1-2 tiếng **test nhanh bản `mobile/` có sẵn** (đã nằm sẵn trong bộ ONLYOFFICE Web Editors, load thử qua URL `.../documenteditor/mobile/index.html` với 1 file mẫu) để xem nó có đủ tính năng cần cho MVP không. Nếu đủ → đỡ phải build lại 100% những gì đối thủ đã làm. Nếu thiếu tính năng quan trọng (ví dụ edit bảng phức tạp) → mới đi hướng A, và lúc đó bộ CSS ở mục 2 là điểm khởi đầu tốt (không phải copy y nguyên — vì đó là code của đối thủ — mà hiểu đúng *chiến lược*: ẩn theo nhóm chức năng vô nghĩa khi offline, giữ nguyên ribbon nhưng cho cuộn ngang, tự vẽ header/title native riêng).

**Việc cần làm chung cho cả 2 hướng** (không phụ thuộc chọn A hay B):
1. Long-press → context menu: bất kỳ hướng nào cũng cần, vì đây là hạn chế chung của mọi trình duyệt di động, không riêng ribbon desktop.
2. Header/title: dùng native SwiftUI toolbar của app, không dùng header web (dù load `main/` hay `mobile/`).
3. Câu hỏi license AGPLv3 (đã ghi trong memory, và mục 11 `ONLYOFFICE_OFFLINE_ARCHITECTURE.md`) áp dụng như nhau cho cả 2 hướng — vì cả `main/` và `mobile/` đều là code ONLYOFFICE Web Editors, không phải "mobile/ thì miễn phí, main/ thì phải trả tiền".

**Chưa code gì ở bước này** — đây là tài liệu research + đề xuất hướng, đợi bạn chọn A/B (hoặc test cả 2 trước) rồi mới update `OfficeEditorViewController.swift`/`OfficeEditorView.swift` (đã có sẵn trong project — xem `ONLYOFFICE_OFFLINE_ARCHITECTURE.md` mục 8-10) theo `rule.md` (present plan + go-ahead trước khi đụng Swift).

---

## 7. Toàn bộ logic — viết lại sạch, sẵn sàng đem dùng (nếu chọn Hướng A)

**Về nguồn gốc**: đã đọc hết cả 3 hàm xử lý chính của đối thủ (~14KB minified cho riêng phần ribbon). Không có dấu hiệu họ lấy từ 1 repo mã nguồn mở nào — kể cả kỹ thuật hay nhất (mục 7.2 dưới) là **monkey-patch thẳng vào class nội bộ của chính ONLYOFFICE** (`Common.UI.Mixtbar`, không có trong tài liệu public) — đọc như hàng họ tự dò ra khi build, không phải copy sẵn ở đâu.

**Đây KHÔNG phải bản sao của đối thủ — quan trọng, đọc trước khi dùng:**
- Toàn bộ code bên dưới là **viết lại từ đầu** theo đúng *kỹ thuật/nguyên lý* quan sát được, không dán nguyên văn 1 dòng code minify nào của họ. Tên hàm, tên biến, cấu trúc file, id CSS (`wordoffice-mobile-chrome`...) — tất cả đặt riêng, không trùng với code của đối thủ.
- Phần **bắt buộc phải giống nhau** chỉ là các `id`/`class` DOM (`#right-menu`, `#statusbar`, `.box-controls`...) — đây là do chính **ONLYOFFICE** đặt tên trong sản phẩm của họ, public, ai tích hợp ONLYOFFICE cũng thấy y hệt, không phải sáng tạo của đối thủ nên không có gì để "giống" cả.
- **Về rủi ro Apple từ chối (Guideline 4.1 "copycat")**: guideline này xét trên *trải nghiệm/concept app* nhìn thấy được (UI, icon, tên, flow) so với 1 app cụ thể khác — không xét đoạn JS/CSS chạy ẩn bên trong WKWebView mà người dùng không thấy. Ribbon sau khi patch trông thế nào là do **thiết kế UI thật của Word Office** (icon, màu, bố cục toolbar riêng) quyết định, không phải do kỹ thuật ẩn/hiện DOM này quyết định — nên cứ tự thiết kế UI khác biệt ở lớp nhìn thấy (đã bàn ở các mục 1-5), còn lớp kỹ thuật "làm sao ép ribbon cuộn ngang" thì dùng chung nguyên lý không sao.
- **Về Guideline 2.5.2 (không được tải code thực thi động)**: đoạn JS dưới đây phải **đóng gói tĩnh trong app bundle** (file `.js` build sẵn, nạp qua `WKUserScript`), không được fetch từ URL ngoài lúc runtime rồi mới chạy — làm đúng vậy thì hoàn toàn hợp lệ, y như mọi app dùng WebView (React Native, Cordova, hybrid app...) vẫn được duyệt bình thường.

Bên dưới là viết lại theo *kỹ thuật/logic* đã quan sát được, đặt tên riêng, có comment giải thích — để bạn hiểu và chỉnh theo đúng nhu cầu Word Office, không phải dán mù.

### 7.1 Ẩn phần chrome vô nghĩa khi offline (tương đương hàm `oE` của đối thủ)

```js
// mobileChrome.js — chạy trong context của trang chứa editor ONLYOFFICE (main/ ribbon)
function applyMobileChromePatch(win, doc, opts) {
  const { hidePresentationLeftPane = false } = opts;

  const CSS = `
    /* 1. Overflow-tab control của ribbon (nút "..." khi hết chỗ) — không cần vì
          ta sẽ ép ribbon cuộn ngang thay vì thu gọn (xem 7.2) */
    .tabs-short, .extra-right,
    [class*="tabs-short"], [class*="extra-right"] {
      display: none !important; width: 0 !important; margin: 0 !important;
    }

    /* 2. Panel phải: chat/comment/collaboration — vô nghĩa khi không có server đồng bộ */
    #right-menu, #id-right-menu, #right-panel,
    [id*="right-panel"], [class*="right-panel"], [class*="rightmenu"] {
      display: none !important; width: 0 !important; margin: 0 !important;
    }

    /* 3. Panel trái (thumbnail slide PPT) — ẩn có điều kiện, để bật lại trên iPad */
    ${hidePresentationLeftPane ? `
    #left-menu, #id-left-menu, #left-panel,
    [id*="left-panel"], [class*="left-panel"], [class*="leftmenu"] {
      display: none !important; width: 0 !important; margin: 0 !important;
    }` : ''}

    /* 4. Ruler — tính năng chỉ có ý nghĩa với chuột + in ấn chính xác trên desktop */
    [id*="ruler"], [class*="ruler"] { display: none !important; }

    /* 5. Header/title bar web gốc — app tự vẽ title bar native SwiftUI riêng */
    body > header, body > [class*="header"], body > [class*="titlebar"],
    #viewport > header, #viewport > [class*="caption"] {
      display: none !important;
    }
    body, #viewport, #editor_sdk {
      padding-top: 0 !important; margin-top: 0 !important; top: 0 !important;
    }

    /* 6. Nút About/Comment — match rộng theo mọi kiểu attribute a11y/tooltip */
    #btn-about, #btn-comments,
    [data-hint*="About"], [data-hint*="Comment"],
    [aria-label*="About"], [aria-label*="Comment"],
    [title*="About"], [title*="Comment"] {
      display: none !important;
    }

    /* 7. Ribbon buttons: KHÔNG ẩn, chỉ cho cuộn ngang mượt kiểu iOS */
    .box-controls {
      overflow-x: auto !important; overflow-y: hidden !important;
      -webkit-overflow-scrolling: touch;
    }
    .box-controls .panel.active {
      width: max-content !important; white-space: nowrap !important;
    }
    .box-controls .panel.static { display: none !important; width: 0 !important; }

    /* 8. Status bar (zoom, số trang): cuộn ngang, phẳng hoá theo tông màu app */
    #statusbar {
      overflow-x: auto !important; -webkit-overflow-scrolling: touch;
      background: #fff !important; border: none !important; box-shadow: none !important;
    }
    #statusbar .statusbar {
      width: max-content !important; white-space: nowrap !important;
    }

    /* 9. Dọn thêm vài control status bar không cần trên mobile (ngôn ngữ, spellcheck) */
    #btn-cnt-lang, #btn-doc-lang, #btn-doc-spell { display: none !important; }
  `;

  if (!doc.getElementById('wordoffice-mobile-chrome')) {
    const style = doc.createElement('style');
    style.id = 'wordoffice-mobile-chrome';
    style.textContent = CSS;
    doc.head.appendChild(style);
  }

  // Header của đối thủ dò theo CẤU TRÚC layout thay vì hardcode 1 class — bền hơn
  // khi ONLYOFFICE đổi tên class giữa các bản. Áp dụng lại kỹ thuật này:
  const appTitle = doc.querySelector('#app-title');
  if (appTitle) {
    let node = appTitle.parentElement;
    while (node) {
      const layoutSiblings = Array.from(node.children)
        .filter(el => el.classList?.contains('layout-item'));
      if (node.querySelector('#app-title') && layoutSiblings.length >= 3) {
        node.style.setProperty('display', 'none', 'important');
        break;
      }
      node = node.parentElement;
    }
  }
}
```

### 7.2 Tắt hành vi "thu gọn nút vào nút …" của ribbon (kỹ thuật hay nhất, đáng dùng nhất)

Đây là phần thật sự đáng lấy: ONLYOFFICE có sẵn 1 class nội bộ `Common.UI.Mixtbar` tự động thu gọn ribbon khi hết chỗ ngang (giống Word desktop khi thu nhỏ cửa sổ — các nút bị gom vào nút "..."). Trên mobile ta KHÔNG muốn hành vi này (muốn cuộn ngang thay vì thu gọn), nên patch thẳng 2 method của nó:

```js
function disableToolbarCollapse(win) {
  const proto = win.Common?.UI?.Mixtbar?.prototype;
  if (!proto || proto.__mobilePatchApplied) return !!proto;
  proto.__mobilePatchApplied = true;

  // Gốc: khi hết chỗ, ribbon gọi hàm này để GOM bớt nút vào nút "...".
  // Ép nó làm ngược lại — luôn "trả hết nút ra ngoài" (moveAllFromMoreButton).
  const originalSetMoreButton = proto.setMoreButton;
  proto.setMoreButton = function (tab) {
    this.moveAllFromMoreButton?.(tab);
    this.$moreBar = null; // vô hiệu tham chiếu tới nút "..." để nó không tự bật lại
    return this;
  };

  // Gốc: tính lại layout ribbon mỗi khi resize/đổi tab — ép nowrap thay vì wrap/thu gọn.
  proto.resizeToolbar = function (tab) {
    const activePanel = this.$panels?.filter?.('.active');
    const tabId = activePanel?.attr?.('data-tab');
    if (tabId) this.moveAllFromMoreButton?.(tabId);
    activePanel?.css?.({ whiteSpace: 'nowrap' });
    return this;
  };

  win.requestAnimationFrame(() => win.dispatchEvent(new Event('resize')));
  return true;
}
```

**Vì sao cần cả 7.1 lẫn 7.2**: 7.1 (CSS `.box-controls { overflow-x:auto }`) chỉ cho phép cuộn — nhưng nếu ONLYOFFICE vẫn tự thu gọn nút vào "..." trước (do `Mixtbar` gốc), bạn sẽ thấy ribbon ngắn ngủn với 1 nút "..." chứ không phải dải nút dài để cuộn. 7.2 mới là thứ khiến "cuộn ngang thay vì thu gọn" thật sự xảy ra.

### 7.3 Poll lại định kỳ — vì ONLYOFFICE tự re-render, patch 1 lần không đủ

```js
function keepPatched(win, doc, opts) {
  disableToolbarCollapse(win); // thử patch ngay — nếu Mixtbar đã load thì xong luôn

  const pollUntilReady = setInterval(() => {
    if (disableToolbarCollapse(win)) clearInterval(pollUntilReady);
  }, 300);

  // ONLYOFFICE re-render DOM khi đổi tab/mở panel — apply lại CSS/hide liên tục.
  // Gợi ý: MutationObserver sạch hơn polling, nhưng đối thủ dùng interval 300ms vì
  // đơn giản, không cần lo debounce khi ONLYOFFICE đổi DOM dồn dập. Chọn 1 trong 2:
  const reapply = setInterval(() => applyMobileChromePatch(win, doc, opts), 300);

  // return cleanup — gọi khi rời màn hình editor
  return () => { clearInterval(pollUntilReady); clearInterval(reapply); };
}
```

### 7.4 Long-press → context menu (nguyên hàm `rE`, viết lại sạch)

```js
function installLongPressContextMenu(doc) {
  const HOLD_MS = 500, MOVE_TOLERANCE_PX = 10;
  let timer = null, startX = 0, startY = 0, curX = 0, curY = 0;

  const cancel = () => { if (timer) clearTimeout(timer); timer = null; };
  const fireContextMenu = () => {
    timer = null;
    const target = doc.elementFromPoint(curX, curY) ?? doc.body;
    target.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true, cancelable: true, button: 2, buttons: 2,
      clientX: curX, clientY: curY,
    }));
  };

  doc.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'mouse') return;
    cancel();
    startX = curX = e.clientX; startY = curY = e.clientY;
    timer = setTimeout(fireContextMenu, HOLD_MS);
  }, true);

  doc.addEventListener('pointermove', (e) => {
    if (!timer) return;
    curX = e.clientX; curY = e.clientY;
    const dist = Math.hypot(curX - startX, curY - startY);
    if (dist > MOVE_TOLERANCE_PX) cancel(); // coi là scroll/drag, không phải giữ tay
  }, true);

  doc.addEventListener('pointerup', cancel, true);
  doc.addEventListener('pointercancel', cancel, true);
}
```

### 7.5 Nối clipboard hệ thống ↔ Clipboard Web API (nguyên hàm `gE`, viết lại sạch)

```js
function installClipboardBridge(win, doc) {
  const isSecure = win.isSecureContext ?? win.location.protocol === 'https:';
  if (!isSecure || typeof win.navigator.clipboard?.writeText !== 'function') return;

  doc.addEventListener('copy', (e) => {
    const text = e.clipboardData?.getData('text/plain');
    if (text) win.navigator.clipboard.writeText(text).catch(() => {});
  }, true);

  doc.addEventListener('keydown', (e) => {
    const isPasteShortcut = (e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V');
    if (!isPasteShortcut) return;
    const target = e.target;
    const isNativeInput = target instanceof win.HTMLInputElement
      || target instanceof win.HTMLTextAreaElement
      || target?.isContentEditable;
    if (isNativeInput) return; // để trình duyệt tự xử lý paste bình thường

    e.preventDefault();
    win.navigator.clipboard.readText().then((text) => {
      const dt = new DataTransfer();
      dt.setData('text/plain', text);
      const editorRoot = doc.getElementById('editor_sdk') ?? doc.body;
      editorRoot.dispatchEvent(new ClipboardEvent('paste', {
        clipboardData: dt, bubbles: true, cancelable: true,
      }));
    }).catch(() => {});
  }, true);
}
```

### 7.6 Cách nhúng vào WKWebView (Swift) — chỉ là hướng đi, chưa phải code thật

**Cập nhật 2026-09-16**: project này giờ đã có sẵn `OfficeEditorViewController.swift`/`OfficeEditorView.swift`/`OfficeBridge.swift`/`OfficeSchemeHandler.swift` thật (xem `ONLYOFFICE_OFFLINE_ARCHITECTURE.md` mục 8-10) — các hàm 7.1-7.5 ở trên nên nhúng vào **đúng những file đã có sẵn này**, không tạo file editor mới song song.

- Gộp 7.1–7.5 thành 1 file `wordoffice-mobile-chrome.js`, nạp vào `WKWebView` (trong `OfficeEditorViewController.swift`) qua `WKUserScript(source:, injectionTime: .atDocumentEnd, forMainFrameOnly: true)` — chạy tự động mỗi lần trang load, không cần gọi `evaluateJavaScript` thủ công.
- Gọi `keepPatched(window, document, { hidePresentationLeftPane: <true nếu iPhone, false nếu iPad> })` ở cuối script — giá trị `hidePresentationLeftPane` truyền từ Swift qua bằng cách build chuỗi JS động (giống `UIDevice.current.userInterfaceIdiom == .phone`), hoặc đơn giản hơn: base ngay trên `window.innerWidth` trong JS luôn, khỏi cần Swift can thiệp.
- Tắt bounce/rubber-band của `webView.scrollView.bounces = false` — không liên quan tới đối thủ, nhưng nên làm cùng lúc vì cùng mục tiêu "bớt cảm giác web".

**Vẫn giữ nguyên nguyên tắc rule.md**: đây là code JS tham khảo để bạn review/chỉnh, chưa đụng vào file Swift nào trong Xcode project. Báo lại nếu muốn mình nhúng thật vào `OfficeEditorViewController.swift` (kèm `/code-review` sau khi build xong).
