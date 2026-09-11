# Onboarding pager — package for integration (2026-09-11, final)

Redesigned S1-S4 first-run onboarding pager for Word Office. Packaged out of
the main repo so it can travel to another machine and be integrated by hand
(the main repo has no git remote, so a physical copy is the only transfer
path — same as the machine-portability packaging done 2026-09-02).

This supersedes any earlier copy of this package — it reflects every
adjustment made during today's review pass (background style, S1/S2 hero
content, Skip visibility, S3 background pages).

## What changed vs. the version already in the repo (pre-redesign)

- **Background**: flat dark "aurora" gradient → light "soft brand wash"
  (off-white/light-blue base + 2 blurred, drifting/breathing brand-blue
  blobs).
- Removed the glass card wrapper (`OnboardingCardStack`, deleted) — hero art
  sits directly on the background.
- Progress dots moved from the footer to the top bar.
- CTA is brand-blue on every page (was near-black for S1-S3, blue only on
  S4).
- **Skip** now shows only on S1 (`viewModel.isFirstPage`) — previously
  shown on S1-S3, hidden only on the last page (S4).
- `RootView.swift`: removed the Session-19 auto-skip branch so this pager is
  the real first-run gate again, not dead code bypassed by
  `SampleFileSeeder`.

### S1 ("Edit Office files anywhere")
Kept the **original static PNG** hero (`OnboardingEditOffice` — Word/Excel/
PDF icons + signature). An earlier draft replaced this with an animated
SwiftUI composition (`OnboardingEditHero.swift`, still present in this
folder but **no longer referenced** by `OnboardingPageView` — safe to leave
unused or delete on the target repo, your call) — reverted per feedback, the
static PNG is what ships.

### S2 ("Every tool, one tap away")
Also kept the **original static PNG** hero (`OnboardingTools` — PDF+convert
arrows, signature, and a Compress/zip icon), but added two small badges
alongside it for tools the PNG doesn't depict:
- **Split** badge (top-right, above the zip icon)
- **Merge** badge (bottom-left, near the PDF icon)

Both icon/tint pulled from `ToolsTabView`'s real cards (`square.split.2x1`,
`doc.on.doc.fill`, PDF-document red tint) — not invented. The badges are
built inline in `OnboardingPageView.swift` (`toolBadge(icon:label:)`), not
in a separate hero file.

⚠️ **Known inaccuracy, not fixed (flagged, kept per user's call)**: the PNG
itself still shows a Compress/zip icon. Compress is **cut from MVP scope**
and has no card in `ToolsTabView` — this PNG detail is technically
misleading but was left as-is; revisit if it matters later.

`OnboardingToolsHero.swift` (the earlier animated Convert/Merge/Split/Sign
version) is still present in this folder but **no longer referenced**.

### S3 ("Stay on top of every document")
Unchanged content/animation (the Signing→Signed loop card + timeline), but
added **4 faint decorative document pages** peeking out from behind the
card (`backgroundPages` in `OnboardingTrackDocumentsHero.swift`) — one near
each corner, muted opacity, rotated, sized to stay proportional (not
overlapping the card's own rounded corners, which caused a visible seam
artifact in an earlier iteration — see the doc comment on `backgroundPages`
for why the offsets are what they are).

### S4 ("Choose a folder")
No changes — still the `OnboardingChooseFolder` PNG.

## Files in this folder → where they go in the target repo

```
Views/Onboarding/*.swift        → Word Office/Views/Onboarding/
Models/OnboardingPage.swift     → Word Office/Models/OnboardingPage.swift
ViewModels/OnboardingViewModel.swift → Word Office/ViewModels/OnboardingViewModel.swift
RootView.swift (Views/Root/)    → Word Office/Views/Root/RootView.swift
Assets.xcassets/*                → Word Office/Assets.xcassets/
```

`Views/Onboarding/` here is the COMPLETE replacement set for that directory
— it does NOT include `OnboardingCardStack.swift` because that file was
deleted (no longer used). Delete it on the target machine too if it's still
present there.

`OnboardingEditHero.swift` and `OnboardingToolsHero.swift` are included
because they're part of the live source tree, but neither is referenced
anymore (S1/S2 both use static PNGs now) — safe to keep as unused code or
delete, your call.

`OnboardingTrackDocuments.imageset` in the target repo's `Assets.xcassets`
is unused (S3 is a SwiftUI composition, not a PNG) — not included in this
package; safe to leave in place or delete on the target machine.

## Known follow-ups, not done

- S2's PNG still visually implies a Compress feature that doesn't exist in
  the app (see the ⚠️ note above) — not fixed, flagged for a future pass.
- No on-device visual QA pass on a physical device (this machine has no
  Accessibility permission for tap automation — same limitation noted
  across prior sessions in `CHANGELOG.md`). All verification here was done
  via `xcodebuild` + `simctl` fresh-installs and screenshots, jumping pages
  by temporarily hardcoding `OnboardingViewModel.currentIndex` for the
  screenshot then reverting — not real swipe interaction.
