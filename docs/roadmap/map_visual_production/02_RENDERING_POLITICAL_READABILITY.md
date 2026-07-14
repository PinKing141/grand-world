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
- Current captures show dark/saturated fills, heavy borders, bright coast edges, pixel stair-stepping, and placeholder marker shapes.

Before implementation, MV-0 must confirm these observations with a GPU frame capture and import-setting inventory.

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

Run a controlled spike comparing viable Forward+ options for borders, coastlines, text, and thin rivers. Consider camera jitter, MSAA, TAA, FXAA, texture supersampling, signed-distance borders, mip bias, and pixel alignment. Do not enable a global option without measuring text softness, motion shimmer, and GPU cost.

**Done when**

- A decision record includes still captures, motion captures, GPU cost, supported hardware impact, and selected fallback.
- Coast/border stair-stepping and camera shimmer meet the visual baseline.
- The selected solution does not make labels or terrain visibly blurry.

### RP-1.4 Define texture resolution tiers — P1 / M

Current province identity is `5632 × 2048`, while major terrain outputs are lower resolution. Establish intentional source, bake, and runtime tiers.

Example policy to validate:

| Asset class | Source expectation | Runtime tiers |
|---|---|---|
| Province/ownership IDs | Lossless authoritative full resolution | Full resolution only |
| Coast/country/province distance fields | Generated from authoritative IDs | Quality-dependent but alignment-validated |
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

Build on the existing duplicate and neighbour-distance validation by adding art-direction ranges for luminance, chroma, and saturation. Reserve colours for selection, invalid actions, war states, overlays, and debug data.

**Done when**

- All active 1444 political colours have automated contrast/neighbour reports.
- Dense Europe and other likely-neighbour clusters receive manual review.
- No two adjacent countries are visually ambiguous in normal or supported colour-vision simulations.
- Political colour remains recognisable after terrain blending.

### RP-2.2 Define country versus realm grouping — P1 / M

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

Country, subject, province, coast, lake, river, impassable, selected, occupied, and command-path edges should not compete through one generic black distance field.

**Done when**

- Border type is derived deterministically from province and relationship data.
- Border generation supports incremental ownership/relationship updates.
- Border classes can be styled independently without rebaking unrelated terrain.

### RP-3.2 Use zoom-aware screen-space line weights — P1 / L

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

Separate coastline definition from water glow. If foam or shallow shelf exists, it uses a restrained independent mask and mode-aware intensity.

**Done when**

- Coast remains readable on both light and dark land.
- No one-pixel cyan fringe or oversized glow appears in benchmark captures.
- Islands keep their silhouette at supported zooms.

### RP-3.4 Add pattern and shape alternatives — P1 / M

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
