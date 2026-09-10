# ONLYOFFICE Offline Editor — Xcode Setup Guide

All Swift source files and the `OfficeBundle` assets are created.
You need to add them to the Xcode target manually (Xcode cannot auto-detect new files).

---

## 1. Add Swift files to the Word Office target

In Xcode, right-click each folder and choose **"Add Files to 'Word Office'..."**.
Make sure **"Add to targets: Word Office"** is checked.

### New Swift files to add:

| File | Group in Xcode |
|------|----------------|
| `Services/Implementations/ONLYOFFICE/Offline/OfficeSchemeHandler.swift` | ONLYOFFICE/Offline |
| `Services/Implementations/ONLYOFFICE/Offline/OfficeBridge.swift` | ONLYOFFICE/Offline |
| `Views/Editor/OfficeEditorViewController.swift` | Views/Editor |
| `Views/Editor/OfficeEditorView.swift` | Views/Editor |

---

## 2. Add OfficeBundle as a folder reference

> **Important:** Add as a **folder reference** (blue folder icon), NOT as a group.
> This ensures the entire directory tree is copied to the app bundle as-is.

1. In Xcode Navigator, right-click **Resources** → **"Add Files to 'Word Office'..."**
2. Navigate to `Word Office/Resources/OfficeBundle`
3. Select the `OfficeBundle` folder
4. Choose **"Create folder references"** (NOT "Create groups")
5. Make sure **"Add to targets: Word Office"** is checked
6. Click **Add**

The folder should appear with a **blue icon** in the Navigator.

### OfficeBundle structure (verify after adding):
```
OfficeBundle/
├── editor.html              ← bootstrap HTML loaded by WKWebView
├── sdk-core/
│   ├── index.mjs            ← wasm-onlyoffice-sdk core (108KB)
│   └── assets/
│       └── x2t.worker-CjNFjWSw.js  ← Web Worker for x2t (8.9KB)
├── x2t/
│   ├── x2t.js              ← Emscripten bootstrap (165KB)
│   └── x2t.wasm            ← x2t WebAssembly binary (63MB)
└── web-apps/
    └── apps/
        ├── api/documents/
        │   ├── api.js          ← ONLYOFFICE DocsAPI (64KB)
        │   └── preload.html    ← cache warming page
        ├── documenteditor/main/index.html    ← Word editor scaffold
        ├── spreadsheeteditor/main/index.html ← Excel editor scaffold
        └── presentationeditor/main/index.html ← PPT editor scaffold
```

---

## 3. Add ATS exception in Info.plist (already done if server-based was configured)

The scaffold HTML files reference CDN resources at `https://oonxt.github.io/...` 
(for sdkjs — loaded on first use and cached by WKWebView). 
No special ATS config needed since these are https:// URLs.

---

## 4. Clean build after adding

After adding `OfficeBundle` as a folder reference, do:
- **Product → Clean Build Folder** (Shift+Cmd+K)
- Then **Build** (Cmd+B)

---

## 5. First-launch behavior

| Condition | Behavior |
|-----------|----------|
| **No internet, first use** | ✅ editor.html loads, x2t.wasm loads (from bundle), but sdkjs loads from CDN → editor won't show until internet available |
| **Internet, first use** | ✅ sdkjs (~86MB) downloads from CDN, WKWebView caches it |
| **Subsequent uses (no internet)** | ✅ fully offline — sdkjs served from WKWebView cache, x2t from bundle |

> **Phase 2 (future):** Bundle sdkjs (~86MB → ~30MB compressed in app store) 
> for true offline on first use, without CDN dependency.

---

## 6. Files changed in this session

- `Views/Editor/EditorPlaceholderView.swift` — office formats now use `OfficeEditorView`
- `Resources/OfficeBundle/` — new directory with all offline assets  
- `Services/Implementations/ONLYOFFICE/Offline/` — new directory with scheme handler + bridge
- `Views/Editor/OfficeEditorView.swift` — new SwiftUI wrapper
- `Views/Editor/OfficeEditorViewController.swift` — new WKWebView host VC

The server-based files (`ONLYOFFICEAPIClient.swift`, `ONLYOFFICEEditorView.swift`, 
`ONLYOFFICEConfig.swift`) and `DependencyContainer.onlyofficeAPIClient` are 
**no longer used** — you may delete them after confirming the offline editor works.
