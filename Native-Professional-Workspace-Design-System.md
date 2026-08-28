# Native Professional Workspace

## Product Design System & SwiftUI Style Guide

**Version:** 1.2  
**Status:** Single source of truth  
**Platforms:** iOS · iPadOS · macOS  
**Design source:** Figma Variables → Xcode Asset Catalog → SwiftUI semantic tokens  
**Product:** Office / Document / PDF productivity workspace

---

## 1. Purpose

This document defines the shared product, visual, interaction, and implementation language for the Native Professional Workspace. It is the authoritative reference for product designers, engineers, QA, and Codex/SwiftUI agents.

When a screen, component, or implementation conflicts with this guide, use this order of precedence:

1. Platform behavior and accessibility.
2. Semantic design-system rules in this document.
3. Feature-specific requirements.
4. One-off visual preference.

Do not invent a new color, spacing value, radius, type style, or interaction pattern when an appropriate token or native pattern already exists.

---

## 2. Product Direction

### 2.1 Direction name

**Native Professional Workspace**

The product should feel like a professional document workspace built specifically for Apple devices. It combines:

- Apple Files simplicity;
- Pages-level productivity;
- Notion-level clarity;
- practical PDF utility power;
- trust-first monetization.

The experience should be **calm, precise, native, trustworthy, and productive**.

It should not feel like:

- a mobile utility toolbox;
- a desktop Office clone squeezed onto a phone;
- an AI-first writing app;
- a decorative consumer app;
- a dashboard designed to advertise how many features exist.

The primary objective is:

> Help people complete document work quickly, confidently, and with minimal cognitive overhead.

### 2.2 Product pillars

1. **Productivity** — Office editing and iPad-native workflows.
2. **Document utility** — PDF, OCR, conversion, signing, and export.
3. **Trust** — privacy, autosave, recovery, and transparent subscriptions.

AI is an accelerator inside these workflows, not the visual or navigational center of the product.

### 2.3 Audience

- **Primary:** working professionals aged 35–44.
- **Secondary:** adults aged 55+.
- **Core job:** complete document work on an Apple device without returning to a laptop or switching between multiple apps.

The system must support high information density without sacrificing legibility, predictable navigation, or clear recovery paths.

---

## 3. Design Principles

### 3.1 Document First

The document is the primary object. Prioritize:

`Recent files → Open → Edit → Save → Export/Share`

over:

`Feature list → Choose tool → Find file → Perform action`

Features support documents; they do not dominate navigation.

### 3.2 Apple Native, Not Apple Decorative

Use Apple interaction conventions before custom UI:

- navigation stacks and split views;
- sidebars, toolbars, menus, sheets, and popovers;
- contextual actions and context menus;
- keyboard shortcuts, pointer states, drag and drop;
- SF Symbols and system typography;
- platform semantic colors when they express the correct meaning.

System material may communicate hierarchy, but it is not the brand. Avoid glass effects on every card or surface.

### 3.3 Progressive Complexity

Keep the default interface simple. Reveal advanced controls when the current task requires them.

Example:

`Bold · Italic · Underline · Alignment`

expands contextually into:

`Font · Spacing · Paragraph · Lists · Indentation · Advanced Format`

### 3.4 Trust Is Visible

Always make the following states understandable:

- whether a file is saved;
- where it is stored;
- whether it is synced;
- whether processing happens locally or remotely;
- what a subscription costs;
- when a trial ends and how to cancel.

Trust is a visible product behavior, not only policy text.

### 3.5 iPad Is a Workspace

iPad is not a stretched iPhone. Use multi-column layouts, resizable panes, inspectors, pointer and keyboard behavior, Apple Pencil, drag and drop, and Stage Manager-friendly sizing.

### 3.6 AI in Context

AI should appear at the moment of a relevant task:

- select text → Rewrite;
- open a long document → Summarize;
- open a contract → Ask About This Document.

Do not create a separate visual universe for AI and never replace user content without confirmation.

---

## 4. Brand Personality & Expression

| Attribute | Target |
|---|---:|
| Professional | 80% |
| Calm | 80% |
| Minimal | 65% |
| Premium | 60% |
| Technical | 55% |
| Friendly | 45% |
| Expressive | 30% |
| Playful | 15% |

The intended impression is **“reliable professional tool,”** not **“exciting productivity toy.”**

Use stronger brand expression in the app icon, onboarding, paywall, App Store assets, marketing, and AI introduction. Reduce brand expression in file management, editing, formatting, spreadsheet, presentation, and PDF-reading surfaces.

> The deeper the user enters their work, the quieter the brand becomes.

Avoid these directions:

- liquid glass everywhere;
- AI-purple gradients;
- super-rounded consumer UI;
- illustration-heavy functional screens;
- dashboards with 10–15 equal quick actions;
- desktop Office chrome copied literally onto iPad.

---

## 5. Information & UI Architecture

### 5.1 Four design-system layers

1. **Apple system:** typography, navigation, toolbar, sidebar, menus, sheets, popovers, context menus, and search.
2. **Document system:** file row, thumbnail, grid, document type, file state, sync state, recents, folders.
3. **Editor system:** formatting toolbar, selection menu, inspector, page navigator, sheet tabs, slide navigator.
4. **Utility system:** scan, OCR, convert, merge, compress, signature, and AI.

### 5.2 iPhone

Use a focused, single-pane navigation model:

`Files → Folder/List → Document → Editor`

Guidance:

- keep the tab bar to 2–4 items;
- preferred v1 tabs: `Files`, `Tools`, and optionally `Templates`;
- use bottom sheets for create, export, PDF tools, and compact inspectors;
- use a 16 pt default horizontal inset and 20 pt for spacious content;
- preserve at least 44 × 44 pt interactive targets;
- avoid showing every editor control simultaneously.

### 5.3 iPad

Use an adaptive workspace:

```text
Navigation Sidebar | File List | Document Workspace | Optional Inspector
```

Reference dimensions:

| Region | Width |
|---|---:|
| Navigation sidebar | 240–280 pt |
| File list | 280–360 pt |
| Document workspace | Flexible |
| Panel content inset | 20–24 pt |

Guidance:

- collapse panes based on available width, not device name alone;
- prefer popovers to full-screen sheets for formatting and quick actions;
- provide pointer hover, selection, and pressed states;
- support keyboard shortcuts and discoverability menus;
- keep the document stable when sidebars or inspectors appear;
- design for Split View and Stage Manager from the start.

### 5.4 Editor attention

During active editing, approximately 75% of visual attention should belong to user content. Toolbars and chrome may collapse when safe. Advanced formatting belongs in an inspector, popover, menu, or expandable toolbar.

---

## 6. Color Strategy

The color system is:

1. neutral-first;
2. based on one recognizable brand accent;
3. semantic rather than decorative;
4. independently designed for Light and Dark Mode, never simply inverted.

The brand family is **Professional Cobalt**. It communicates productivity, reliability, security, professionalism, and compatibility with the Apple ecosystem.

Avoid neon blue, saturated cyan, AI-purple gradients, and heavy navy backgrounds throughout the app.

### 6.1 Primitive cobalt palette

Primitive values support palette construction. Components must consume semantic roles instead of these values directly.

| Token | HEX |
|---|---|
| `Primitive/Color/Blue/50` | `#F2F6FF` |
| `Primitive/Color/Blue/100` | `#E3EBFF` |
| `Primitive/Color/Blue/200` | `#C7D7FF` |
| `Primitive/Color/Blue/300` | `#9EB9FF` |
| `Primitive/Color/Blue/400` | `#7197F5` |
| `Primitive/Color/Blue/500` | `#3267E3` |
| `Primitive/Color/Blue/600` | `#2858C9` |
| `Primitive/Color/Blue/700` | `#2349A7` |
| `Primitive/Color/Blue/800` | `#213E86` |
| `Primitive/Color/Blue/900` | `#20376E` |
| `Primitive/Color/Blue/950` | `#152246` |

### 6.2 Brand semantic tokens

| Token | Light | Dark |
|---|---|---|
| `BrandPrimary` | `#3267E3` | `#5B8CFF` |
| `BrandPrimaryPressed` | `#2858C9` | `#719DFF` |
| `BrandPrimarySubtle` | `#F2F6FF` | `#172544` |
| `BrandPrimarySubtlePressed` | `#E3EBFF` | `#20335B` |
| `BrandBorder` | `#C7D7FF` | `#35528C` |
| `BrandText` | `#2858C9` | `#84A7FF` |

### 6.3 Background tokens

| Token | Light | Dark | Usage |
|---|---|---|---|
| `BackgroundPrimary` | `#FFFFFF` | `#111317` | Main screens and workspace |
| `BackgroundSecondary` | `#F7F8FA` | `#181B20` | Sidebar and grouped sections |
| `BackgroundTertiary` | `#F0F2F5` | `#202329` | Nested backgrounds |
| `BackgroundElevated` | `#FFFFFF` | `#262A31` | Popovers and floating surfaces |

Dark Mode uses progressive surface elevation instead of inverted Light Mode values.

### 6.4 Surface tokens

| Token | Light | Dark |
|---|---|---|
| `SurfacePrimary` | `#FFFFFF` | `#1A1D22` |
| `SurfaceSecondary` | `#F7F8FA` | `#21242A` |
| `SurfaceTertiary` | `#EEF0F3` | `#292D34` |
| `SurfaceSelected` | `#EEF3FF` | `#1D2C4D` |
| `SurfaceHover` | `#F2F4F7` | `#272B32` |
| `SurfacePressed` | `#E9ECF1` | `#30343C` |
| `SurfaceDisabled` | `#F3F4F6` | `#202329` |

### 6.5 Text tokens

| Token | Light | Dark |
|---|---|---|
| `TextPrimary` | `#17191D` | `#F5F6F7` |
| `TextSecondary` | `#5D636D` | `#B8BDC5` |
| `TextTertiary` | `#777E89` | `#8B919B` |
| `TextDisabled` | `#A7ACB4` | `#636973` |
| `TextOnBrand` | `#FFFFFF` | `#081226` |
| `TextLink` | `#2858C9` | `#84A7FF` |

Important primary-button rule:

| Mode | Background | Foreground |
|---|---|---|
| Light | `#3267E3` | `#FFFFFF` |
| Dark | `#5B8CFF` | `#081226` |

Do not automatically keep white text on the brighter Dark Mode cobalt.

### 6.6 Borders and dividers

| Token | Light | Dark |
|---|---|---|
| `BorderSubtle` | `#ECEEF1` | `#292D33` |
| `BorderDefault` | `#DADDE2` | `#373B43` |
| `BorderStrong` | `#BEC3CA` | `#50555F` |
| `BorderFocused` | `#3267E3` | `#719DFF` |

Use a 1 px default divider. Define hierarchy in this order:

`Spacing → Surface → Divider → Border`

Do not outline every component.

### 6.7 Status tokens

| Role | Light main | Light background | Light border | Dark main | Dark background | Dark border |
|---|---|---|---|---|---|---|
| Success | `#218739` | `#EDF8EF` | `#BDE4C4` | `#4BD166` | `#14351C` | `#28643A` |
| Warning | `#A75D00` | `#FFF6E8` | `#F2D09B` | `#FFB44A` | `#3C290C` | `#75501C` |
| Error | `#D9342B` | `#FFF0EF` | `#F0BAB6` | `#FF6961` | `#421917` | `#7C312D` |

Use brand tokens for information states rather than creating a second blue palette. Pair every status color with an icon, label, or both.

### 6.8 Document-type colors

| File type | Light | Dark |
|---|---|---|
| Word | `#2F64D6` | `#6392FF` |
| Spreadsheet | `#18864B` | `#4BC67A` |
| Presentation | `#D86724` | `#FF995F` |
| PDF | `#D63C35` | `#FF706A` |
| Image | `#7654C6` | `#A88BFF` |
| Generic | `#68707C` | `#9CA2AC` |

Use document-type color only on file icons, small badges, or thumbnail identifiers. Never use it as a full-screen background.

### 6.9 Document workspace

| Token | Light | Dark |
|---|---|---|
| `DocumentCanvas` | `#F1F2F4` | `#0D0F12` |
| `DocumentPage` | `#FFFFFF` | `#F8F8F7` |
| `DocumentPageBorder` | `#E0E2E5` | `#35383E` |

A Word or PDF page may remain light when the surrounding interface is dark because it represents actual document output. Do not invert document content merely because the app uses Dark Mode.

### 6.10 Overlay, selection, and disabled states

| Token | Light | Dark |
|---|---|---|
| `OverlayScrim` | `rgba(0,0,0,0.32)` | `rgba(0,0,0,0.50)` |
| `OverlayStrong` | `rgba(0,0,0,0.48)` | `rgba(0,0,0,0.68)` |
| `SelectionBackground` | `#EEF3FF` | `#1D2C4D` |
| `SelectionBorder` | `#3267E3` | `#719DFF` |
| `SelectionText` | `#203E87` | `#DCE7FF` |
| `ButtonDisabledBackground` | `#E8EAED` | `#292C31` |
| `ButtonDisabledText` | `#9CA1A9` | `#666B73` |

Do not implement a disabled state by applying opacity to the entire component. Use explicit semantic tokens for predictable contrast.

---

## 7. Typography

Use **SF Pro through SwiftUI system text styles**. Do not introduce a custom UI font in v1.

| Token | iPhone reference | Weight | Typical use |
|---|---|---|---|
| `LargeTitle` | 34/41 | Bold | Top-level screen title |
| `Title1` | 28/34 | Bold | Rare, prominent title |
| `Title2` | 22/28 | Bold | Section or modal heading |
| `Title3` | 20/25 | Semibold | Subsection heading |
| `Headline` | 17/22 | Semibold | File name, primary card content |
| `Body` | 17/22 | Regular | Primary reading and controls |
| `Callout` | 16/21 | Regular | Supporting content |
| `Subheadline` | 15/20 | Regular | Metadata |
| `Footnote` | 13/18 | Regular | Supporting detail |
| `Caption` | 12/16 | Regular | Compact labels |

Rules:

- use Dynamic Type-compatible styles rather than fixed sizes where possible;
- support Regular, Medium, Semibold, and Bold; avoid pervasive extra-bold weight;
- use at most three visual text levels on one surface;
- left-align functional workspace content;
- reserve centered text for onboarding, empty states, confirmations, and simple paywall heroes;
- allow multiline content and test at accessibility sizes.

---

## 8. Spacing, Radius, Size & Elevation

### 8.1 Spacing

Base unit: **4 pt**.

| Token | Value |
|---|---:|
| `xxs` / `space/1` | 4 |
| `xs` / `space/2` | 8 |
| `sm` / `space/3` | 12 |
| `md` / `space/4` | 16 |
| `lg` / `space/5` | 20 |
| `xl` / `space/6` | 24 |
| `xxl` / `space/8` | 32 |
| `xxxl` / `space/10` | 40 |
| `huge` / `space/12` | 48 |
| `massive` / `space/16` | 64 |

Do not introduce arbitrary values such as 14, 17, or 18 pt without a documented layout reason.

### 8.2 Radius

| Token | Value | Use |
|---|---:|---|
| `small` | 8 | Small controls and thumbnails |
| `control` | 10 | Buttons and fields |
| `card` | 12 | Cards |
| `large` | 16 | Large cards and floating panels |

Use continuous rounded rectangles in SwiftUI. Avoid making 20–32 pt radii the default.

### 8.3 Size

| Token | Value |
|---|---:|
| `minimumTouchTarget` | 44 |
| `buttonHeight` | 50 |
| `fileIcon` | 44 |
| `navigationIcon` | 22 |
| `toolbarIcon` | 20 |

### 8.4 Elevation

- **Level 0:** flat content.
- **Level 1:** slight surface distinction for cards, toolbars, and floating controls.
- **Level 2:** system shadow for popovers, menus, and floating modal surfaces.

Avoid large, blurred marketing-style shadows.

---

## 9. Iconography

Use **SF Symbols by symbol name**. Never transfer SF Symbols by Unicode codepoint.

Create custom icons only when no suitable SF Symbol exists, the concept is product-specific, or file/product branding requires it.

| Context | Size |
|---|---:|
| Compact UI | 16–18 |
| Toolbar | 18–20 |
| Navigation | 20–24 |
| Feature action | 24 |
| Empty state | 40–56 |

Use familiar metaphors: share, import, scan, signature, lock, magnifying glass, plus, ellipsis, sparkles, trash, and star. Every icon-only action must have an accessibility label and a 44 × 44 pt hit area.

---

## 10. Core Components

### 10.1 Buttons

**Primary button**

```text
Height: 50
Radius: 10
Horizontal padding: 20
Font: Headline / 17 Semibold
Background: BrandPrimary
Foreground: TextOnBrand
```

Use one primary action per surface. A normal mobile surface may contain one primary, one secondary, and optional tertiary actions.

Secondary buttons use a neutral surface and primary/accent text. Tertiary buttons use text or icon-only treatment. Destructive actions use system destructive styling and must not resemble the primary action.

### 10.2 Inputs and search

- minimum field height: 44 pt; preferred: 48 pt;
- radius: 10 pt;
- horizontal inset: 12–16 pt;
- labels remain outside fields for professional forms;
- placeholders are examples, not labels;
- use platform-native search behavior.

Search initially supports filename, type, location, and recency. Document and OCR content may be added later without changing the search component’s visual contract.

### 10.3 File row

```text
[Thumbnail/Icon]  Proposal.docx
                  iCloud · Edited 12 min ago        ⋯
```

Reference:

- row height: 64–72 pt;
- file icon: 40–44 pt;
- name: Headline;
- metadata: Subheadline;
- overflow target: 44 × 44 pt.

Supported states: selected, syncing, offline, failed, locked, and shared.

### 10.4 File grid and thumbnail

The thumbnail dominates the grid card. Recognition priority is:

1. actual document preview;
2. file type;
3. title;
4. sync or status.

Avoid decorative cards around file names and do not over-brand thumbnails.

### 10.5 Sidebar and navigation

Recommended iPad groups:

```text
Documents
  Recent
  Favorites

Locations
  iCloud Drive
  On My iPad
  Google Drive
  Dropbox

Tools
Trash
```

Keep navigation bars quiet: back, title, contextual actions, and more. Avoid large colored navigation bars.

### 10.6 Editor toolbar and inspector

A compact Word toolbar may expose:

`Undo · Redo · Bold · Italic · Underline · Text · Paragraph · Insert · AI`

Advanced properties open in an inspector, popover, menu, or expandable toolbar. Do not expose every property at once.

### 10.7 Context menus, sheets, popovers, and dialogs

- use context menus for document and selection actions;
- use bottom sheets primarily on iPhone;
- use popovers on iPad for formatting, colors, and quick options;
- do not convert every iPhone sheet into a full-screen iPad sheet;
- interrupt with dialogs only for irreversible actions, critical failures, permission explanations, or data-loss risk.

### 10.8 Empty, loading, progress, save, toast, and error states

Empty states are short, functional, and action-oriented. Avoid illustration-heavy workspace screens.

Use specific progress copy such as `Scanning document…`, `Converting to PDF…`, or `Compressing…`. Long operations show progress and cancellation when technically safe. Background saving must not block editing.

Save states remain subtle but visible:

`Saving… · Saved · Saved to iCloud · Offline — saved on this iPad · Sync failed`

Use toasts for lightweight confirmations such as copied, moved to Trash, or export completed. Errors follow:

1. what happened;
2. a useful reason when known;
3. the next action.

Prefer `Couldn’t save your document. Your iCloud storage is full. Manage Storage.` over `Something went wrong.`

---

## 11. Feature Patterns

### 11.1 AI

AI uses the same product design system. A sparkle symbol and subtle brand tint are sufficient identifiers. Avoid glowing borders, animated orbs, purple gradients, and permanent sparkle animation.

Primary actions:

`Summarize · Rewrite · Ask About Document · Translate`

Rewrite options:

`Professional · Concise · Friendly · Simplify`

Generated content must be labeled and must offer explicit actions such as `Replace`, `Insert Below`, `Copy`, and `Regenerate`. Never replace original content without confirmation.

### 11.2 PDF utilities

All utilities use one workflow:

`Select File → Configure → Preview → Process → Result`

Tool cards are compact: icon, label, and a short description. Do not make each utility look like a separate app.

### 11.3 OCR and scanning

The camera dominates the capture screen. Controls stay minimal:

`Auto · Flash · Multi-page · Shutter · Import`

After capture:

`Crop · Rotate · Retake · Recognize Text`

### 11.4 Signature

Offer `Draw`, `Type`, and `Import`. Clearly state whether saved signatures remain local or sync.

### 11.5 Subscription

Paywalls are calm and factual. Show the billed amount, billing period, trial length, renewal amount, restore action, and cancellation path. Never use fake countdowns, false urgency, misleading close controls, or preselected consent that obscures cost.

---

## 12. Motion

Motion is **fast, restrained, and meaningful**.

Reference duration: **150–250 ms** for common interface transitions.

Use motion for toolbar transitions, sidebar expansion, page thumbnails, drag reordering, save confirmation, and OCR progress.

Avoid bouncing calls to action, elaborate loading sequences, decorative parallax, and continuous AI sparkle animation.

Rules:

- respect Reduce Motion;
- preserve spatial continuity when opening a file or inspector;
- do not animate every state change;
- favor system transitions and springs when they match the native pattern;
- never delay task completion to showcase an animation.

---

## 13. Accessibility

Minimum targets:

- normal text contrast: **4.5:1**;
- large or bold text contrast: **3:1**;
- interactive and meaningful non-text UI: **3:1** where applicable;
- touch targets: **44 × 44 pt** minimum.

Requirements:

- support Dynamic Type, including accessibility sizes;
- do not communicate file type, selection, sync, error, or success using color alone;
- provide accessibility labels for icon-only controls;
- preserve logical VoiceOver reading and focus order;
- make custom controls expose role, value, state, and action;
- support Differentiate Without Color, Increase Contrast, Reduce Motion, and Reduce Transparency where relevant;
- never disable text scaling to protect a fragile layout;
- test Light, Dark, and increased-contrast appearances;
- keep critical actions reachable by keyboard on iPadOS and macOS.

High-contrast support must change semantic token values, not require separate component implementations.

---

## 14. Content Style

Voice is calm, direct, factual, and respectful. Use sentence case.

### 14.1 Action labels

Use clear verbs: `Create Document`, `Import File`, `Save`, `Export`, `Try Again`, `Manage Storage`.

Avoid vague labels such as `OK`, `Go`, or `Proceed` when the action can be named.

### 14.2 Status and error copy

State the real condition and recovery path. Avoid blame, unexplained technical codes, and unsupported promises.

### 14.3 Privacy copy

Show privacy information at the moment it matters:

- `Processed on this device.`
- `Stored on this iPad.`
- `Selected content will be sent securely for processing.`

Do not claim on-device or encrypted processing unless it is technically true.

### 14.4 Localization

- design for labels to expand by at least 30%;
- avoid concatenating translated strings;
- use locale-aware dates, times, numbers, and prices;
- keep file metadata scannable and meaningful;
- do not encode meaning through English abbreviations alone.

---

## 15. Figma Variable Architecture

Use exactly three conceptual levels:

```text
Primitive/
  Color/
    Blue/
    Neutral/
    Green/
    Orange/
    Red/
    Purple/

Semantic/
  Background/
  Surface/
  Text/
  Border/
  Brand/
  Status/
  Document/
  Overlay/
  Selection/

Component/
  Button/
  Input/
  Sidebar/
  File/
  Editor/
  Feedback/
```

Correct alias chain:

```text
Primitive/Color/Blue/500
  ↓
Semantic/Brand/Primary
  ↓
Component/Button/Primary/Background
```

Do not bind a component directly to `Blue/500`.

### 15.1 Collections and modes

Recommended collections:

| Collection | Modes |
|---|---|
| `Primitive Color` | Single source values |
| `Semantic Color` | Light, Dark |
| `Component Color` | Light, Dark through aliases |
| `Number` | Spacing, radius, size |
| `Typography` | Platform text styles or documented references |

Future semantic modes may include `Light High Contrast` and `Dark High Contrast`. Component structure must remain unchanged when appearance changes.

### 15.2 Naming contract

Figma components and SwiftUI types should share concepts:

| Figma | SwiftUI |
|---|---|
| `Button/Primary` | `DSPrimaryButton` |
| `File/Row` | `DSFileRow` |
| `File/GridItem` | `DSFileGridItem` |
| `Navigation/SidebarItem` | `DSSidebarItem` |
| `Editor/ToolbarButton` | `DSEditorToolbarButton` |
| `Status/Save` | `DSSaveStatus` |

Use SF Symbol names as metadata or documented properties. Never store or hand off a glyph codepoint.

---

## 16. Xcode Asset Catalog Mapping

Create semantic Color Sets. Each set uses:

```text
Any Appearance = Light value
Dark Appearance = Dark value
```

Required color assets:

```text
BrandPrimary
BrandPrimaryPressed
BrandPrimarySubtle
BrandPrimarySubtlePressed
BrandBorder
BrandText

BackgroundPrimary
BackgroundSecondary
BackgroundTertiary
BackgroundElevated

SurfacePrimary
SurfaceSecondary
SurfaceTertiary
SurfaceSelected
SurfaceHover
SurfacePressed
SurfaceDisabled

TextPrimary
TextSecondary
TextTertiary
TextDisabled
TextOnBrand
TextLink

BorderSubtle
BorderDefault
BorderStrong
BorderFocused

StatusSuccess
StatusSuccessBackground
StatusSuccessBorder
StatusWarning
StatusWarningBackground
StatusWarningBorder
StatusError
StatusErrorBackground
StatusErrorBorder

DocumentWord
DocumentSpreadsheet
DocumentPresentation
DocumentPDF
DocumentImage
DocumentGeneric
DocumentCanvas
DocumentPage
DocumentPageBorder

OverlayScrim
OverlayStrong
SelectionBackground
SelectionBorder
SelectionText
ButtonDisabledBackground
ButtonDisabledText
```

Do not create UI assets named `Blue500`, `Gray100`, `DarkBlue`, or `LightBackground`. Primitive names belong in the design-system source, not view code.

---

## 17. SwiftUI Token Patterns

### 17.1 Color

Views must not contain design HEX or Light/Dark branching for visual colors. Asset Catalog resolves appearance automatically.

```swift
import SwiftUI

extension Color {
    // Brand
    static let dsBrandPrimary = Color("BrandPrimary")
    static let dsBrandPrimaryPressed = Color("BrandPrimaryPressed")
    static let dsBrandPrimarySubtle = Color("BrandPrimarySubtle")
    static let dsBrandPrimarySubtlePressed = Color("BrandPrimarySubtlePressed")
    static let dsBrandBorder = Color("BrandBorder")
    static let dsBrandText = Color("BrandText")

    // Background and surface
    static let dsBackgroundPrimary = Color("BackgroundPrimary")
    static let dsBackgroundSecondary = Color("BackgroundSecondary")
    static let dsBackgroundTertiary = Color("BackgroundTertiary")
    static let dsBackgroundElevated = Color("BackgroundElevated")
    static let dsSurfacePrimary = Color("SurfacePrimary")
    static let dsSurfaceSecondary = Color("SurfaceSecondary")
    static let dsSurfaceTertiary = Color("SurfaceTertiary")
    static let dsSurfaceSelected = Color("SurfaceSelected")
    static let dsSurfaceHover = Color("SurfaceHover")
    static let dsSurfacePressed = Color("SurfacePressed")
    static let dsSurfaceDisabled = Color("SurfaceDisabled")

    // Text and border
    static let dsTextPrimary = Color("TextPrimary")
    static let dsTextSecondary = Color("TextSecondary")
    static let dsTextTertiary = Color("TextTertiary")
    static let dsTextDisabled = Color("TextDisabled")
    static let dsTextOnBrand = Color("TextOnBrand")
    static let dsTextLink = Color("TextLink")
    static let dsBorderSubtle = Color("BorderSubtle")
    static let dsBorderDefault = Color("BorderDefault")
    static let dsBorderStrong = Color("BorderStrong")
    static let dsBorderFocused = Color("BorderFocused")

    // Status
    static let dsSuccess = Color("StatusSuccess")
    static let dsSuccessBackground = Color("StatusSuccessBackground")
    static let dsSuccessBorder = Color("StatusSuccessBorder")
    static let dsWarning = Color("StatusWarning")
    static let dsWarningBackground = Color("StatusWarningBackground")
    static let dsWarningBorder = Color("StatusWarningBorder")
    static let dsError = Color("StatusError")
    static let dsErrorBackground = Color("StatusErrorBackground")
    static let dsErrorBorder = Color("StatusErrorBorder")

    // Document
    static let dsDocumentWord = Color("DocumentWord")
    static let dsDocumentSpreadsheet = Color("DocumentSpreadsheet")
    static let dsDocumentPresentation = Color("DocumentPresentation")
    static let dsDocumentPDF = Color("DocumentPDF")
    static let dsDocumentImage = Color("DocumentImage")
    static let dsDocumentGeneric = Color("DocumentGeneric")
    static let dsDocumentCanvas = Color("DocumentCanvas")
    static let dsDocumentPage = Color("DocumentPage")
    static let dsDocumentPageBorder = Color("DocumentPageBorder")

    // Overlay, selection, and disabled
    static let dsOverlayScrim = Color("OverlayScrim")
    static let dsOverlayStrong = Color("OverlayStrong")
    static let dsSelectionBackground = Color("SelectionBackground")
    static let dsSelectionBorder = Color("SelectionBorder")
    static let dsSelectionText = Color("SelectionText")
    static let dsButtonDisabledBackground = Color("ButtonDisabledBackground")
    static let dsButtonDisabledText = Color("ButtonDisabledText")
}
```

The `ds` prefix improves autocomplete, avoids framework naming conflicts, and makes global refactoring safer.

### 17.2 Typography

```swift
import SwiftUI

enum DSFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title1 = Font.title.weight(.bold)
    static let title2 = Font.title2.weight(.bold)
    static let title3 = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
}
```

### 17.3 Spacing, radius, and size

```swift
import Foundation

enum DSSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
    static let massive: CGFloat = 64
}

enum DSRadius {
    static let small: CGFloat = 8
    static let control: CGFloat = 10
    static let card: CGFloat = 12
    static let large: CGFloat = 16
}

enum DSSize {
    static let minimumTouchTarget: CGFloat = 44
    static let buttonHeight: CGFloat = 50
    static let fileIcon: CGFloat = 44
    static let navigationIcon: CGFloat = 22
    static let toolbarIcon: CGFloat = 20
}
```

### 17.4 Component example

```swift
import SwiftUI

struct DSPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isDisabled = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DSSize.buttonHeight)
        }
        .foregroundStyle(
            isDisabled ? .dsButtonDisabledText : .dsTextOnBrand
        )
        .background(
            isDisabled ? .dsButtonDisabledBackground : .dsBrandPrimary
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: DSRadius.control,
                style: .continuous
            )
        )
        .disabled(isDisabled)
    }
}
```

Prefer a custom `ButtonStyle` when interaction states must be reused across many buttons.

### 17.5 System colors vs. custom tokens

Use `Color.primary`, `Color.secondary`, `.tint`, and native platform styling when they express the intended semantic role. Use DS tokens for brand, product surfaces, file states, document canvas, and custom components. Do not recreate Apple’s entire semantic color system.

---

## 18. SwiftUI Implementation Rules

1. **No design HEX in views.** HEX values exist only in the design source and Asset Catalog.
2. **No appearance branching for colors.** Do not read `colorScheme` only to select a visual color.
3. **Use semantic names.** Prefer `.dsTextSecondary` over `.gray` and `DSSpacing.md` over `16`.
4. **Use native patterns.** Recognize `NavigationStack`, `NavigationSplitView`, `List`, `TabView`, `Toolbar`, `Menu`, `contextMenu`, `sheet`, and `popover` before rebuilding them from primitives.
5. **Use SF Symbols by name.** Example: `Image(systemName: "square.and.arrow.up")`.
6. **Preserve Dynamic Type.** Use text styles and flexible layouts; avoid fixed-height text containers.
7. **Keep tokens feature-agnostic.** A feature may compose tokens but must not redefine foundations.
8. **Model state explicitly.** Loading, empty, error, disabled, selected, offline, syncing, and destructive states are part of the component API.
9. **Use environment behavior intentionally.** Read appearance, size class, accessibility, or motion settings only when behavior or layout genuinely changes.
10. **Do not infer missing design values silently.** Reuse a documented token or flag a genuine gap for design-system review.

Recommended project structure:

```text
App/
├── DesignSystem/
│   ├── Foundations/
│   │   ├── DSColor.swift
│   │   ├── DSFont.swift
│   │   ├── DSSpacing.swift
│   │   ├── DSRadius.swift
│   │   └── DSSize.swift
│   ├── Components/
│   │   ├── Buttons/
│   │   ├── Inputs/
│   │   ├── Navigation/
│   │   ├── File/
│   │   ├── Editor/
│   │   └── Feedback/
│   └── Styles/
├── Features/
│   ├── Documents/
│   ├── Editor/
│   ├── PDFTools/
│   ├── Scanner/
│   ├── AI/
│   ├── Templates/
│   └── Settings/
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Storage/
│   └── Extensions/
└── Resources/
    └── Assets.xcassets
```

---

## 19. Design-to-Code Handoff Contract

Every component handed to engineering must include:

- semantic token bindings;
- supported size and appearance modes;
- content and localization behavior;
- default, hover, pressed, focused, selected, disabled, loading, and error states as applicable;
- accessibility label/value guidance for non-text controls;
- iPhone and iPad behavior;
- SF Symbol names;
- truncation, wrapping, and empty-content behavior.

Every Codex/SwiftUI implementation must:

- map design roles to existing DS tokens;
- keep native iOS semantics rather than translating literal Figma geometry;
- use screenshots as visual reference and Figma variables as token reference;
- preserve platform behavior, accessibility, localization, and adaptive layout;
- report token or component gaps instead of embedding one-off values.

---

## 20. Review Checklist

### Product and interaction

- Is the document still the primary object?
- Is the default UI simpler than the full feature set?
- Does iPad behave like a workspace rather than a scaled phone?
- Are save, sync, storage, privacy, and subscription states visible?
- Does AI appear in context and preserve user control?

### Visual system

- Are component colors semantic rather than primitive?
- Have Light and Dark Mode been reviewed independently?
- Does the document page preserve the output metaphor?
- Are spacing, radius, type, and size values tokenized?
- Are brand expression and decorative effects restrained inside the workspace?

### Accessibility and content

- Does contrast meet the stated targets?
- Does the interface work with Dynamic Type and VoiceOver?
- Is meaning communicated without color alone?
- Are targets at least 44 × 44 pt?
- Is copy specific, factual, localized, and recoverable?

### SwiftUI

- Are there no HEX values or appearance branches in views?
- Are native containers and controls used where appropriate?
- Are SF Symbols referenced by name?
- Are all relevant states modeled explicitly?
- Does the implementation remain stable across iPhone, iPad multitasking, Light, Dark, and accessibility settings?

---

## 21. Final Direction

The product must not try to look “feature-rich.” It must look and behave as though completing document work is straightforward.

> Quiet interface. Clear state. Native behavior. Powerful document workflow.
