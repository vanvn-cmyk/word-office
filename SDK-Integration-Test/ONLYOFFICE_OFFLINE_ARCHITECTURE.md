# ONLYOFFICE Offline iOS Architecture

> Dựa trên phân tích đối thủ (`OfficeWord_Logic_Processing.md`) + ONLYOFFICE 9.x bundle structure.  
> Mục tiêu: chạy ONLYOFFICE hoàn toàn on-device, không cần server, không cần internet.

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────┐
│                   Native iOS (Swift)                    │
│  - Quản lý file (URL, security scope, sandbox)          │
│  - Điều hướng / tab bar / library                       │
│  - StoreKit (subscription)                              │
│  - WKWebView host                                       │
└────────────────────┬────────────────────────────────────┘
                     │  WKWebView (full-screen)
                     │  + WKScriptMessageHandler bridge
┌────────────────────▼────────────────────────────────────┐
│                React/Vite shell (bundled in IPA)        │
│  - Nhận file từ iOS qua JS bridge                       │
│  - Khởi tạo DocsAPI.DocEditor                           │
│  - Virtual Document Server (interceptor)                │
└──────┬──────────────────────────────────┬───────────────┘
       │                                  │
┌──────▼──────┐                  ┌────────▼──────────────┐
│  ONLYOFFICE │                  │  x2t.wasm (Web Worker)│
│  Web Editor │◄─────────────────│  - DOCX/XLSX/PPTX →   │
│  (DocsAPI)  │                  │    ONLYOFFICE format   │
│             │─────────────────►│  - ONLYOFFICE format → │
│             │                  │    DOCX/XLSX/PPTX      │
└─────────────┘                  └───────────────────────┘
```

**Kết quả:** 100% offline, không cần VPS, không cần Firebase, không cần network khi edit.

---

## 2. Các thành phần cần bundle vào IPA

### 2.1 ONLYOFFICE Web Editors (từ Docker image hoặc npm)

```
web-apps/
├── apps/
│   ├── api/documents/api.js          ← DocsAPI entry point
│   ├── documenteditor/               ← Word editor (~50MB)
│   │   └── main/
│   │       ├── index.html
│   │       ├── app.js
│   │       └── ...
│   ├── spreadsheeteditor/            ← Excel editor (~50MB)
│   │   └── main/ ...
│   └── presentationeditor/           ← PowerPoint editor (~50MB)
│       └── main/ ...
├── sdkjs/                            ← Core SDK JS (~100MB)
│   ├── word/
│   ├── cell/
│   ├── slide/
│   └── common/
└── fonts/                            ← Office fonts (~30MB)
    └── ...
```

### 2.2 x2t Format Converter

```
x2t/
├── x2t.wasm          ← WebAssembly binary (~8MB)
├── x2t.js            ← JS loader/wrapper
└── x2t.worker.js     ← Web Worker runner
```

Nguồn chính thức: npm package `@onlyoffice/x2t-wasm`  
Hoặc extract từ Docker image: `/var/www/onlyoffice/documentserver/server/FileConverter/bin/`

### 2.3 Shell app (React/Vite)

File tự viết, bundle cùng IPA:
```
editor-shell/
├── index.html
├── main.js           ← Virtual doc server + DocsAPI init
├── bridge.js         ← iOS ↔ JS message handlers
└── worker.js         ← x2t Web Worker wrapper
```

**Tổng dung lượng ước tính:** ~250–350MB (sau khi lazy-load theo loại file)

---

## 3. Virtual Document Server

ONLYOFFICE Web Editor mặc định kỳ vọng một Document Server thật ở backend. Thay vào đó, ta **intercept** toàn bộ request bằng JS trước khi nó đi ra network.

### 3.1 Request paths cần intercept

```javascript
// Intercept fetch + XMLHttpRequest
const VIRTUAL_ROUTES = {
  '/downloadfile/:key':  handleDownloadFile,   // Editor tải file về để render
  '/downloadas/:key':    handleDownloadAs,      // Export sang format khác
  '/upload/:key':        handleUpload,          // Editor upload file tạm
  '/coauthoring/...':    handleCoauthoring,     // Co-editing (mock, single user)
  '/plugins.json':       handlePlugins,         // Plugin list (trả [] rỗng)
  '/info/info.json':     handleInfo,            // Server info
};
```

### 3.2 Luồng mở file

```
iOS gọi: webView.callAsyncJavaScript("receiveFileFromIOS", args: payload)
    ↓
payload = { fileName, fileType, base64data }
    ↓
bridge.js nhận → gọi x2t.worker.js
    ↓
x2t.wasm convert: DOCX → ONLYOFFICE internal format (.bin)
    ↓
Lưu vào Virtual FS (IndexedDB / in-memory)
    ↓
DocsAPI.DocEditor init với virtualUrl = "virtual://doc/current"
    ↓
Editor gọi GET /downloadfile/current → Virtual Server trả nội dung từ Virtual FS
    ↓
Editor render ✓
```

### 3.3 Luồng lưu file

```
User bấm Cmd+S hoặc Save button
    ↓
ONLYOFFICE gọi onRequestSaveAs / downloadAs("docx")
    ↓
Editor gọi GET /downloadas/current?outputtype=docx
    ↓
Virtual Server gọi x2t.wasm: ONLYOFFICE format → DOCX binary
    ↓
Virtual Server trả file binary về editor
    ↓
bridge.js nhận binary → encode Base64 → postMessage sang iOS
    ↓
Swift WKScriptMessageHandler nhận → decode → ghi file ra disk
```

---

## 4. Swift ↔ JavaScript Bridge

### 4.1 iOS → JS (gửi file vào editor)

```swift
// Gọi khi user mở file
func openFileInEditor(url: URL) async throws {
    let data = try Data(contentsOf: url)
    let payload: [String: Any] = [
        "fileName": url.lastPathComponent,
        "fileType": url.pathExtension.lowercased(),
        "base64data": data.base64EncodedString()
    ]
    try await webView.callAsyncJavaScript(
        "window.receiveFileFromIOS(payload)",
        arguments: ["payload": payload],
        in: nil,
        in: .page
    )
}
```

### 4.2 JS → iOS (nhận file đã edit)

```swift
// WKScriptMessageHandler
func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
) {
    guard let body = message.body as? [String: Any] else { return }
    switch message.name {
    case "editorSave":
        let base64 = body["base64data"] as! String
        let type   = body["type"] as! String          // "docx" | "xlsx" | "pptx"
        let data   = Data(base64Encoded: base64)!
        saveEditedFile(data: data, ext: type)
    case "editorStateChange":
        let dirty  = body["dirty"] as! Bool
        updateDirtyState(dirty)
    case "editorError":
        let msg    = body["message"] as! String
        showError(msg)
    default: break
    }
}
```

### 4.3 Đăng ký message handlers

```swift
let config = WKWebViewConfiguration()
let contentController = WKUserContentController()
contentController.add(self, name: "editorSave")
contentController.add(self, name: "editorStateChange")
contentController.add(self, name: "editorError")
config.userContentController = contentController
```

---

## 5. Kế hoạch triển khai

### Phase 1 — Bundle setup (1–2 ngày)
- [ ] Extract x2t.wasm từ Docker image hoặc npm `@onlyoffice/x2t-wasm`
- [ ] Extract web-apps bundle (documenteditor/spreadsheeteditor/presentationeditor)
- [ ] Xác định lazy-loading strategy (chỉ load editor type cần thiết)
- [ ] Tạo Xcode bundle resource group `ONLYOFFICEBundle/`

### Phase 2 — Virtual Document Server (2–3 ngày)
- [ ] Viết `virtual-server.js`: intercept fetch/XHR
- [ ] Implement `handleDownloadFile` (serve từ in-memory FS)
- [ ] Implement `handleDownloadAs` (trigger x2t export)
- [ ] Implement `handleUpload` (nhận từ editor)
- [ ] Mock coauthoring endpoint (single-user, luôn trả OK)

### Phase 3 — x2t Worker (1–2 ngày)
- [ ] Viết `x2t.worker.js`: wrap x2t.wasm API
- [ ] Implement `convertToInternal(fileData, fileType)` → internal bin
- [ ] Implement `convertFromInternal(binData, targetType)` → DOCX/XLSX/PPTX
- [ ] Test với sample files

### Phase 4 — Swift Bridge + Editor Shell (2–3 ngày)
- [ ] Viết `ONLYOFFICEBundleEditorView.swift` (thay `ONLYOFFICEEditorView.swift` hiện tại)
- [ ] Implement `openFileInEditor(url:)` + file reading
- [ ] Implement `WKScriptMessageHandler` cho save/stateChange/error
- [ ] Wire vào `EditorPlaceholderView` (thay API client approach)

### Phase 5 — Testing & optimization (2–3 ngày)
- [ ] Test DOCX / XLSX / PPTX với nhiều loại nội dung
- [ ] Kiểm tra memory usage (file lớn + x2t)
- [ ] Lazy-load: chỉ load editor type cần (word/cell/slide)
- [ ] Autosave: call `downloadAs` định kỳ → ghi file

---

## 6. Lưu ý quan trọng

### Bộ nhớ
- x2t.wasm chạy trong Web Worker (không block main thread)
- Không giữ nhiều base64 cùng lúc: xử lý xong → giải phóng
- File >10MB: dùng chunked transfer hoặc file:// URL thay vì base64

### License
- ONLYOFFICE Document Server: AGPLv3 (cần commercial license cho app store)
- x2t: cùng license với Document Server
- Liên hệ ONLYOFFICE để mua OEM license trước khi ship production

### App Store
- Không cần `NSAllowsArbitraryLoads` (không có HTTP call ra ngoài)
- WKWebView load local bundle: dùng `loadFileURL(_:allowingReadAccessTo:)`
- Không cần background network entitlement

### So sánh với approach hiện tại (server-based)

| | Server approach (02-onlyoffice) | Bundle approach (offline) |
|---|---|---|
| Internet required | ✅ Luôn cần | ❌ Không cần |
| Server cost | $24+/tháng | $0 |
| App Store ready | ⚠️ HTTPS required | ✅ Sẵn sàng |
| IPA size | Nhỏ (~50MB) | Lớn (~300MB) |
| Setup complexity | Cao (VPS, Docker) | Trung bình (bundle assets) |
| Phù hợp MVP | Test/dev only | ✅ Production |

---

## 7. Nguồn tài nguyên

| Tài nguyên | Nguồn |
|---|---|
| x2t.wasm | `npm install @onlyoffice/x2t-wasm` |
| Web editors bundle | Extract từ Docker: `/var/www/onlyoffice/documentserver/web-apps/` |
| ONLYOFFICE API docs | https://api.onlyoffice.com/editors/basic |
| Virtual server reference | Phân tích IPA đối thủ (`OfficeWord_Logic_Processing.md`) |
| Commercial license | https://www.onlyoffice.com/developer-edition.aspx |

---

*Tài liệu này mô tả kiến trúc target cho Word Office MVP offline editor.  
Server-based approach (`02-onlyoffice/`) giữ lại để reference và test fidelity.*
