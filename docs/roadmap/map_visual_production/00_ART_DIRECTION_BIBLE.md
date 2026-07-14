 # 00 — Map Art Direction Bible

## Purpose

Lock a coherent target before expensive terrain, shader, label, and content production begins. This is the visual contract used by design, map art, rendering engineering, UI/UX, content, and QA.

## Visual Thesis

The map should feel like a living early-modern political atlas laid over a tactile world. At wide zoom it is primarily a clean political diagram. At regional zoom geography and borders share attention. At close zoom terrain, rivers, settlements, armies, and local labels give the world character.

The intended result is inspired by the clarity of Europa Universalis IV and the regional texture of Crusader Kings II, but it must not imitate proprietary assets or reproduce another game's exact look. The project's identity should come from its own palette, type system, terrain materials, border language, and historical content.

## Reference Breakdown

Reference material should be studied by function rather than copied as a whole.

| Reference quality | What to learn | What not to copy |
|---|---|---|
| EU4 political mode | Muted country fills, strong country/province hierarchy, readable labels, water as negative space, useful zoom transitions | Exact colours, border textures, font treatment, map assets |
| EU4 terrain mode | Layered terrain, rivers, seasonal/environmental cues, animated water, map objects | Proprietary height, normal, terrain, tree, river, and water textures |
| CK2 terrain/realm map | Regional texture, holdings, heraldic identity, terrain readability | Character-first density or UI conventions that conflict with country-first play |
| Historical atlases | Typographic hierarchy, restraint, line weight, coast and river conventions | Period inaccuracies or projections that reduce gameplay clarity |
| Physical/climate maps | Sahara/Sahel transition, mountain ranges, forests, steppe, monsoon and polar zones | Satellite-photo realism and visual noise |

Research references already used for the assessment include the official EU4 and CK2 store imagery, contemporary EU4 reviews, technical frame-capture analysis, map-modding layer references, and Paradox map-development discussions. Store external links in an approved reference-board record with capture date and usage notes; do not import third-party imagery into shipping assets without rights review.

### Research register seed

These sources seed MV-0 research; they are evidence about visual layering and presentation, not permission to copy assets.

| Source | Production use |
|---|---|
| [Europa Universalis IV official store page](https://store.steampowered.com/app/236850/Europa_Universalis_IV/) | Official wide/regional political-map presentation references |
| [Crusader Kings II official store page](https://store.steampowered.com/app/203770/Crusader_Kings_II/) | Official terrain, holdings, and realm-presentation references |
| [PC Gamer EU4 review](https://www.pcgamer.com/europa-universalis-iv-review/) | Contemporary description of vibrant detail, seasons, routes, and units |
| [EU4 map-modding quick reference](https://www.eu4cn.com/wiki/Map_Modding_Quick_Reference) | Functional inventory of map data/layer categories to investigate |
| [EU4 reference map notes](https://xylozi.wordpress.com/eu4/reference-map/) | Height, normal, terrain, river, tree, season, and water layer comparison |
| [WebGL EU4-map analysis](https://nickb.dev/blog/simulating-the-eu4-map-in-the-browser-with-webgl/) | Country/province border hierarchy and political/terrain composition concepts |
| [EU4 GPU frame-capture analysis](https://www.hlsl.co.uk/blog/2018/7/18/what-can-we-learn-from-gpu-frame-captures-europa-universalis-4) | Render-pass and GPU investigation reference |
| [Paradox map-development discussion](https://forum.paradoxplaza.com/forum/developer-diary/eu4-development-diary-9th-of-october-2018.1122972/) | Evidence that attractive labels require art direction and manual map review as well as algorithms |

Each retained source should receive capture date, owner, claims used, rights note, and whether it is primary, secondary, or community technical research.

## Information Hierarchy

The hierarchy below is mandatory. A lower layer may support a higher layer but must not overpower it.

1. Current interaction: hover, selected province/country, command target, invalid action.
2. Active conflict: battle, occupation, siege, hostile army, war goal.
3. Political structure: sovereign border, subject relationship, country fill, province border.
4. Identity: country name, capital, important regional/province names.
5. Geography: coast, river, relief, biome, wasteland, lake.
6. Atmosphere: waves, clouds, weather, seasonal tint, decorative objects.

Debug and data map modes may deliberately replace this hierarchy, but must do so explicitly.

## Zoom Language

### Strategic world zoom

**Player question:** Who controls the world, where are the major powers, and where am I?

- Country colours and sovereign borders dominate.
- Country names are large, sparse, stable, and prioritised.
- Province borders are hidden or extremely subtle.
- Terrain is low contrast and supports continental shape.
- Armies and settlements collapse into aggregate or important-only markers.
- Small island detail may simplify, but ownership must remain discoverable.

### Regional campaign zoom

**Player question:** Which provinces, armies, terrain, and neighbours matter to the next decision?

- Country and province borders are both readable, with clear hierarchy.
- Major terrain, rivers, capitals, forts, ports, armies, and occupation become visible.
- Country labels remain readable but defer to interaction markers.
- Province or regional labels may appear according to mode.
- Water gains restrained coastal and motion detail.

### Tactical close zoom

**Player question:** What is in this province and what can I interact with?

- Province boundary, local relief, rivers, settlements, units, and action feedback dominate.
- Country labels fade, reduce, or yield to regional/province naming.
- Micro-detail appears through tiling/material layers rather than a huge unique texture.
- Decorative density remains capped so markers and tooltips are never obscured.

### Transition standard

- No uncontrolled popping.
- Major elements use hysteresis so a small zoom oscillation does not repeatedly toggle them.
- Fades are short, deterministic, and compatible with reduced-motion settings.
- Font sizes and line weights are clamped in screen pixels rather than scaling without bounds.

## Map-Mode Art Direction

| Mode | Political fill | Terrain | Borders | Labels | Primary purpose |
|---|---|---|---|---|---|
| Political | Muted country colour over legible terrain | Subordinate but present | Sovereign strong; province restrained | Country primary | Ownership and diplomatic geography |
| Terrain | Minimal/translucent political tint | Primary | Coast and province context | Reduced or optional | Movement geography and world appreciation |
| War | Attacker/defender/occupation overlays | Suppressed | War participants and fronts prominent | Belligerents prioritised | Conflict comprehension |
| Relations/access | Semantic colour ramp | Suppressed | Selected country context | Selected and relevant names only | Diplomatic analysis |
| Culture/religion/control/unrest/technology | Semantic data palette | Very low | Province clarity | Mode-specific policy | Data comparison |
| Province ID/debug | Exact technical colours/data | Off | Exact province boundary | Off by default | Development and validation |

Every map mode must declare its fill, terrain contribution, border stack, label policy, marker policy, legend, and colour-blind alternative. No layer should remain visible merely because it was not connected to the mode state.

## Colour Direction

- Political colours should use controlled saturation and luminance ranges, not unrestricted source RGB values.
- Neighbour separation remains a data constraint; attractive harmony cannot make adjacent countries indistinguishable.
- Water should occupy a narrower, calmer range than political land.
- Terrain variation should be primarily value, material, and low-frequency hue—not high-saturation noise.
- Selection and action colours are reserved accents and must not be common country colours.
- Wasteland, uncolonised land, owned land, occupied land, and impassable terrain require distinct semantics.
- Subject states remain visibly distinct countries unless a specifically approved map mode groups them under an overlord tint.
- France must not visually consume Orléans or another subject merely because a label or overlay uses the overlord's realm shape.

Create an Oklab-based palette review tool or report that shows neighbour distance, global duplicates, luminance, saturation, and colour-blind simulation. Automated thresholds identify risks; final art review decides the authored colour.

## Border Direction

The border stack should read from large political concept to local detail:

1. Coastline/land-water separation.
2. Sovereign country border.
3. Subject or special-relation border treatment where required.
4. Province border.
5. Selection, hover, route, occupation, and war overlays.

Requirements:

- Line weight is controlled in screen pixels or zoom-aware bands.
- Borders are not pure heavy black stickers at every zoom.
- Country borders remain stronger than province borders.
- Coast treatment does not become a neon halo.
- At wide zoom, province noise reduces before country structure does.
- Borders remain readable on light desert, dark forest, snow, and saturated countries.

## Terrain Direction

- Terrain is painterly/cartographic, not photorealistic.
- Macro forms communicate ranges, plains, deserts, forests, wetlands, and snow.
- Micro detail is subtle, tiling, and filtered; it must not shimmer during camera movement.
- Mountain ranges read as connected geographic forms rather than isolated noise.
- Desert has dune/rock variation and transitions through Sahel instead of one flat tan mask.
- Forest is suggested through material and sparse object layers, not a carpet that obscures borders.
- Snow and arid regions preserve label and border contrast.
- Physical geography is historically plausible for the period, while temporary seasons/weather remain presentation layers rather than permanent terrain truth.

## Camera Direction

- Camera pitch, field of view, height, relief exaggeration, and near/far clipping are art-direction variables, not only control settings.
- Strategic zoom should read like an atlas rather than an extreme perspective horizon.
- Regional and close zoom may reveal more relief, but selection, label projection, and marker scale remain stable.
- Camera movement uses smoothing only where it does not add input lag or motion sickness.
- Home/reset framing and benchmark bookmarks are deterministic.
- The camera must never expose mesh edges, texture seams, or empty space beyond the authored world treatment.

## Water and Coast Direction

- Deep ocean, shallow shelf, inland lake, river, and selection/route overlays are visually distinct.
- Motion is slow and low contrast at world zoom.
- Coastal shelves and foam are restrained and geography-aware.
- Rivers are readable at regional/close zoom and visually join lakes/coasts correctly.
- Grid lines, seams, texture edges, and wrap boundaries must not be visible.
- Low graphics settings keep water readable without expensive reflection or multi-layer animation.

## Typography Direction

- Public map labels always use full authored country names; internal tags remain developer/search metadata.
- The typeface must be bundled, licensed, crisp at supported resolutions, and tested with required writing systems.
- Country names follow realm shape when it helps readability, but do not become extreme arcs or illegible letter paths.
- Text has a restrained outline/shadow or contrast treatment appropriate to the active map mode.
- Labels have a clear priority hierarchy: sovereign/country, regional, province, capital, settlement, map object.
- Microstates may use a close-zoom full-name treatment, leader line, or authored placement hint; they do not fall back to `ENG`, `ORL`, or similar tags.

## Reference Scenes

The vertical slice must include more than one visually easy region.

| Scene | Problems it proves |
|---|---|
| Iberia and western Mediterranean | Large countries, coastlines, islands, arid/temperate transition, readable sovereign borders |
| France and Low Countries | Dense provinces, subjects/appanages such as Orléans, colour separation, label collision |
| Italy and Alps | Narrow/diagonal realms, mountains, microstates, dense borders, curved-shape label pressure |
| Scandinavia and Baltic | Long diagonal countries, islands/straits, snow/forest/water, wide labels |
| Sahara, Sahel, and Nile | Wasteland semantics, desert transition, river importance, sparse settlement |
| Maritime Southeast Asia | Islands, straits, coast density, fragmented realms, water performance |
| Andes and western South America | Long mountain chain, relief, climate range, narrow territories |
| North American interior | Uncolonised/indigenous ownership semantics, forests/plains, low-density labels |

## Visual Greenlight Deliverables

MV-0 cannot close until the following exist:

- Annotated current-state captures at the three target zoom bands.
- A legally safe reference board with functional notes.
- Two or three colour scripts showing possible project identity.
- Approved political-mode mock-up for Iberia/western Europe.
- Approved terrain/water mock-up covering at least desert, mountain, temperate coast, and open ocean.
- Typography tests for long names, microstates, diagonal countries, diacritics, and dense Europe.
- A render-layer diagram and preliminary cost model.
- A list of hard constraints: projection, texture sizes, target Godot version, supported renderer, and reference hardware.
- Decision records for political colour semantics, label render method, water tier, anti-aliasing, and terrain asset strategy.

## Review Cadence

- Daily implementation review inside the active strike team when a visual slice is changing rapidly.
- Weekly art/engineering capture review using identical camera bookmarks and builds.
- Milestone gate review with side-by-side current, target, and performance captures.
- No approval from editor-only screenshots; a packaged build on reference hardware is required.
- Review comments identify hierarchy/readability problems before subjective taste preferences.
- Approved captures become golden references and changes require an explicit update note.

## Art-Direction Exit Gate

- Stakeholders can identify the game from its palette and typography without seeing the UI.
- Political ownership is readable within two seconds in representative wide and regional captures.
- Geography is recognisable without the political overlay.
- Country labels are readable without dominating the map.
- The visual target is achievable within a measured performance projection.
- All reference and source material has an approved provenance path.
