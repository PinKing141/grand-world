# MV-0 Target Mock-ups — Production Brief

## Purpose

These frames define the visual destination for the first map-rendering slice. They are project-original direction concepts, not shipping textures and not authoritative geography. Implementation must continue to use the project's province IDs, ownership data, terrain data, and historical-content pipeline.

The concepts use the existing deterministic camera bookmarks so every review can compare:

1. current game capture;
2. target concept;
3. later in-engine implementation;
4. measured performance at the same view.

## Status

| Target | Bookmark | State | Primary question |
|---|---|---|---|
| A — France and Low Countries | `current_france_low_countries_political_1920x1080.png` | **In production** | Can dense 1444 ownership read cleanly without France consuming appanages? |
| B — Sahara and Nile | `current_sahara_nile_terrain_1700x960.png` | **Brief locked; concept queued** | Can geography, river structure, wasteland, and sparse settlement read without political noise? |
| C — Italy and Alps | `current_italy_alps_political_1152x648.png` | **Brief locked; concept queued** | Can diagonal realms, mountains, coasts, microstates, and typography coexist? |

Approval means Art/Product accept the direction and Technical Art can describe a plausible in-engine path. A generated concept alone is not approval.

## Shared Visual Contract

### Intended identity

- A living early-modern political atlas over a tactile, painterly world.
- Political clarity at strategic zoom; shared political/geographic attention regionally; geographic and object detail close in.
- Original palette, line language, terrain materials, water treatment, and typography.
- Restrained ornament: the map should feel authored and historical, not photorealistic, plastic, neon, or like a flat debug texture.

### Invariants

- Preserve the existing camera framing, coastlines, islands, country/province topology, and recognizable regional geography closely enough for side-by-side review.
- Do not invent a new projection or move borders merely to make a prettier composition.
- Use full country names. Never replace a public map label with an internal tag.
- Subjects and appanages keep separate legal ownership colours in political mode unless a separately approved realm mode groups them.
- In particular, the `France` label and fill must not claim Orléans or another appanage as directly owned French land.
- No UI, logos, trademarks, watermarks, flags, copied proprietary map art, or copied proprietary palette.
- Concept labels are illustrative. Final text must come from deterministic game data and the licensed font pipeline.

### Shared hierarchy

1. selection, hover, and commands;
2. active conflict and occupation;
3. sovereign borders, subject relationships, and political fill;
4. country identity and capitals;
5. province borders and local labels;
6. terrain, rivers, coasts, lakes, and water;
7. atmosphere and decoration.

The concepts omit selection and war overlays so the permanent map hierarchy can be judged in isolation.

### Shared material direction

- Political colour: muted mid-value pigment with enough neighbour distance; allow low-frequency terrain to show through.
- Sovereign border: dark neutral and confident, but narrower and softer than the current heavy black sticker line.
- Province border: fine, lower-contrast line that recedes at strategic zoom.
- Subject/appanage relationship: its own colour and border, plus a subtle relationship cue to the overlord; never ownership rewriting.
- Coast: crisp land/water separation with a restrained shallow shelf; remove the current electric-blue halo.
- Water: calm dark blue-green depth gradient, subtle cartographic grain, no dominant high-frequency animation.
- Relief: connected geographic forms, not isolated blurred blobs.
- Terrain detail: authored macro shape plus tileable micro detail; no satellite-photo realism.
- Typography: crisp atlas serif, restrained outline/shadow, stable screen-space weight, gentle territorial alignment, and no extreme arcs or stretched glyphs.

## Target A — France and Low Countries Political Mode

### Player questions

- Where does France directly rule in 1444?
- Which nearby polities are independent, subjects, appanages, or foreign neighbours?
- Can the player identify major countries in two seconds without losing dense province structure?

### Direction

- France uses a controlled cool blue family; neighbouring England, Burgundy, Brittany, Aragon, Castile, Savoy, the Low Countries, and imperial states use restrained distinct hues.
- Orléans and every other authored appanage remain separately coloured and bounded. A subtle subject cue may relate them to France without making them French-owned provinces.
- France receives one large, crisp, gently angled full-name label fitted only to a valid directly owned connected component.
- Large neighbours receive appropriately scaled full-name labels. Dense small states use fewer labels at this zoom, with authored priority rather than unreadable microscopic text.
- Country borders are clear; province borders are thin and approximately one visual tier quieter.
- Terrain remains visible as low-contrast plains, forests, relief, and major river structure.
- Capitals and armies are excluded from this target frame so border, palette, coast, and label quality can be judged.

### Acceptance checks

- France does not visually absorb Orléans or other non-owned land.
- No full-name label crosses a foreign or subject component merely to fill space.
- Sovereign edges read at normal size without a black cartoon outline.
- The English Channel and Atlantic coast read without a cyan glow.
- Dense Low Countries remain separable without high-saturation confetti.
- Labels are legible at 100% and remain credible at 75% display scale.
- The visual target has a plausible runtime decomposition using existing authoritative data plus generated presentation layers.

### Concept prompt record

~~~text
Use case: stylized-concept
Asset type: grand-strategy game map visual-direction frame
Input images: Image 1 is the project's current France/Low Countries benchmark and composition reference
Primary request: restyle this exact regional map into a polished, original early-modern political-atlas map target while preserving the recognizable coastlines, islands, camera framing, and province topology
Style/medium: top-down painterly cartographic game map; refined production concept; not UI and not a historical paper scan
Composition/framing: retain the 16:9 France/Low Countries view from Image 1
Color palette: muted mid-value country pigments with strong neighbour separation; calm blue-green water; restrained terrain beneath political colour
Materials/textures: subtle paper-like pigment grain, connected relief, restrained forest/plains texture, crisp coast shelf, thin province boundaries, stronger sovereign boundaries
Text (verbatim where geographically appropriate): "France", "England", "Brittany", "Burgundy", "Orléans", "Aragon", "Castile", "Savoy"
Constraints: full country names only; France must cover directly owned land only; Orléans and other appanages remain separately coloured and bounded; large labels follow territory with a gentle readable angle; small-state labels may be omitted rather than made microscopic; no UI; no marker rectangles; no logos; no flags; no watermark; no copied proprietary assets or exact palette
Avoid: heavy pure-black outlines; neon cyan coasts; oversaturated country confetti; blurry text; extreme letter stretching; labels crossing unrelated realms; photorealistic satellite texture
~~~

## Target B — Sahara and Nile Terrain Mode

### Player questions

- Can the player instantly distinguish Mediterranean coast, Atlas, Sahara, Sahel, Nile valley, Red Sea, and Arabian desert?
- Do passable corridors and inhabited river/coastal zones read against impassable or sparse wasteland?
- Does terrain remain calm enough for future borders, units, and labels?

### Direction

- The Nile is the organizing geographic feature: continuous, readable, connected to its delta and Mediterranean mouth, with a narrow fertile floodplain.
- Sahara uses more than one brown field: ergs/dunes, rocky plateau, mountain mass, dry basin, and oasis/floodplain are distinct but cohesive.
- The Atlas and Ethiopian highlands read as connected relief systems.
- Sahel transitions gradually from desert to scrub/grassland rather than a hard painted band.
- Mediterranean, Red Sea, and open Atlantic water share the water family while showing restrained depth and coastal shelf differences.
- Political tint and country labels are minimal. Major geographic names may be added only after the terrain pass works without them.

### Acceptance checks

- The Nile remains visible from the regional camera without becoming a glowing game trail.
- Sahara, Sahel, cultivated valley, highlands, coast, and water are distinguishable at a glance.
- Wasteland semantics can be layered without implying that all desert is empty or impassable.
- No blurred macro blobs, texture seams, electric coast halo, or dominant repeating tile.
- There is visual room for borders and units at regional zoom.

### Concept prompt record

~~~text
Use case: stylized-concept
Asset type: grand-strategy game terrain-map visual-direction frame
Input images: Image 1 is the project's current Sahara/Nile benchmark and composition reference
Primary request: transform the current terrain presentation into an original painterly early-modern cartographic landscape while preserving the recognizable regional framing, coastline, Red Sea, Nile route, and landmass geometry
Style/medium: top-down tactile game terrain map, authored macro geography with restrained material detail
Composition/framing: retain the benchmark's wide Sahara/Nile framing
Color palette: warm but controlled ochre and umber desert family; muted green floodplain and Sahel; stone highlands; calm dark blue-green water
Materials/textures: connected mountain relief, rocky hamada, subtle dune fields, Sahel scrub transition, narrow fertile Nile valley and delta, subdued coastal shelf
Constraints: terrain is primary; Nile is continuous from south through delta to sea; no political colour confetti; no country labels; no UI; no army markers; no logos; no watermark; original assets only
Avoid: one flat tan desert; blurry blobs; satellite realism; glowing rivers; electric-blue coastlines; noisy repeating microtexture; invented seas or displaced geography
~~~

## Target C — Italy and Alps Integrated Regional Mode

### Player questions

- Can narrow and diagonal realms be identified without horizontal labels floating over neighbours?
- Do Alps, Apennines, Po valley, Adriatic, and Tyrrhenian coasts matter without defeating political clarity?
- Can microstates remain selectable while the regional picture stays calm?

### Direction

- Alps and Apennines use connected relief with different scale and visual weight.
- Political tint is translucent enough for relief and river corridors to remain legible.
- Country borders dominate province borders; microstates get precise edges without oversized black strokes.
- `Naples` follows the peninsula with a restrained diagonal baseline. Long or fragmented realms use a straight or gently curved fitted line, not a warped ribbon.
- Microstate names use close-zoom priority or authored callout behavior; they are not squeezed into illegible text.
- Water supports coast/island recognition with restrained shelf variation around Sicily, Sardinia, Corsica, and the Adriatic.

### Acceptance checks

- Country labels are crisp, use full names, and do not cross unrelated territory.
- Labels align with the dominant country axis while individual glyphs remain upright and readable.
- The Alps do not hide borders; borders do not erase the Alps.
- Province hierarchy stays readable in northern Italy and the Adriatic coast.
- Islands, straits, and peninsulas remain geographically clear without the cyan halo.

### Concept prompt record

~~~text
Use case: stylized-concept
Asset type: grand-strategy game integrated political/terrain and typography visual-direction frame
Input images: Image 1 is the project's current Italy/Alps benchmark and composition reference
Primary request: restyle this exact regional map into a polished original political-atlas game map that integrates connected relief, calm coasts, hierarchical borders, and shape-aware full country labels
Style/medium: top-down painterly cartographic game map; tactile terrain beneath muted political pigment
Composition/framing: retain the benchmark Italy/Alps framing and recognizable province/country topology
Color palette: restrained neighbouring country pigments; cool stone Alps; warm Mediterranean land; calm blue-green seas
Materials/textures: connected Alps and Apennines, Po valley, restrained forest/plains texture, subtle shallow-water shelf
Text (verbatim where geographically appropriate): "Naples", "Papal States", "Venice", "Milan", "Savoy"
Constraints: full country names only; labels align gently to each realm's dominant axis without bending individual glyphs; country borders stronger than province borders; tiny polities may defer labels; no UI; no markers; no logos; no flags; no watermark; original assets only
Avoid: horizontal labels detached from country shape; extreme arcs; fuzzy glyphs; heavy black borders; cyan coast glow; flat terrain; unreadable microstate text
~~~

## Layer Ownership and Runtime Translation

| Visual element | Source class | Planned production path | Optional / quality response |
|---|---|---|---|
| Province ownership and coast mask | Authoritative authored/imported data | Exact province IDs and country ownership lookup | Never approximated by concept art |
| Subject/appanage semantics | Authoritative authored data | Diplomacy/subject relation plus border/fill policy | Realm grouping only in an explicit map mode |
| Political palette | Authored rules + generated validation | Oklab palette constraints, neighbour graph checks, art review | Lower tier keeps the same semantic colours |
| Country/province border fields | Generated from topology | Exact adjacency plus distance/edge field presentation | Simplify province detail first at wide zoom |
| Terrain class and height | Authored/generated world data | Validated categorical imports, height/normal/material stack | Reduce micro detail before macro geography |
| Rivers | Authoritative authored geographic data | Stable river graph/vector source and generated render representation | Minor tributaries may cull by zoom |
| Water/coast | Generated/runtime material | Depth/shelf/coast masks and restrained animated material | Low tier removes expensive motion/reflection |
| Country labels | Runtime data + authored hints | Full localized names, fitted components, screen-space or hybrid renderer | Reduce density before abbreviation |
| Microstate labels | Runtime data + authored exceptions | Priority, callout, and zoom rules | Hide/defer; never use internal tags publicly |
| Concept texture/grain | Reference only | Rebuilt from owned/licensed procedural/source material | May be removed on low tier |

## Review Sheet

Score each frame from 1 (fails) to 5 (production target) and record evidence.

| Criterion | A | B | C | Required |
|---|---:|---:|---:|---:|
| Two-second ownership/geography read | — | — | — | 4 |
| Political hierarchy | — | N/A | — | 4 |
| Terrain hierarchy | — | — | — | 4 |
| Coast/water restraint | — | — | — | 4 |
| Full-name typography clarity | — | N/A | — | 4 |
| Shape-aware label placement | — | N/A | — | 4 |
| 1444 subject/appanage correctness | — | N/A | N/A | 5 |
| Original project identity | — | — | — | 4 |
| Plausible runtime decomposition | — | — | — | 4 |
| Low-end performance path | — | — | — | 3 |

Any score below the requirement blocks Visual Greenlight. Reviewers must identify a concrete hierarchy, data, readability, provenance, or performance issue rather than only saying that a frame feels better or worse.

## Production Sequence After Concept Approval

1. Lock one colour script and country/subject semantics.
2. Run TD-006 AA/sampling comparison against Target A and Target C.
3. Run TD-007 label-renderer comparison against Target A and Target C.
4. Run TD-008/TD-009 import and resolution comparisons against all three targets.
5. Build the MV-1 France/Low Countries in-engine slice.
6. Validate political correctness, label fit, click agreement, movement sharpness, memory, and frame time.
7. Extend the accepted stack to Sahara/Nile and Italy/Alps before global rollout.

