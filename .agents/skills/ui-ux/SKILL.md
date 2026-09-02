# UI/UX Design Skill

Deep guidance for designing and building high-quality user interfaces. Load this skill when working on visual design, component architecture, user flows, or front-end implementation.

---

## Design System Audit

When reviewing an existing design or codebase, check for:

### Visual inconsistencies
- Mixed border radii (some 4px, some 8px, some 12px — pick one scale)
- Inconsistent spacing (random pixel values instead of a 4px grid)
- Multiple grays that are too close in value (consolidate to 3–5 neutral steps)
- Font sizes that don't follow a scale (17px, 15px, 13px — not a system)

### Component debt
- Duplicated components that do the same thing slightly differently
- Components with too many props (>8 is a smell — consider splitting)
- Missing states: hover, focus, active, disabled, loading, error, empty
- Hardcoded colors inside components instead of token references

---

## User Flow Mapping

Before building a feature, map the flow:

```
Entry point → Task steps → Success / Error → Next action
```

Ask:
- What does the user want to accomplish?
- What do they already know when they arrive?
- What can go wrong, and how is each error case handled?
- What happens after success — do they stay or go somewhere else?
- Is there a shortcut for power users?

---

## Screen Archetypes

### List screen
Purpose: Browse and find items
Required elements: search/filter, sort control, item count, empty state, loading skeleton, bulk action bar (if items are selectable)
Pitfalls: no filter on large lists, no count, "No results" with no way to reset filters

### Detail screen
Purpose: View and act on a single item
Required elements: breadcrumb/back nav, primary action (edit/delete), metadata section, related items
Pitfalls: too much information density, no clear primary action, no loading state for async sections

### Form screen
Purpose: Create or edit an item
Required elements: clear title ("New project" / "Edit profile"), field labels, validation, cancel + submit actions, unsaved changes warning
Pitfalls: submit-only validation, no cancel, no success feedback

### Dashboard / Overview
Purpose: Status at a glance, surface what needs attention
Required elements: key metrics (3–5 max), recent activity, alerts/anomalies, quick actions
Pitfalls: too many metrics (everything important = nothing important), no actionable next steps

### Settings screen
Purpose: Configure preferences and account
Required elements: logical grouping, save feedback (auto-save or explicit save), dangerous actions in their own section at the bottom
Pitfalls: no grouping, dangerous actions mixed with normal ones

---

## Interaction Design Patterns

### Progressive disclosure
Show only what's needed now. Reveal more on request.
- Summary → expand for detail
- Simple form → "Advanced options" accordion
- Onboarding → show advanced features after first use

### Inline editing
When to use: single-field edits in a dense list or detail view
Pattern: display value → click to activate input → confirm with Enter/blur → show saved indicator
Avoid for: multi-field forms, required validation, or when the change is hard to reverse

### Drag and drop
Always provide a non-drag alternative (up/down arrows, move-to menu)
Visual affordances: grab cursor, drag handle icon, drop zone highlight
Announce to screen readers: use `aria-grabbed` and `aria-dropeffect`

### Infinite scroll vs pagination
Use infinite scroll for: social feeds, photo galleries, exploratory browsing
Use pagination for: search results (users want to return to a position), data tables, any list where items need to be referenced by page number
Never: infinite scroll without a way to get back to a position

### Optimistic UI
Apply immediately, roll back on error
- Show the change instantly
- Make the API call in the background
- On error: revert + show error toast with retry option
- Works best for: likes, toggles, reorders, quick status changes
- Avoid for: financial transactions, irreversible deletes

---

## Color Theory for UI

### Building a palette from one accent color
1. Start with your brand/accent color (e.g. `#C4603A`)
2. Create a 10-step scale: mix toward white (tints) and black (shades)
3. Pick 3 values from the scale: light (backgrounds, highlights), mid (borders, hover), dark (text, filled buttons)
4. Derive neutrals: desaturate the accent slightly and build a gray scale from it — these grays will feel "on-brand" without being obvious

### Semantic color roles
```
Action:     accent (buttons, links, highlights)
Success:    green family (confirmation, complete states)
Warning:    amber/orange (caution, degraded states)
Error:      red family (failures, destructive actions)
Info:       blue family (neutral alerts, tooltips)
Neutral:    grays (borders, muted text, backgrounds)
```

### Contrast shortcuts
- Text on white: `#595959` or darker passes 4.5:1
- White text on color: the color needs to be at least `#767676` luminance equivalent or darker
- Use https://webaim.org/resources/contrastchecker/ to verify

---

## Typography Pairing Guide

### Display + Body combinations
```
Fraunces (serif display)   + DM Sans (clean body)      → editorial, premium
Playfair Display           + Source Serif 4             → classic, longform
Cabinet Grotesk            + Inter                      → modern startup
Clash Display              + Satoshi                    → bold, youthful
Syne                       + Epilogue                   → geometric, creative
```

### Rules
- Display font for: h1, h2, hero headlines, pull quotes
- Body font for: h3–h6, paragraphs, labels, UI text
- Mono font for: code, data, ID strings, keyboard shortcuts
- Never more than 2 font families in one UI (mono doesn't count)

---

## Iconography Guidelines

### Usage
- Use icons to reinforce meaning, not replace text in unfamiliar contexts
- Icon + label is almost always better than icon alone
- Consistent style across the entire product (all outline or all filled — not mixed)
- Size: 16px for inline UI, 20–24px for standalone, 32px+ for feature illustration

### Common mistakes
- Using a "settings" gear for everything ambiguous
- Using different icon libraries in the same product
- Icons that are too detailed to read at 16px
- Animated icons on static content (distracting)

---

## Copywriting for UI

### Microcopy principles
- Button labels are verbs: "Save changes" / "Delete account" / "Send message"
- Error messages say what happened AND what to do: "Email already in use — try signing in instead"
- Empty states offer a next step: don't end with "Nothing here yet"
- Confirmation dialogs state the consequence: "This will permanently delete all 47 files"

### Tone by context
```
Error/warning:    Direct, specific, no blame, offers a fix
Success:          Brief, warm, confirms the action taken
Onboarding:       Encouraging, low-friction, outcome-focused
Destructive action: Neutral, factual, specific about what will happen
```

### Things to avoid
- "Oops!" — sounds dismissive for real errors
- "Are you sure?" — vague, doesn't state what they're sure about
- "Invalid input" — doesn't tell the user what's wrong
- Passive voice: "The file was deleted" → "You deleted the file" / "File deleted"

---

## Handoff Checklist (for dev handoff)

- [ ] All components have defined states (default, hover, focus, active, disabled, loading, error)
- [ ] Color tokens documented, not just hex values
- [ ] Spacing values from the grid (not arbitrary)
- [ ] Font sizes, weights, line heights specified per text style
- [ ] Motion specs: duration, easing, trigger
- [ ] Responsive behavior documented at each breakpoint
- [ ] Edge cases covered: long text truncation, empty state, overflow
- [ ] Accessibility notes: focus order, ARIA roles, keyboard interactions
