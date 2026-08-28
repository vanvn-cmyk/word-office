# Word Office

Native iOS/iPadOS/Mac Catalyst office document editor — DOCX/XLSX/PPTX/PDF viewer and editor with on-device processing. Design-first, privacy-first, no cloud upload.

## Architecture

**MVVM + SOLID** with layer-based structure:

- `App/` — entry point, DI container, app-level `@Observable` stores
- `Models/` — pure value types (Codable + Sendable)
- `Services/` — protocols + implementations (native + SDK-backed)
- `ViewModels/` — `@Observable @MainActor` coordinators
- `Views/` — SwiftUI presentation only
- `DesignSystem/` — semantic tokens (color, spacing, typography, sizes)

See `Word Office/PHASE_1_ARCHITECTURE.md` for the full architecture spec.

## Sprint 0.2 status

**Non-SDK track effectively DONE** — Library core loop (§10 v2) implemented end-to-end:
- 5 view atoms (`DocumentCard`, `DocumentStatusPicker`, `RemindAtField`, `FolderPermissionOnboarding`, `ReauthorizePermissionCTA`)
- `LibraryView` + `RootView` compose
- Unit tests (34+2 cases, Swift Testing)
- Import + crash-recovery + `scenePhase` autosave services
- UC16 first-scan familiarity — `DateBucket` grouping + adaptive hero copy (backend ready)

Blocked on external:
- Artifex license for real SDK swap + round-trip fidelity gate
- Bundle ID + Team ID for App Group entitlement (FileProvider sharing)

## Requirements

- Xcode 16+ (Xcode 26 recommended)
- iOS 17.0+ deployment target
- Swift 6 strict concurrency enabled

## Setup

1. Open `Word Office.xcodeproj`
2. Add GRDB SPM: `https://github.com/groue/GRDB.swift` (v7+, select only the `GRDB` static product — not `GRDB-dynamic`)
3. Select scheme `Word Office (Mock)`
4. `⌘R` to build and run

## Documentation

| Doc | Purpose |
|---|---|
| `Word Office/PHASE_1_ARCHITECTURE.md` | Full architecture v2.2 |
| `Word Office/product-strategy-master.md` | Product positioning + roadmap |
| `Word Office/Native-Professional-Workspace-Design-System.md` | Design tokens (Professional Cobalt palette) |
| `Word Office/Library-Architecture.md` | Library core loop (§10) — flow + traps |
| `Word Office/Phase0-Implementation-Logic-v2.md` | Per-feature implementation logic |
| `Word Office/GUIDELINE.md` | Step-by-step checklist |
| `Word Office/library-preview.html` | 7 UI case mockup (iOS 18 style) |
| `Word Office/TuHoSo-Flow-Review.html` | Flow review + 15 use cases + Mermaid diagrams |
| `CHANGELOG.md` | Session history |

## License

TBD.
