# UI Art & Style Requirements

Everything needed to take the interface from the current flat debug look to an
EU4-calibre themed UI. Derived from the systems each roadmap phase introduces:
an asset is listed in the earliest phase whose systems display it. Nothing here
touches simulation, saves, or determinism — it is all presentation.

**When to build:** the *Design Language* and *Theme Foundations* sections are the
"theme pass" scheduled at the start of Phase 6 (the vertical slice must prove the
UI pipeline). Each later section lands with its phase. Final polish, additional
screens, and audio belong to Phase 9's UI Completion gate.

---

## 1. Design Language (decide once, before any asset is made)

These decisions make every later asset consistent. Write the chosen values into
a style reference image and stick to it.

| Decision | EU4 reference | Recommendation |
|---|---|---|
| Base surface | Dark leather/parchment texture | Dark desaturated blue-brown, subtle 256×256 tileable texture, ~4% noise |
| Frame metal | Gold/brass trim | Muted antique gold `#b99a5f` range for borders, dividers, header accents |
| Header text | Small-caps serif, gold on dark | Serif display font, ~17px, letter-spaced small caps |
| Body text | Clean readable face | Neutral sans or humanist serif, 12–13px |
| Number colors | Green positive / red negative / gold neutral | Keep the existing green `#6fd08c` / red `#f28c7a`, add gold for headers |
| Accent shape | Bevels, corner flourishes | One corner-ornament motif reused on every window |
| Country identity | Shields, flags, color strips | Country color strip + generated heraldic shield frame |

### Core font files (2–3 total, SIL OFL licensed so they ship free)
- [ ] Display serif for titles/headers (candidates: Cinzel, IM Fell English SC, Alegreya SC)
- [ ] Body face for labels and numbers (candidates: Alegreya Sans, Source Sans, EB Garamond for flavor text)
- [ ] Optional: tabular-figure variant for the ledger so numbers align

### Texture set (tileable, one-time)
- [ ] Panel background texture (dark parchment/leather, 256×256 tileable)
- [ ] Lighter parchment texture for event popups and flavor text areas
- [ ] Wood or stone texture for the top bar strip
- [ ] Subtle vignette/inner-shadow overlay for recessed sub-boxes

### Nine-patch frame set (each is ONE image reused everywhere)
- [ ] Window frame: ornate border with corner flourishes (main windows)
- [ ] Sub-box frame: thin inset frame (grouped values inside windows, e.g. "Province Values")
- [ ] Button frame: raised bevel with hover/pressed/disabled variants (4 states)
- [ ] Tooltip frame: thin gold rule on dark
- [ ] Header plate: horizontal banner strip behind window titles
- [ ] Divider: horizontal rule with end-caps or center ornament
- [ ] Tab: active and inactive variants for tabbed windows
- [ ] Progress bar: trough + fill (sieges, construction, recruitment share it)

---

## 2. Theme Foundations in Godot (the Phase 6 theme pass)

- [ ] One project-wide `Theme` resource applied at the root; delete the per-node
      `font_size` overrides scattered through the HUD scenes
- [ ] StyleBoxTexture entries for PanelContainer, Button (4 states), TabContainer,
      LineEdit, OptionButton, ProgressBar, ItemList, tooltip panel
- [ ] Font sizes as theme defaults: 17 title / 14 section / 13 body / 12 dense
- [ ] A reusable tooltip scene: icon + title + body + breakdown lines (every number
      in EU4 explains itself on hover — the framework comes now, content grows per phase)
- [ ] A reusable "framed group" container scene (header plate + sub-box frame)
- [ ] Icon atlas convention: 32×32 source, drawn on a shared palette, exported once
      per icon; name them `icon_<domain>_<name>.png`

---

## 3. Icon Inventory by Phase

Sizes: 32×32 for bars/panels, 16×16 auto-downscale for inline text use.
Counts are the real target; "unknown" trade good needs a placeholder icon too.

### Already-shipped systems (Phases 2–5) — needed AT the theme pass (~45 icons)

**Resource bar (7):** treasury/ducats, monthly balance, manpower, sailors-placeholder
(skip until naval), development, stability-placeholder (Phase 8), war status

**Economy (12):** tax, production, trade value, building slot, construction,
Tax Office, Workshop, Barracks, loan/debt, interest, maintenance, ledger

**Military (9):** infantry regiment, army strength, morale, movement/march,
siege, battle, occupation, war goal, disband

**Diplomacy (10):** relations, improve relations, alliance, military access,
declare war, peace offer, white peace, truce, attacker marker, defender marker

**Map modes (7):** political, terrain, tax, production, manpower, development,
relations/war/access (one icon each or a shared style)

### Phase 6 — AI vertical slice (~6 icons)
- [ ] AI attitude markers (friendly, neutral, threatened, hostile)
- [ ] Rival/threat marker
- [ ] Objective marker for the AI debug overlay (debug-styled is fine)

### Phase 7 — Characters & dynasties (~12 icons + portrait system)
- [ ] Ruler, heir, consort markers; regency
- [ ] Monarch skill pips (administrative / diplomatic / military — the EU4 crown/quill/sword trio)
- [ ] Dynasty crest frame
- [ ] Death/succession notification icons
- [ ] **Portrait framework:** frame texture + 30–60 period portraits
      (public-domain 15th–18th century paintings, cropped to a shared frame,
      one shared treatment/filter so they feel uniform)

### Phase 8 — Country depth & content (~60–80 icons; the big batch)
- [ ] **Trade goods (31, already in data):** chinaware, cloth, cloves, cocoa, coffee,
      copper, cotton, dyes, fish, fur, gems, glass, gold, grain, incense, iron, ivory,
      livestock, naval_supplies, paper, salt, silk, slaves, spices, sugar, tea, tobacco,
      tropical_wood, wine, wool + unknown placeholder
- [ ] Government types (3–5) and reform/law icon
- [ ] Stability, unrest, revolt risk, rebel faction, separatism, legitimacy, centralisation
- [ ] Culture, accepted culture, religion (one per religion group you ship), tolerance, conversion
- [ ] Technology (admin/diplo/military) + era marker
- [ ] Ideas/national direction group icons (one per group)
- [ ] Cores, claims, fabricate claim
- [ ] Subjects: vassal, personal union, liberty desire
- [ ] Expanded building families and unit upgrade tiers (one per new entry)
- [ ] **Event popup art:** 12–20 reusable flavor images (public-domain paintings:
      battle, court, harvest, plague, religion, trade, sea, construction…) — events
      reference a small shared pool, exactly like EU4 does

### Phase 9 — Release polish (~15 icons + screens)
- [ ] Notification/alert row icons (the EU4 top-center alert strip)
- [ ] Ledger category icons, sort arrows
- [ ] Settings, save/load slot, main menu iconography
- [ ] Difficulty/suggested-nation markers for the nation picker
- [ ] Cursor set (default, hover, drag) if desired

---

## 4. Screen & Window Inventory (structure, mapped to phases)

| Screen | Phase | Notes |
|---|---|---|
| Themed top bar (icons + numbers + tooltips) | 6 | Replaces text-only resource bar |
| Tabbed province window (Economy / Military / Culture-Religion) | 6 | Restructure existing panels into tabs |
| Tabbed country window (Overview / Diplomacy / Economy / Military) | 6 | Same pattern |
| War overview + peace screen (themed) | 6 | Slice must demo the war loop cleanly |
| Court/character window | 7 | Portraits, skills, succession |
| Event popup (image + flavor text + option buttons) | 8 | Small framework, big content |
| Government / technology / ideas windows | 8 | One themed window template reused |
| Nation selection screen (map + country card + history blurb) | 9 | Your third screenshot |
| Full ledger (sortable tables) | 9 | |
| Outliner (armies/sieges/construction sidebar) | 9 | Quality-of-life |
| Main menu + settings + save management | 9 | |
| Message settings / notification feed | 9 | |

---

## 5. Audio (Phase 9, cheap but transforms feel)

- [ ] UI click, hover tick, window open/close
- [ ] Event popup sting, war declaration sting, peace signed sting
- [ ] Monthly tick ambience at high speed (optional)
- [ ] One period music track for menu + 2–3 for gameplay (public-domain recordings
      of period compositions exist; check the *recording* license, not just the composition)

---

## 6. Sourcing & Licensing Rules

- **Never** extract or trace Paradox assets — same rule as the map data.
- Icons: game-icons.net (CC BY 3.0, needs attribution screen — 4,000+ icons covering
  almost every entry above), Kenney.nl packs (CC0). Recolor to the shared palette so
  mixed sources look uniform.
- Textures: ambientCG / Poly Haven (CC0) for leather, parchment, wood, paper.
- Portraits & event art: public-domain paintings (Wikimedia Commons, museum open-access
  collections — Rijksmuseum, Met, NGA all offer CC0 downloads). Apply one shared
  color-grade so 60 different painters read as one game.
- Fonts: Google Fonts under SIL OFL only; keep license files in `assets/fonts/`.
- Keep an `ATTRIBUTIONS.md` at repo root from the first CC-BY asset onward.

---

## 7. Totals & Effort Snapshot

| Batch | When | Size |
|---|---|---|
| Design language + textures + 9-patch frames + Theme resource | Phase 6 start | ~15 art files, ~1 week including restyling existing HUDs |
| Core icon set | Phase 6 | ~45 icons (sourced + recolored, 1–2 days) |
| Character icons + portrait pipeline | Phase 7 | ~12 icons + 30–60 portraits |
| Content icon batch + event art | Phase 8 | ~60–80 icons + 12–20 paintings |
| Screens, alerts, audio, cursor | Phase 9 | ~15 icons + audio set |
| **Total by 1.0** | | **~140–160 icons, ~20 textures/frames, 2–3 fonts, 40–80 art images, ~10 sounds** |

The single highest-leverage item on this list is the first row: one Theme resource
with real textures and frames restyles every existing panel at once, and every
panel built afterwards inherits it for free.
