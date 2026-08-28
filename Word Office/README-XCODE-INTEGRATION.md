# Xcode Integration — Sprint 0.1 Skeleton

Created 2026-08-26 · arch v2.1 · Files created outside Xcode need to be **added to the Xcode project** before they compile.

---

## What was created

| Kind | Count | Location |
|---|---:|---|
| Swift files (real code) | ~40 | `App/`, `DesignSystem/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Extensions/` |
| Swift files (placeholder for Sprint 0.2–0.5) | ~60 | scattered — each has `// TODO Sprint 0.X` header |
| Asset Catalog color sets | 52 | `Assets.xcassets/` (Brand, Background, Surface, Text, Border, Status, Document, Overlay, Selection, Button) |
| Removed | 2 | `Word_OfficeApp.swift` + `ContentView.swift` at root (template scaffolding) |

## Step 1 — Add folder groups to Xcode

Open `Word Office.xcodeproj` in Xcode 16+.

1. In the Project Navigator (left panel), **right-click** on the top-level `Word Office` group.
2. Choose **Add Files to "Word Office"…**
3. Select the following folders (⌘-click for multi-select) — set **"Create groups"** (NOT "Create folder references"):
   - `App/`
   - `DesignSystem/`
   - `Models/`
   - `Services/`
   - `ViewModels/`
   - `Views/`
   - `Extensions/`
   - `Resources/` (once populated Sprint 0.1)
4. Ensure **"Add to targets: Word Office"** is checked.
5. Click **Add**.

The 52 new `.colorset` folders inside `Assets.xcassets/` are automatically picked up — no manual step needed.

## Step 2 — Enable Swift 6 strict concurrency (C4)

Xcode → target **Word Office** → **Build Settings** → search `strict concurrency`.

- Set **Strict Concurrency Checking** = **Complete**

Fix all warnings same day. If Artifex SDK types (Sprint 0.2) aren't `Sendable`, wrap them in `@unchecked Sendable` isolated inside `Services/Implementations/SDK/Real/*.swift` with a comment explaining why.

## Step 3 — Set up 2 build configs for Mock ↔ Real SDK swap (C3)

Xcode → **project** (not target) → **Info** tab → **Configurations** section.

1. Duplicate `Debug` → rename to `Debug-Mock`
2. Duplicate `Debug` → rename to `Debug-Real`
3. Target **Word Office** → **Build Settings** → search `active compilation conditions`
4. Under **Debug-Mock**, add flag: `USE_MOCK_SDK`
5. Under **Debug-Real**, leave empty (Real Artifex code compiles in)

Create 2 schemes (Product → Scheme → Manage Schemes… → duplicate):
- **Word Office (Mock)** → build config `Debug-Mock`
- **Word Office (Real)** → build config `Debug-Real`

Sprint 0.1: everyone runs the Mock scheme. When Artifex license lands Sprint 0.2, switch to Real scheme.

## Step 4 — Mac Catalyst PoC (C1)

Xcode → target → **General** → **Supported Destinations** → verify **Mac (Mac Catalyst)** is listed.

Build & run on Mac Catalyst destination. Verify:
- `NavigationSplitView` 3-column layout renders correctly
- `columnVisibility` binding persists across launches (N3)
- Sidebar hover states work with mouse pointer
- Toolbar buttons visible and clickable

If any of the above break → wrap the offending code in `#if targetEnvironment(macCatalyst)` fallback.

## Step 5 — Delete stale scheme reference

If Xcode still shows the old `Word_OfficeApp.swift`/`ContentView.swift` in the sidebar as red (missing) files — right-click → **Delete** → **Remove Reference**.

## Verification checklist

After Step 1–5:

- [ ] Project builds clean (`⌘B`) on iPhone, iPad, Mac Catalyst destinations
- [ ] Zero Swift 6 concurrency warnings
- [ ] Mock scheme runs → shows document list (empty), create button opens sheet
- [ ] Creating a `.txt` file writes to `Documents/` directory (verify via Xcode's Devices window or macOS `~/Library/Containers/…/Documents/`)
- [ ] Opening a `.txt` shows the placeholder editor with basic text editing
- [ ] Settings tab (iPhone) or sidebar (iPad) shows Theme picker + version info

## Next after this

- Sprint 0.1 remaining work: unit tests for `DocumentListViewModel`, `EditorViewModel`, `AutosaveScheduler`
- Sprint 0.2 gate: when Artifex license lands, swap to `Debug-Real` scheme, plug real reader/writer/session manager into `Services/Implementations/SDK/Real/`

See `PHASE_1_ARCHITECTURE.md` §6 for the full sprint plan.
