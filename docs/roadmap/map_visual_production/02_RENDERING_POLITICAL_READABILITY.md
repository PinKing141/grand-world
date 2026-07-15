# 02 — Rendering and Political Readability

## Outcome

Create a stable, sharp, zoom-aware map renderer in which political information is immediately understandable and every map mode owns its complete layer policy.

## Current Baseline

The current implementation is a useful prototype but has structural limits:

- `shaders/final_output_political_map.gdshader` is unshaded and combines a strong political overlay with a simplified two-sample relief treatment.
- Terrain and political layers do not yet behave like distinct authored material systems.
- Water is a static texture mix rather than a complete ocean/coast material.
- `shaders/political_map.gdshader` uses strong black country edges and fixed edge parameters that can read like sticker outlines.
- Several visual assets are lower resolution than the province ownership source, creating softness and alignment pressure.
- No complete project-level anti-aliasing and output-quality policy has been locked.
- Earlier captures showed dark/saturated fills, heavy borders, bright coast edges, pixel stair-stepping, and debug marker shapes. Borders/coasts and the first complete historical-placeholder marker family have since received engineering passes; bespoke final art remains.

The first MV-1 pass now uses a normalized palette, distinct subject/appanage realm tint, lighter internal-realm edges, dark sovereign/coast edges, restrained navy water, the corrected categorical terrain-class input, and final-output derivative-based line weights that remain stable during zoom. Province detail fades by zoom band; hover, selection, and occupation have higher-priority outlines. Art review and close-zoom topology quality remain open.

## Target Render-Layer Contract

The map renderer should expose explicit ordered layers rather than implicit shader side effects:

~~~text
Base land/water mask
→ terrain macro colour
→ terrain relief/normal/material response
→ water/coast/river material
→ political or data-mode fill
→ sovereign/subject/province borders
→ occupation/war/control overlays
→ selection/hover/command overlays
→ map objects and markers
→ map labels
→ atmospheric/post effects allowed by mode and settings
~~~

Each layer declares:

- Input authority.
- Resolution and colour space.
- Blend rule.
- Zoom range.
- Map modes in which it appears.
- Update trigger and invalidation cost.
- Low/medium/high quality behaviour.
- Accessibility alternative.
- CPU, GPU, and memory budget.

## Epic RP-1 — Render Architecture and Output Quality

### RP-1.1 Inventory the active render path — P1 / S

Record every shader, viewport, mesh, texture, compute step, material, and runtime update involved in the final map. Include import flags, filtering, mipmaps, compression, colour space, and generated asset hashes.

**Done when**

- One diagram traces source data to final pixel.
- Every map texture has a declared semantic, authority, size, format, and import policy.
- Duplicate or dead render paths are named for removal.

### RP-1.2 Lock pixel and world-coordinate authority — P1 / L

Map geometry, province data, label samples, markers, terrain, and borders must derive from the same authoritative transform. Eliminate duplicated constants such as map half-width and pixel scale from presentation systems.

**Done when**

- One `MapProjection`/transform authority defines map dimensions, pixel-to-world, world-to-pixel, wrap/seam policy, and height convention.
- Province anchors, borders, labels, armies, terrain samples, and mouse selection pass a transform agreement test.
- A source-resolution change fails validation rather than silently misaligning layers.

### RP-1.3 Choose anti-aliasing and sampling policy — P1 / M

**MV-0 decision:** Accepted and initially implemented. Use final-silhouette analytic AA from the canonical edge lattice for regional/close political borders, a country-distance fallback for distant minification, MSDF for map labels, exact nearest sampling for categorical/ID textures, linear mip sampling for continuous height and presentation art, and no default FXAA/TAA/global blur. Keep 3D MSAA disabled on the low-end default; measure an optional 2× object-quality tier later. See [MV-0 Rendering Architecture and Budgets](mv0/MV0_RENDERING_ARCHITECTURE_AND_BUDGET_DECISIONS.md).

Run a controlled spike comparing viable Forward+ options for borders, coastlines, text, and thin rivers. Consider camera jitter, MSAA, TAA, FXAA, texture supersampling, signed-distance borders, mip bias, and pixel alignment. Do not enable a global option without measuring text softness, motion shimmer, and GPU cost.

**Done when**

- A decision record includes still captures, motion captures, GPU cost, supported hardware impact, and selected fallback.
- Coast/border stair-stepping and camera shimmer meet the visual baseline.
- The selected solution does not make labels or terrain visibly blurry.

### RP-1.4 Define texture resolution tiers — P1 / M

**MV-0 decision:** Accepted for the vertical slice. Semantic authority stays at `5632×2048`; continuous macro height/terrain/water stays at `2816×1024`; geographic richness comes from tileable micro material/normal layers. Full-resolution macro art requires measured MV-3 benefit and budget approval.

Current province identity is `5632 × 2048`, while major terrain outputs are lower resolution. Establish intentional source, bake, and runtime tiers.

Example policy to validate:

| Asset class | Source expectation | Runtime tiers |
|---|---|---|
| Province/ownership IDs | Lossless authoritative full resolution | Full resolution only |
| Province edge lattice and strategic country distance field | Generated from authoritative IDs | Exact regional/close adjacency; minification-safe strategic fallback |
| Macro terrain/height/normal | Highest justified source | Low/medium/high variants |
| Micro terrain materials | Tileable | Shared across world, quality-dependent |
| Water normals/foam/noise | Tileable + coast masks | Shared variants |
| Label territory bake | Deterministic conservative ownership | Resolution chosen by fit error budget |

**Done when**

- Each tier has memory cost and visual-error measurements.
- Compression never corrupts ID/data textures.
- Low settings change fidelity, not ownership correctness.

### RP-1.5 Separate static and dynamic work — P1 / L

Static geography should not be regenerated for routine ownership or camera changes. Dynamic ownership and overlays should update only affected regions or compact lookup data.

**Done when**

- Update triggers are documented for province transfer, country formation/extinction, map-mode change, camera change, settings change, and load.
- Normal camera movement causes no country-colour or border recomputation.
- A mass peace transfer remains within the update budget without blocking input.

### RP-1.6 Choose coastline and province-edge fidelity strategy — P1 / L spike

Anti-aliasing cannot restore geographic detail that does not exist in the authoritative raster. Compare:

- Keeping the current province raster and rendering contours through a high-quality signed-distance/analytic edge.
- Re-authoring a higher-resolution province/coast source while preserving stable province IDs.
- Producing vector-like contours from validated raster topology for presentation only.
- A hybrid in which selection/ownership uses exact IDs while visual coast/borders use a smoothed topology-constrained contour.

**Constraints**

- Never interpolate or compress province IDs as ordinary colour art.
- Visual smoothing cannot move an edge far enough to make clicking select a different province than the visible one.
- Tiny islands, straits, holes, and one-pixel connections require topology fixtures.
- Any source-resolution/topology change needs save/content compatibility review.

**Done when**

- Close-zoom coastlines and province edges no longer show unacceptable pixel stair-steps.
- Visual and selection boundaries agree within an approved screen-pixel tolerance.
- Memory, bake time, update cost, and content-migration implications are recorded.

## Epic RP-2 — Political Palette and Ownership Semantics

### RP-2.1 Author a palette specification — P1 / M

**Implementation status:** Engineering and tools first pass live. Runtime HSV normalization narrows extreme saturation/value while preserving authored hue and neutral colours. The map settings expose Normal, Red-green safe, Blue-yellow safe, and High contrast profiles; the final political pass changes both palette opposition and the strength of non-colour patterns, while semantic accents are reserved per profile. Automated state propagation and rendered red-green-safe capture coverage are live. The deterministic [neighbour-colour production report](MV1_NEIGHBOUR_COLOUR_REPORT.md) checks all 1,542 starting country adjacencies in Oklab, ranks protanopia/deuteranopia/tritanopia simulation risks, records shared-border exposure, and generates advisory one-country-at-a-time candidates. Art approval, authored exceptions, dense-Europe captures, and hands-on review with affected players remain.

Build on the existing duplicate and neighbour-distance validation by adding art-direction ranges for luminance, chroma, and saturation. Reserve colours for selection, invalid actions, war states, overlays, and debug data.

**Done when**

- All active 1444 political colours have automated contrast/neighbour reports.
- Dense Europe and other likely-neighbour clusters receive manual review.
- No two adjacent countries are visually ambiguous in normal or supported colour-vision simulations.
- Political colour remains recognisable after terrain blending.

### RP-2.2 Define country versus realm grouping — P1 / M

**Implementation status:** First pass live. Legal owners retain distinct colours; active appanages/vassals receive presentation-only tint toward their ultimate overlord, a subtle subject cue texture, and lighter internal-realm edges. France's four 1444 appanages resolve to the French realm while Brittany and Provence do not. Ownership and save state remain unchanged.

Write the visual rules for sovereigns, subjects, personal unions, vassals, appanages, colonial nations, occupied territory, and temporary control.

Default recommendation:

- A legally distinct country keeps its own province colour and border.
- Subject relationship is communicated through border style, small heraldic/relationship cue, tooltip, and dedicated diplomatic/realm mode.
- An overlord-grouped mode may tint or pattern the realm, but must not rewrite province ownership.
- Country labels use owned/integrated label components, not every subject province, unless an explicit realm-label mode is active.

This directly covers cases such as Orléans: its provinces should remain visibly separate from France in the default political ownership view if it is a separate playable country in authoritative 1444 data.

**Done when**

- Design and historical content agree on the semantics.
- France/Orléans and at least five other relationship structures have approved captures.
- Save/load and relationship changes update the appropriate overlay without ownership corruption.

### RP-2.3 Define uncolonised, indigenous, wasteland, and impassable semantics — P1 / L

The current full-world catalogue and previous “fill every empty area” work can make the map visually over-fragmented. Decide which land is owned by a state, inhabited but not represented as a state, colonisable, impassable wasteland, or excluded from play.

**Done when**

- Each province has one validated political status separate from terrain type.
- Status changes are gameplay data, not inferred from colour.
- Uncolonised/wasteland fills are visually quiet and cannot be mistaken for normal countries.
- Historical 1444 setup review owns disputed/outlier decisions.

### RP-2.4 Tune political overlay blending — P1 / M

Replace one global strength with art-directed parameters by map mode, zoom band, and terrain context where justified. Avoid washing terrain out entirely or allowing terrain to destroy political readability.

**Done when**

- Political, terrain, war, relations, and province-ID modes have separate reviewed blend policies.
- Desert, forest, snow, mountain, and water-adjacent provinces meet readability targets.
- The selected country retains a stable identity without relying only on saturation.

## Epic RP-3 — Border Hierarchy

### RP-3.1 Generate semantic border classes — P1 / L

**Implementation status:** Engineering first pass live. The final-output pass classifies sovereign/realm-internal/ocean-coast/lake-shore/province edges from owner, terrain, lake-mask, and realm lookup data and styles them independently. Temporary control is supplied by a compact province-state lookup and receives an occupation outline/pattern. War goals retain the underlying side/control colour and receive a dedicated screen-stable double border. Command paths use a separate screen-stable outlined route layer with preview, active, retreat, and invalid-target shapes. River and invalid-terrain classes remain.

Country, subject, province, coast, lake, river, impassable, selected, occupied, and command-path edges should not compete through one generic black distance field.

**Done when**

- Border type is derived deterministically from province and relationship data.
- Border generation supports incremental ownership/relationship updates.
- Border classes can be styled independently without rebaking unrelated terrain.

### RP-3.2 Use zoom-aware screen-space line weights — P1 / L

**Implementation status:** Engineering first pass live. The former per-province interior SDF has been removed from the live province-border path. A full-resolution two-channel lattice stores each vertical and horizontal adjacency between texels exactly once. The final shader computes screen distance to those shared segments, classifies subject/sovereign/coast status from the two authoritative province IDs before dilation, and uses the old country SDF only as a wide-strategic minification fallback. Camera-normalized zoom controls sovereign, subject, coast, province, hover, selection, and occupation weights; province borders fade out toward the widest strategic band. Ordinary boundaries use an opaque solid core with a narrow anti-aliased outer transition, growing from `0.80 px` strategic weight to `1.45 px` close weight; hollow/double-ring treatment is reserved for the war-goal semantic. No erosion or blind topology cleanup is applied, preserving tiny provinces, islands, enclaves, and corridors. Forward+ capture, an exact lattice/ID contract test, and camera tests verify the live path. Final art approval and broader close-zoom topology fixtures remain.

Fixed world-space widths become too thick or too thin. Establish clamped screen-pixel targets per zoom band.

Provisional art targets to validate rather than blindly implement:

| Border | Strategic | Regional | Close |
|---|---:|---:|---:|
| Sovereign | 1.5–2.5 px | 2–3 px | 2–3 px |
| Subject/special | 1–2 px patterned/tinted | 1.5–2.5 px | 2–3 px |
| Province | Hidden–0.75 px | 0.75–1.25 px | 1–2 px |
| Selection/command | 2–3 px | 2–4 px | 3–5 px |

**Done when**

- Lines remain stable during continuous zoom.
- Wide view is not filled with province noise.
- Close view does not hide small provinces under outlines.

### RP-3.3 Replace neon coastline artefacts — P1 / M

**Implementation status:** First pass live. The cyan-biased ocean multiplier was removed and land-side coasts now use a restrained dark navy edge. Benchmark review at islands, straits, and pale terrain remains.

Separate coastline definition from water glow. If foam or shallow shelf exists, it uses a restrained independent mask and mode-aware intensity.

**Done when**

- Coast remains readable on both light and dark land.
- No one-pixel cyan fringe or oversized glow appears in benchmark captures.
- Islands keep their silhouette at supported zooms.

### RP-3.4 Add pattern and shape alternatives — P1 / M

**Implementation status:** Engineering first pass live. Occupied provinces combine a screen-stable outline with a restrained diagonal hatch, using distinct player-controlled, player-occupied, and third-party colours. Appanages use a dot cue, ordinary vassals a diagonal cue, and personal unions crosshatching in addition to their presentation tint. Route previews and retreats use distinct dashed rhythms while active movement is solid, all with a dark contrast outline. Invalid destinations use a geometric X and explanatory text rather than a colour-only failure cue. War goals use a double-ring shape and preserve occupation beneath them. The shader explicitly applies passive borders → occupation → war goal → hover → selection, and an automated dense-overlap fixture exercises all five levels on one province. Four player-selectable colour-vision/contrast profiles adjust palette and pattern strength. Hands-on colour-vision and moving-camera moiré review remain before art approval.

War, occupation, invalid terrain, subject grouping, and other semantic states cannot rely only on hue.

**Done when**

- Accessible hatch/pattern/icon alternatives exist.
- Pattern scale is screen-stable and does not moiré during camera motion.
- Dense overlaps have a documented priority rule.

## Epic RP-4 — Map Modes and Overlays

### RP-4.1 Create a declarative map-mode definition — P1 / L

Each mode should define:

- Base terrain/water contribution.
- Province fill source and legend.
- Border styles.
- Label policy.
- Marker policy.
- Tooltip/selection behaviour.
- Accessible palette/pattern.
- Required data and invalidation signal.

**Done when**

- Adding a data mode does not require scattered visibility checks across unrelated scripts.
- Mode switch is deterministic and captures the same result after save/load.
- Debug mode can disable labels, objects, relief, and post effects completely.

### RP-4.2 Make overlay composition explicit — P1 / L

Selection, hover, occupation, war, relation, access, route, movement, and invalid-action feedback need a single precedence table.

Recommended precedence:

1. Invalid/blocked immediate command feedback.
2. Hover/selection and command destination.
3. Battle/siege/occupation/war goal.
4. Active map-mode semantic fill.
5. Political ownership.
6. Terrain/environment.

**Done when**

- No overlay silently erases a more important state.
- Each combined-state regression case has a reviewed screenshot.
- Animation honours pause/reduced-motion and does not affect simulation determinism.

### RP-4.3 Eliminate normal-play placeholders — P1 / M

Audit coloured squares, debug circles, temporary lines, and internal IDs. Replace gameplay-relevant items with approved markers; hide development-only elements behind a debug flag.

**Done when**

- Normal packaged builds contain no unexplained placeholder marker.
- QA can still enable diagnostics in a controlled development build.

## Epic RP-5 — Shader and Material Quality Levels

Define Low, Medium, High, and optionally Ultra only if each tier has a meaningful tested difference.

| Feature | Low | Medium | High |
|---|---|---|---|
| Terrain macro | Required | Required | Required |
| Normal/micro detail | Reduced/shared | Standard | Higher fidelity |
| Water motion | Single low-cost layer | Multi-layer | Enhanced if budget permits |
| Coast foam/shelf | Simplified | Standard | Standard/enhanced |
| Shadows/reflections | Off or minimal | Selective | Approved enhanced path |
| Vegetation/objects | Aggressive cull | Standard | Increased density within cap |
| Post effects | Minimal | Approved default | Approved enhanced |

**Done when**

- Every tier preserves ownership, borders, selection, labels, and rivers.
- Settings can change safely at runtime or clearly require reload.
- Tier switching does not leave stale resources or unbounded memory.

## Verification Matrix

At minimum, capture every major change in:

- Political, terrain, war, relations, and debug/ID modes.
- Strategic, regional, and close zoom.
- France/Low Countries, Italy, Scandinavia, Sahara/Nile, maritime Southeast Asia, Andes, and North American interior.
- Normal, selected, hover, occupied, subject, and invalid-target states.
- 1920×1080 plus minimum supported resolution, ultrawide, and high-DPI/UI-scale configurations.
- Default and colour-blind-safe presentation.

## Exit Criteria

- The renderer has one documented layer contract and coordinate authority.
- Political ownership remains accurate after every authoritative state transition.
- Country, province, coast, and interaction edges have stable hierarchy at all supported zooms.
- The default palette is cohesive, neighbour-readable, and accessibility-tested.
- Map modes own complete visual policies.
- Output is sharp in stills and stable in motion.
- The full layer stack meets the budgets in [07 — Performance, QA, and Release Gates](07_PERFORMANCE_QA_RELEASE_GATES.md).
