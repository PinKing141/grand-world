# AI Image-Generation Prompts for the UI Art Set

Companion to `UI_ART_REQUIREMENTS.md`. Ready-to-paste prompts for generating every
visual asset with an AI image tool (Flow, Midjourney, DALL-E, Stable Diffusion,
Firefly — the prompts are tool-agnostic).

## How to use this file (read first — this is what keeps the set consistent)

1. **Always prepend the Master Style Block** to every prompt below. Consistency
   comes from repeating the same style language, not from luck.
2. **Generate in batches per section in one session**, reusing the same seed or
   style reference image if your tool supports it. Mixed sessions drift.
3. **Icons:** generate at 1024×1024 on a plain dark background, then downscale to
   32×32. AI tools cannot produce true transparency — remove the background
   yourself (one flat background color makes this trivial).
4. **Tileable textures:** add "seamless tileable texture" and verify by offsetting
   the image by 50% in an editor; fix seams or regenerate.
5. **Nine-patch frames:** generate the whole ornate frame as one square image on a
   plain center; you slice it into a nine-patch in Godot (StyleBoxTexture margins).
   Symmetry matters — add "perfectly symmetrical" and be prepared to mirror one
   good corner in an editor instead of hoping all four match.
6. **After generating, recolor everything to the palette** (antique gold
   `#b99a5f`, dark blue-brown surface, parchment `#d8c9a3`) so mixed batches read
   as one game.
7. Check your generator's terms allow commercial game use, and never include
   "EU4", "Europa Universalis", or "Paradox" in a prompt — describe the style,
   not the trademark.

---

## Master Style Block (prepend to EVERY prompt)

```text
15th-17th century European grand strategy game UI art, antique gold and dark
leather palette, muted antique gold #b99a5f ornament on very dark desaturated
blue-brown #10151c background, aged parchment accents #d8c9a3, engraved
baroque-renaissance style, clean crisp edges, high detail, no text, no
watermark, no photograph, game asset
```

Suggested negative prompt (tools that support it):

```text
text, letters, watermark, signature, photo, 3d render, plastic, neon, blur,
modern, minimalist flat design, cartoon, anime
```

---

## 1. Textures (generate at 1024×1024, downscale to 512 or 256)

**Panel background (dark leather):**
```text
seamless tileable texture, dark worn leather with very subtle grain and faint
mottling, extremely dark desaturated blue-brown, low contrast, no seams, no
distinct objects, uniform lighting, suitable as a quiet UI panel background
```

**Parchment (event popups, flavor text):**
```text
seamless tileable texture, aged parchment paper, soft cream and tan tones,
faint fibers and gentle stains, low contrast, no writing, no burns, uniform
lighting, quiet background texture
```

**Top bar strip (dark wood):**
```text
seamless tileable texture, dark polished walnut wood planks, horizontal grain,
very dark and low contrast, subtle sheen, no knots dominating, UI header strip
```

**Vignette overlay:**
```text
square black soft vignette overlay, transparent-looking plain mid-gray center
fading to darkened edges and corners, smooth radial gradient only, no texture,
no objects
```

---

## 2. Nine-Patch Frames (generate at 1024×1024, plain flat center)

**Main window frame (the signature asset — spend the most attempts here):**
```text
ornate rectangular picture frame border for a strategy game window, engraved
antique gold baroque trim with decorative corner flourishes, perfectly
symmetrical, thin elegant border approximately 5 percent of image width, flat
plain very dark empty center, subtle bevel and inner shadow, crisp edges
```

**Sub-box inset frame:**
```text
thin simple rectangular inset frame, narrow antique gold double-line border
with tiny corner studs, perfectly symmetrical, flat plain very dark empty
center, recessed engraved look, restrained and quiet, crisp edges
```

**Button (generate 4 variants by swapping the state phrase):**
```text
rectangular game UI button, subtle raised bevel, dark leather face with thin
antique gold edge trim, perfectly symmetrical, empty face with no text,
[STATE]
```
- normal: `neutral soft lighting`
- hover: `slightly brighter gold trim, gentle outer glow`
- pressed: `inverted bevel, face slightly darkened, pressed inward`
- disabled: `desaturated, dimmed, no glow`

**Tooltip frame:**
```text
minimal rectangular border, single thin antique gold rule with tiny corner
ticks, flat near-black empty center, perfectly symmetrical, very restrained
```

**Header banner plate:**
```text
long horizontal ornamental banner plate for a window title, engraved antique
gold ends with a subtle ribbon or scroll motif, flat dark center band for
text, perfectly symmetrical left and right, wide aspect ratio
```

**Divider:**
```text
long thin horizontal ornamental divider rule, antique gold, small central
diamond or fleuron motif, tapering engraved ends, transparent-style plain
dark background, wide aspect ratio
```

**Tabs (two states):**
```text
game UI tab shape, trapezoid with rounded top corners, dark leather face with
thin gold top edge, empty face, [active: brighter gold trim and lit face /
inactive: dimmed flat face]
```

**Progress bar (trough and fill separately):**
```text
trough: long thin recessed horizontal groove, dark inset channel with thin
gold edge, empty, wide aspect ratio
fill: long thin horizontal bar of warm antique gold with subtle gradient and
soft inner glow, wide aspect ratio
```

---

## 3. Icon Master Template

All icons use this wrapper — replace `[SUBJECT]`:

```text
single game UI icon of [SUBJECT], engraved antique gold emblem style with
parchment and muted color accents, centered, bold readable silhouette that
stays clear at 32 pixels, plain flat very dark background, no border, no text
```

### 3a. Resource bar (7)
| Icon | [SUBJECT] |
|---|---|
| Treasury | a small pile of gold ducat coins |
| Monthly balance | a gold coin with an upward arrow |
| Manpower | two crossed pikes over a soldier helmet |
| Development | a rising city skyline of medieval rooftops |
| Stability (P8) | a balanced classical scale |
| War status | two crossed swords |
| Sailors (later) | a ship wheel |

### 3b. Economy (12)
| Icon | [SUBJECT] |
|---|---|
| Tax | an open ledger book with a coin |
| Production | a blacksmith anvil and hammer |
| Trade value | a merchant scale with coins |
| Building slot | an empty stone foundation plinth |
| Construction | wooden scaffolding with a crane pulley |
| Tax Office | a stone counting house facade |
| Workshop | a watermill wheel |
| Barracks | a military tent with a banner |
| Loan / debt | a money bag bound in chains |
| Interest | an hourglass with falling coins |
| Maintenance | a wrench crossed with a supply sack |
| Ledger | a thick bound account book |

### 3c. Military (9)
| Icon | [SUBJECT] |
|---|---|
| Infantry regiment | a pikeman silhouette with raised pike |
| Army strength | a clenched armored gauntlet |
| Morale | a waving battle standard |
| Movement | a marching boot with motion lines |
| Siege | a trebuchet against a tower |
| Battle | two clashing sabers with a spark |
| Occupation | a flag planted on a captured wall |
| War goal | a laurel wreath around a fortress |
| Disband | a broken sword |

### 3d. Diplomacy (10)
| Icon | [SUBJECT] |
|---|---|
| Relations | two clasped hands |
| Improve relations | a dove carrying an olive branch |
| Alliance | two interlocked rings |
| Military access | an open city gate with a road |
| Declare war | a thrown gauntlet |
| Peace offer | a quill signing a treaty scroll |
| White peace | a plain white flag |
| Truce | an hourglass between two shields |
| Attacker | a sword pointing right |
| Defender | a kite shield |

### 3e. Map modes (7)
Use flat simplified emblems (they sit on small square buttons):
political: a heraldic shield · terrain: a mountain range · tax: a coin ·
production: an anvil · manpower: a helmet · development: a castle tower ·
diplomacy overlays: a handshake over a map

### 3f. Phase 6 — AI attitudes (6)
friendly: a raised open hand · neutral: a horizontal balance bar ·
threatened: a cowering shield · hostile: a snarling wolf head ·
rival: two opposed chess kings · objective: a target reticle over a banner

### 3g. Phase 7 — Characters (12)
ruler: a royal crown · heir: a small coronet · consort: a ring and rose ·
regency: a crown on a cushion · admin skill: a quill and scroll ·
diplomatic skill: a sealed letter · military skill: a commander baton ·
dynasty: a heraldic eagle crest · death: a funerary wreath ·
succession: a crown passing between two hands · claim throne: a throne chair ·
court: a palace doorway

### 3h. Phase 8 — Trade goods (31, from economy_definitions.json)
Template: `a [GOOD] as a market commodity emblem`
chinaware: a porcelain vase · cloth: a folded bolt of cloth · cloves: a sprig of
cloves · cocoa: a cacao pod · coffee: a coffee sack and beans · copper: a copper
ingot · cotton: a cotton boll · dyes: a dye pot with drip · fish: a herring ·
fur: a pelt · gems: a cut gemstone · glass: a glassblower vessel · gold: a gold
ingot · grain: a wheat sheaf · incense: a smoking censer · iron: an iron ingot ·
ivory: an elephant tusk · livestock: a bull head · naval_supplies: a coil of rope
and tar barrel · paper: a paper scroll stack · salt: a salt mound in a bowl ·
silk: a silkworm cocoon on silk ribbon · slaves: broken shackles (handle with
care and historical gravity) · spices: a spice sack spilling peppercorns ·
sugar: sugar cane stalks · tea: tea leaves in a chest · tobacco: rolled tobacco
leaves · tropical_wood: dark hardwood logs · wine: a wine amphora · wool: a
sheep fleece · unknown: a burlap sack with a question-mark-free plain tie

### 3i. Phase 8 — Systems (~30)
government: a stone capitol column · reform: a scroll with seal · legitimacy: a
sceptre · centralisation: converging roads to a capital · stability: a balanced
scale · unrest: a raised torch · revolt risk: a powder keg · rebels: a torn
banner · separatism: a splitting shield · culture: a lute · accepted culture:
two linked medallions · religion (per group): a chapel / a crescent / a temple
as appropriate · tolerance: an open palm with flame · conversion: a radiant
sunburst · religious unity: a ring of candles · admin tech: an astrolabe ·
diplo tech: a sextant · military tech: a cannon · era: a sundial · ideas: an
oil lamp · core: an anchored banner · claim: a stamped charter · fabricate
claim: a forged document and quill · vassal: a bowed knight · personal union:
two crowns on one cushion · liberty desire: straining chains · subject income:
tribute chest · decision: a signet ring pressing wax · event: a sealed letter
opened · mission: a compass rose

### 3j. Phase 9 — Interface chrome (~15)
alert: a ringing bell · settings: a quill in an inkwell · save: a wax-sealed
scroll · load: an unrolled scroll · menu: a heraldic cartouche · sort: engraved
chevrons · outliner army/siege/build: miniature variants of 3c icons ·
difficulty: one-to-three stars · suggested nation: a pointing compass needle

---

## 4. Portraits (Phase 7)

Prefer public-domain paintings (see UI_ART_REQUIREMENTS.md §6). If generating:

```text
oil painting portrait of a [15th/16th/17th] century [region] [monarch / noble /
general / advisor], [male/female], [young/middle-aged/elderly], dark neutral
background, three-quarter view, renaissance master style, dramatic warm
lighting, aged varnish look, no text, no frame
```

Generate 30–60 varying century, region, role, age, and sex. Then apply ONE
shared color-grade to the whole set. Keep faces generic — do not name real
historical figures in prompts (likeness and style-imitation issues; also keeps
portraits reusable for any character).

## 5. Event Art (Phase 8, 12–20 reusable images, ~3:2 landscape)

```text
oil painting in the style of a 16th century european master, [SCENE], dramatic
chiaroscuro lighting, warm aged varnish tones, painterly brushwork, no text
```

Scenes: a pitched pike-and-shot battle · a royal court audience · a peasant
harvest · a plague procession · a cathedral interior mass · a bustling harbor
market · a ship in a storm · a siege camp at dawn · a treaty signing · a
coronation · a scholar's study with maps · a burning village · a merchant
caravan · a royal wedding feast · a monastery scriptorium · an executioner's
scaffold · a mine works · a colonial landing

## 6. What NOT to generate

- **Fonts** — use SIL OFL fonts (Cinzel, Alegreya, EB Garamond); AI-generated
  lettering is unusable for UI.
- **Country flags/shields** — generate one blank shield FRAME, then fill with
  each country's existing map color programmatically; 1,000 generated flags
  would never stay consistent.
- **The map itself** — already built from real elevation data.
- **Audio** — source CC0 packs or period recordings (see requirements doc).

## 7. Post-Processing Checklist (every batch)

- [ ] Background removed (icons) or seam-verified (textures)
- [ ] Recolored to palette; one shared grade applied to portraits/event art
- [ ] Downscaled with sharpening; checked for readability at 32px and 16px
- [ ] Exported PNG, named `icon_<domain>_<name>.png` / `tex_<name>.png` / `frame_<name>.png`
- [ ] Added to `assets/ui/` with the generator noted in ATTRIBUTIONS.md
