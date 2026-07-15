# Visual Language and Component System

## Creative direction

The interface should feel like a state archive and ruler's cabinet from 1444–1700: dark wood/leather, restrained antique metal, parchment for documents, painted heraldry, and precise strategic notation. It must remain a readable simulation interface first.

The target is not “make every edge ornate.” Use ornament to establish hierarchy:

- Highest ornament: persistent country identity, major window header, event title, victory/defeat moments.
- Moderate ornament: major navigation buttons, tabs, important section dividers.
- Minimal ornament: tables, dense statistics, tooltips, lists, settings, debug interfaces.

## Design tokens to approve

These are provisional production values. Create a style-board screenshot and approve or revise them before mass-producing assets.

### Colour roles

| Token | Starting value | Use |
|---|---:|---|
| `surface_base` | `#10171C` | Main dark panel |
| `surface_raised` | `#18242B` | Raised controls and headers |
| `surface_recessed` | `#0B1115` | Tables, slots, input wells |
| `metal_mid` | `#9B7B43` | Main antique-brass trim |
| `metal_light` | `#C6A96B` | Fine highlights, selected edge |
| `metal_dark` | `#4F3B22` | Bevel shadow |
| `parchment` | `#D8C9A3` | Document and event content |
| `text_primary` | `#E8E4D8` | Main body text on dark |
| `text_secondary` | `#9FB1BF` | Labels and supporting data |
| `positive` | `#6FD08C` | Positive change, reinforced by `+`/icon |
| `negative` | `#F28C7A` | Negative change, reinforced by `−`/icon |
| `warning` | `#E0B85C` | Attention needed |
| `critical` | `#D85A55` | Immediate danger or destructive action |
| `focus` | `#79BCE8` | Keyboard focus ring |

Never use colour alone to distinguish positive/negative, attacker/defender, religion, ownership, or alert severity. Pair it with sign, icon, label, shape, pattern, or position.

### Typography roles

Use two families, with an optional tabular-number face/variant:

- **Display serif:** window titles, country names, event titles, major headings.
- **Readable body face:** labels, buttons, tooltips, paragraphs, settings.
- **Tabular figures:** ledgers, resource values, dates, percentages, army statistics.

Starting 100% scale sizes:

| Role | Size | Notes |
|---|---:|---|
| Major title | 22–26 px | Rare; event/country identity |
| Window title | 18–20 px | Clear, not all caps by default |
| Section header | 15–16 px | May use small caps/letter spacing |
| Body | 14 px | Normal interface reading |
| Dense/table | 12–13 px | Never the default for long prose |
| Caption | 11–12 px | Only secondary, nonessential data |

Choose fonts licensed for redistribution, preferably SIL Open Font License. Keep the licence file with the font. Verify Latin extended characters, accented names, punctuation, currency symbols, and tabular numerals.

### Spacing and sizing

Use a 4-pixel base grid at 100% UI scale:

- 4 px: icon-to-label micro gap.
- 8 px: normal control internal gap.
- 12 px: compact group padding.
- 16 px: standard panel inner margin.
- 24 px: major section separation.
- 32 px: large structural separation.

Minimum targets:

- Primary pointer target: 40×40 px; prefer 44×44 px for frequently used controls.
- Dense table row: 28–32 px, with a larger accessibility option.
- Close button: 36×36 px with a forgiving hit box.
- Icon source: commonly 32×32 or 64×64 master, scaled consistently.
- Border/corner art: never become the click target by accident.

## Core component library

Each component needs an editable master, runtime export, Godot theme/scene implementation, and a state sheet.

### Surfaces and frames

1. **Major window frame** — ornamental corners, title header, resize-safe centre.
2. **Utility window frame** — restrained frame for ledger, settings, lists, debug.
3. **Recessed sub-panel** — grouped values, lists, graphs, descriptions.
4. **Parchment document panel** — events, treaties, history text; maintain contrast.
5. **Tooltip frame** — compact, strong edge, no decorative dead space.
6. **Popup/modal frame** — stronger silhouette and backdrop separation.

All stretchable frames must define nine-slice margins. Test at minimum, typical, and extreme dimensions; corners must not stretch and centre texture must not visibly smear.

### Controls

- Primary, secondary, icon-only, danger, and text-link buttons.
- Active/inactive/disabled tabs.
- Checkbox, radio button, toggle, option selector, slider, and spin/value control.
- Text field, search field, dropdown, list row, and sortable table header.
- Scroll bar and scroll arrows.
- Progress bar with determinate, indeterminate, paused, complete, and blocked states.
- Close, pin, collapse, expand, help, back, and confirmation controls.
- Drag handle if windows are movable; it must be visually explicit.

Every interactive control should specify normal, hover, pressed, selected, focused, disabled, warning, and error states as applicable.

### Information components

- Resource cell: icon, value, monthly change, warning badge, tooltip.
- Stat row: label, value, optional modifier, help target.
- Breakdown row: source, signed amount, percentage, subtotal.
- Country identity: flag/emblem, country colour, full country name.
- Character identity: portrait, frame, name, age, dynasty, status.
- Status chip: icon, short text, severity, optional countdown.
- Notification card: category, title, time, body, action, dismiss/pin.
- Empty state: explanation and next valid action.
- Validation/error banner: human explanation and recovery action.
- Loading state: use only when work is genuinely asynchronous.

## Icon system

Create one visual grammar instead of mixing clip-art styles:

- Consistent perspective (flat front-facing is safest).
- Consistent outline weight and inner detail density.
- Shared antique-gold/ivory base with limited domain colours.
- Strong silhouette readable at 16 px.
- No baked circular button background unless the component requires it.
- A monochrome/mask version where dynamic tinting is appropriate.

Each icon master must record:

- Semantic name and intended meaning.
- Domain: economy, military, diplomacy, government, religion, character, map mode, shell.
- Source/licence/provenance.
- Master dimensions and runtime dimensions.
- Light/dark background test.
- Colour-vision and small-size review.

Do not reuse the same icon for unrelated actions merely because it looks convenient. Do reuse an icon when the underlying action is genuinely the same.

## Heraldry, flags, portraits, and event art

- Keep the decorative shield frame, alpha mask, and country emblem as separate assets.
- Use full country names in interface text; internal three-letter tags may appear only in developer/debug views.
- Temporary historic flags/shields must be clearly registered as placeholders with source and replacement status.
- If a country lacks approved real/project-owned heraldry, show a neutral silhouette or country-colour field rather than invented pseudo-historical arms.
- Portrait frames are UI; portrait paintings are content. Keep them replaceable independently.
- Event art must use a consistent crop, grade, border, and safe text composition even when source paintings vary.

## Motion and feedback

Animation should clarify state, not slow routine play:

- 80–140 ms: button and tab response.
- 140–220 ms: panel reveal/collapse.
- 200–350 ms: important notification entrance.
- Avoid long travel animations for windows the player opens repeatedly.
- Provide reduced-motion behaviour that removes nonessential movement.
- Use sound and animation as reinforcement; never require either to understand the result.

## Naming and source layout

Recommended structure:

```text
art_source/ui/
├── components/
├── icons/
├── portraits/
├── events/
└── styleboards/

assets/ui/
├── theme/
├── frames/
├── controls/
├── icons/
├── portraits/
├── events/
└── cursors/
```

Runtime names use lowercase snake case:

```text
frame_window_major.png
button_primary_normal.png
button_primary_hover.png
icon_economy_treasury.png
icon_military_morale.png
mask_country_shield.png
```

Do not use filenames such as `final2`, `new_button`, `temp_good`, or a creator name as the only description.

## Visual-direction approval board

Before mass production, one board must show all of the following at actual game size:

- Top-left HUD segment with country identity and four resources.
- Province panel with tabs and a tooltip.
- Dense ledger table.
- Event popup with parchment content.
- Normal/hover/pressed/selected/disabled/focus button states.
- Positive, negative, warning, and critical messages.
- 16, 24, 32, and 64 px icon samples.
- 100%, 125%, and 150% scale samples.
- Lightest and darkest expected map backgrounds behind the UI.

Approval means the direction is readable, original, technically sliceable, and affordable to reproduce across every screen—not merely attractive as one illustration.

