# ONLYOFFICE Offline Architecture — Word Office iOS

## 1. Tổng quan

Kiến trúc này chạy ONLYOFFICE hoàn toàn trên device, không cần server, không cần internet.
Xác nhận từ phân tích đối thủ `com.codeharmonylabs.sheetai` (Office Word – Edit Word Docs v1.5.1).

**Kết luận chính:** Backend KHÔNG bắt buộc cho MVP edit offline DOCX/XLSX/PPTX.

---

## 2. Kiến trúc tổng thể

```
┌─────────────────────────────────────────────────────┐
│                  Native iOS (Swift)                  │
│                                                      │
│  1. Đọc file từ URL (security-scoped)               │
│  2. Gọi bridge: receiveFileFromIOS(name, ext, data) │
│  3. Nhận kết quả: handleEditorMessage(base64, type) │
│  4. Ghi file edited về disk                         │
└──────────────────────┬──────────────────────────────┘
                       │ WKWebView JS bridge
                       ▼
┌─────────────────────────────────────────────────────┐
│              WKWebView (local HTML bundle)           │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │          Virtual Document Server            │   │
│  │   (JS fetch/XHR interceptor)                │   │
│  │                                             │   │
│  │  /downloadfile/{key}  → in-memory blob      │   │
│  │  /downloadas/{key}    → x2t convert & return│   │
│  │  /upload/{key}        → store in memory     │   │
│  │  /plugins.json        → empty plugin list   │   │
│  └──────────────────┬──────────────────────────┘   │
│                     │                               │
│  ┌──────────────────▼──────────────────────────┐   │
│  │         ONLYOFFICE DocsAPI.DocEditor        │   │
│  │   (documenteditor / spreadsheeteditor /     │   │
│  │    presentationeditor — bundled JS assets)  │   │
│  └──────────────────┬──────────────────────────┘   │
│                     │                               │
│  ┌──────────────────▼──────────────────────────┐   │
│  │            x2t.wasm (Web Worker)            │   │
│  │   DOCX/XLSX/PPTX ↔ ONLYOFFICE internal     │   │
│  │   format (AVS binary canvas)                │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## 3. Luồng mở file

```
Swift: đọc file → base64
    ↓ callAsyncJavaScript("receiveFileFromIOS", args)
JS: nhận {fileName, fileType, base64data}
    ↓ decode base64 → ArrayBuffer
x2t.worker: convert DOCX → ONLYOFFICE internal format
    ↓ file nội bộ lưu vào virtual FS (memory)
Virtual Doc Server: đăng ký key → trả URL ảo
    ↓
DocsAPI.DocEditor({document: {url: "virtual://..."}})
    ↓
Editor render (hoàn toàn in-browser, không gọi ra ngoài)
```

## 4. Luồng lưu file

```
User: Cmd+S / Save button
    ↓
DocsAPI: downloadAs(fileType) → ONLYOFFICE export nội bộ
    ↓
x2t.wasm: convert ONLYOFFICE internal → DOCX/XLSX/PPTX
    ↓
JS: tạo {action:"save", type:"docx", base64data:"..."}
    ↓ window.webkit.messageHandlers.editorBridge.postMessage
Swift: decode base64 → Data → ghi file về URL gốc
```

---

## 5. Virtual Document Server — chi tiết

ONLYOFFICE Web Editor mặc định giao tiếp với Document Server qua HTTP.
Virtual Doc Server là một JS interceptor monkey-patch lại `fetch` và `XMLHttpRequest`
để xử lý nội bộ, không gọi ra internet.

### Các path cần interceptor

| Path | Mục đích | Xử lý |
|---|---|---|
| `GET /downloadfile/{key}` | Editor fetch file để render | Trả về blob từ memory |
| `GET /downloadas/{key}/{fmt}` | Export sang format khác | Chạy x2t convert, trả blob |
| `POST /upload` | Editor upload converted file | Lưu vào memory map |
| `GET /plugins.json` | Danh sách plugin | Trả `{plugins:[]}` |
| WebSocket `wss://*/doc/{key}` | Co-editing session | Fake WebSocket stub (single user) |

### Giả WebSocket (co-editing stub)

ONLYOFFICE yêu cầu WebSocket để sync trạng thái. Với single-user offline,
dùng một stub WebSocket object trả lại `open` event ngay lập tức và ignore mọi message.

---

## 6. x2t.wasm — ĐÃ GIẢI QUYẾT ✅ (2026-09-10)

### Nguồn x2t.wasm

Docker container KHÔNG chứa x2t.wasm (chỉ có native ELF). Tuy nhiên:

**`wasm-onlyoffice-sdk`** (npm AGPL-3.0) cung cấp x2t.wasm:
- https://www.npmjs.com/package/wasm-onlyoffice-sdk (by oonxt)
- x2t.wasm CDN: https://github.com/oonxt/wasm-onlyoffice-demo (gh-pages/x2t)

| File | Kích thước | Location trong bundle |
|---|---|---|
| `x2t.wasm` (Emscripten, AGPL) | 63 MB | `OfficeBundle/x2t/x2t.wasm` |
| `x2t.js` (Emscripten bootstrap) | 165 KB | `OfficeBundle/x2t/x2t.js` |
| `sdk-core/index.mjs` | 108 KB | `OfficeBundle/sdk-core/index.mjs` |

**Tất cả đã được download và đặt trong `Word Office/Resources/OfficeBundle/`.**

---

## 7. Bundle size strategy

ONLYOFFICE web-apps đầy đủ rất lớn (~500MB+). Chiến lược cho iOS:

| Component | Bắt buộc bundle | Có thể lazy-load |
|---|---|---|
| `api.js` | ✅ (nhỏ, ~50KB) | — |
| `documenteditor` JS | ✅ nếu support DOCX | — |
| `spreadsheeteditor` JS | ✅ nếu support XLSX | — |
| `presentationeditor` JS | ✅ nếu support PPTX | — |
| `x2t.wasm` | ✅ bắt buộc | Có thể download lần đầu |
| Fonts | ⚠️ bundle tối thiểu | Lazy load thêm |
| Plugins | ❌ không cần MVP | — |
| `pdfeditor` | ❌ dùng PDFKit native | — |

**Chiến lược MVP:** Bundle sẵn 3 editor JS + x2t.wasm vào app bundle.
Download thêm fonts on-demand nếu cần.

---

## 8. Swift ↔ JS Bridge

### Swift → JS (gửi file vào editor)

```swift
func openFile(url: URL) async throws {
    let data = try Data(contentsOf: url)
    let payload: [String: Any] = [
        "fileName": url.lastPathComponent,
        "fileType": url.pathExtension.lowercased(),
        "base64data": data.base64EncodedString()
    ]
    try await webView.callAsyncJavaScript(
        "window.receiveFileFromIOS(payload)",
        arguments: ["payload": payload],
        contentWorld: .page
    )
}
```

### JS → Swift (nhận file đã edit)

```swift
// WKScriptMessageHandler
func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
) {
    guard message.name == "editorBridge",
          let body = message.body as? [String: Any],
          let action = body["action"] as? String,
          let base64 = body["base64data"] as? String,
          let type = body["type"] as? String,
          let data = Data(base64Encoded: base64)
    else { return }

    switch action {
    case "save":  saveEditedFile(data, ext: type)
    case "share": presentShareSheet(data, ext: type)
    default: break
    }
}
```

---

## 9. So sánh: Server-based vs Offline bundle

| | Server-based (02-onlyoffice) | Offline bundle (kiến trúc này) |
|---|---|---|
| **Backend** | Docker + Node.js + VPS | Không cần |
| **Internet** | Bắt buộc | Không cần |
| **Chi phí** | ~$10/tháng Railway.app | $0 (sau khi có x2t.wasm) |
| **Latency** | Upload/download round-trip | Instant (on-device) |
| **App size** | Nhỏ (~50MB) | Lớn (~300–500MB) |
| **Offline** | ❌ | ✅ |
| **App Store** | Cần HTTPS server | ✅ không cần |
| **Fidelity** | ONLYOFFICE full | ONLYOFFICE full (same engine) |
| **x2t.wasm** | Không cần (server có x2t native) | ⚠️ Cần — blocker hiện tại |
| **TestFlight MVP** | ✅ Khả thi ngay | ❌ Blocked cho đến khi có x2t.wasm |

**Kết luận thực tế:**
- **TestFlight MVP** → Server-based trên Railway.app (làm được ngay)
- **Production / offline** → Offline bundle sau khi giải quyết x2t.wasm

---

## 10. Roadmap

### ✅ Đã làm (server-based test harness — 02-onlyoffice)
- [x] ONLYOFFICE chạy trong Docker, fidelity DOCX/XLSX/PPTX xác nhận ✅
- [x] server.js với upload/editor/callback/download API
- [x] iOS integration: ONLYOFFICEAPIClient + ONLYOFFICEEditorView (server-based)

### ✅ ĐÃ IMPLEMENT: Offline approach (2026-09-10)
- [x] Tìm `wasm-onlyoffice-sdk` (npm, AGPL-3.0) — cung cấp x2t.wasm sẵn
- [x] Download x2t.js + x2t.wasm (63MB) từ gh-pages CDN
- [x] Copy sdk-core (index.mjs + x2t.worker) từ npm package
- [x] Download api.js + preload.html + scaffold HTML cho 3 editor types
- [x] `OfficeBundle/editor.html` — bootstrap HTML với EditorServer + XHR proxy + Swift bridge
- [x] `OfficeSchemeHandler.swift` — WKURLSchemeHandler cho `office://`
- [x] `OfficeBridge.swift` — WKScriptMessageHandler (Swift ← JS)
- [x] `OfficeEditorViewController.swift` — WKWebView host VC
- [x] `OfficeEditorView.swift` — SwiftUI wrapper (thay ONLYOFFICEEditorView)
- [x] `EditorPlaceholderView.swift` — updated sang OfficeEditorView

### ✅ Xcode integration DONE (2026-09-10)
- [x] Swift files — auto via `PBXFileSystemSynchronizedRootGroup` (Xcode 26, objectVersion 77)
- [x] `OfficeBundle` moved to `Word Office/OfficeBundle/` (SOURCE_ROOT) → added as `PBXFileReference` (lastKnownFileType=folder) + `PBXBuildFile` in Resources phase
- [ ] Clean Build (Shift+Cmd+K) + test trên device/simulator

### 🔮 Phase 2 — True offline (không cần internet lần đầu)
- [ ] Bundle sdkjs (word/cell/slide) ~86MB → ~30MB compressed
- [ ] Remove CDN base href từ scaffold HTML → serve hoàn toàn offline
- [ ] Bundle minimal font subset

---

## 11. Nguồn tham khảo

- Phân tích đối thủ: `com.codeharmonylabs.sheetai` v1.5.1 (`~/Downloads/OfficeWord_Logic_Processing.md`)
- ONLYOFFICE Document Server Docker image: `onlyoffice/documentserver:latest`
- Test harness (server-based, dùng để verify fidelity): `SDK-Integration-Test/02-onlyoffice/`
- ONLYOFFICE license: AGPL-3.0 (cần commercial license để ship App Store)
