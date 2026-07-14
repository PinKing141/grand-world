# MV-0 Current Baseline Review

## Capture Contract

The current-state capture job:

- Uses Godot 4.7 Forward+ through the console executable.
- Instantiates `scenes/main.tscn`.
- Hides HUD controls so review concerns the map, not menu/UI skin.
- Keeps country labels and world-space gameplay markers because they are part of map presentation.
- Uses fixed region, resolution, mode, and target camera-height definitions.
- Records runtime/hardware metrics in `mv0_capture_manifest.json`.

Baseline directory: `tests/baselines/map_visual_mv0/current/`.

## Captured Views

| Benchmark | Evidence | Primary review purpose |
|---|---|---|
| Strategic maximum zoom | [current wide political](../../../../tests/baselines/map_visual_mv0/current/current_world_political_1920x1080.png) | Global density, labels, political hierarchy, camera framing |
| France/Low Countries political | [political capture](../../../../tests/baselines/map_visual_mv0/current/current_france_low_countries_political_1920x1080.png) | Dense borders, France/subjects, labels, marker clutter |
| France/Low Countries terrain | [terrain capture](../../../../tests/baselines/map_visual_mv0/current/current_france_low_countries_terrain_1920x1080.png) | Terrain-only material and policy leakage |
| France/Low Countries IDs | [ID capture](../../../../tests/baselines/map_visual_mv0/current/current_france_low_countries_ids_1920x1080.png) | Debug-mode exactness and presentation suppression |
| Italy/Alps political | [Italy capture](../../../../tests/baselines/map_visual_mv0/current/current_italy_alps_political_1152x648.png) | Diagonal realms, relief, microstates, label density |
| Scandinavia/Baltic terrain | [Scandinavia capture](../../../../tests/baselines/map_visual_mv0/current/current_scandinavia_baltic_terrain_1152x648.png) | Long realms, islands/straits, snow/forest, water |
| Sahara/Nile terrain | [Sahara/Nile capture](../../../../tests/baselines/map_visual_mv0/current/current_sahara_nile_terrain_1700x960.png) | Desert transition, wasteland, missing river hierarchy |
| Maritime Southeast Asia political | [Southeast Asia capture](../../../../tests/baselines/map_visual_mv0/current/current_maritime_southeast_asia_political_1152x648.png) | Fragmented realms, coast density, water |
| Andes terrain | [Andes capture](../../../../tests/baselines/map_visual_mv0/current/current_andes_terrain_1152x648.png) | Long mountain relief and biome variation |
| North America political | [North America capture](../../../../tests/baselines/map_visual_mv0/current/current_north_america_political_1152x648.png) | Political-status fragmentation and low-density space |

## P0 Findings

No missing land/water layer or capture/export failure occurred during this baseline run. No P0 was opened.

## P1 Visual Findings

### BL-01 — Political hierarchy is too heavy and dark

- Country borders appear as thick black sticker outlines.
- Country fills often use very dark values or strong saturation.
- Terrain emboss/noise inside political fills adds value variation without enough material coherence.
- Province/country/coast distinctions depend heavily on black and blue lines rather than a controlled hierarchy.

**Roadmap owner:** RP-2 and RP-3.  
**Acceptance evidence:** France, Italy, strategic-wide, and Sahara political comparisons.

### BL-02 — Coastline reads as a bright blue fringe

- Land/water separation is frequently a saturated blue/cyan halo.
- Pixel stair-stepping is obvious at close/regional zoom.
- The same treatment competes with political and province borders.

**Roadmap owner:** RP-1.3, RP-1.6, RP-3.3, TW-4.  
**Acceptance evidence:** moving coast capture plus small-island selection agreement.

### BL-03 — Terrain mode is not a clean geographic presentation

- Broad terrain colour is soft and low-frequency, with limited material differentiation.
- Rivers are absent, including the Nile in the Sahara/Nile benchmark.
- Terrain mode retains country labels and many political/army marker rectangles.
- Labels frequently have weak contrast against dark terrain.

**Roadmap owner:** TW-1–TW-4, RP-4.1, CL-5.1, MO-1.  
**Acceptance evidence:** Sahara/Nile, Alps, Scandinavia, and Andes terrain targets.

### BL-04 — Normal-play markers are obvious placeholders

- Dense Europe is covered by small solid-colour rectangles.
- Marker colour competes with country colour and has no consistent silhouette/state grammar.
- Marker density dominates close views and can obscure labels.

**Roadmap owner:** RP-4.3, MO-1, MO-3, MO-4.  
**Acceptance evidence:** France/Low Countries and major-war presentation slice.

### BL-05 — France label/realm footprint is misleading

- The France benchmark places the France name across a differently coloured internal country/appanage area.
- This visually implies political ownership that the fill does not show.
- The issue matches the open disconnected/subject-component rule rather than a font-size-only problem.

**Roadmap owner:** RP-2.2, CL-3.1, CL-3.2.  
**Acceptance evidence:** France/Orléans capture with authoritative ownership overlay and reviewed subject policy.

### BL-06 — Label sharpness and contrast are inconsistent

- Thin dark letter strokes blur into dark country/terrain fills.
- Rotated labels can be difficult to scan while zoomed out.
- Some labels are too small while others become disproportionately large.
- Terrain mode does not provide a separate label contrast policy.

**Roadmap owner:** CL-4 and CL-5.  
**Acceptance evidence:** final render-method still/motion comparison at all supported sizes.

### BL-07 — Strategic framing does not cleanly present the entire world

- The maximum-height capture exposes a large empty area beyond the map edge because of the fixed camera pitch.
- Parts of the world remain cropped at the same time.
- Camera pitch/height and map bounds are not yet an art-directed strategic framing policy.

**Roadmap owner:** Art Bible camera direction, MO-4.1, RP-1.2.  
**Acceptance evidence:** approved Home/reset and strategic-world bookmarks at supported aspect ratios.

### BL-08 — Hidden checksum refresh caused catastrophic periodic stalls — fixed during MV-0

The corrected initial capture found four roughly periodic `669–734 ms` stalls. Layer isolation proved:

- Stalls persisted with labels, armies, camera motion, and simulation processing disabled individually.
- Stalls disappeared when HUD processing was disabled.
- `SimulationHUD` alone reproduced them; every other HUD alone stayed below `27.1 ms` maximum.
- The cause was a hidden developer debug panel calling the full global `world_checksum()` every second even when not visible.

The HUD now computes a checksum only when F10 explicitly opens the debug panel and reuses the checksum already produced by a world-reload event. The post-fix current capture measured:

- `21.340 ms` P50, `24.236 ms` P95, `25.178 ms` P99, and `26.348 ms` maximum over 180 scripted motion frames.
- Zero frames over `33.3 ms`, `50 ms`, or `100 ms`.
- FPS monitor P50 `47` and P05 `41`.

**Status:** Periodic P1 freeze resolved. The remaining steady 60 FPS gap belongs primarily to the country-label render path.

### BL-09 — Country labels dominate dense-view draw and frame cost

The post-fix layer probe measured:

| Profile | P50 | P95 | Maximum | P95 draw calls |
|---|---:|---:|---:|---:|
| All map layers moving | `23.349 ms` | `29.907 ms` | `38.979 ms` | `206` |
| Country labels disabled | `13.327 ms` | `14.783 ms` | `16.412 ms` | `2` |
| Base map moving | `13.302 ms` | `14.391 ms` | `15.053 ms` | `1` |

The current `Label3D` representation therefore contributes approximately 204 draw calls in the benchmark view and keeps the full presentation below the 60 FPS target even after the checksum stall fix.

**Roadmap owner:** CL-4.1 final label-render-method spike.  
**Acceptance evidence:** Same view with approved typography, ≤ map presentation budget, no loss of full-name/readability/collision behaviour.

**Roadmap owner:** MV0-02, TD-013, QA benchmark B02/B10.  
**Acceptance evidence:** corrected wall-clock profile plus external GPU capture.

## P2 Visual Findings

- Water is very dark/static and lacks a controlled coast/depth/material hierarchy.
- No normal, river, vegetation, seasonal, coast-mask, or roughness/material map was found.
- Terrain/height/water are half the linear resolution of province authority.
- Wasteland and uncolonised regions need stronger political semantics before palette polish.
- The strategic view contains strong global colour fragmentation.

## Positive Baseline Capabilities

- Land/water and political ownership render globally.
- Terrain classification and relief exist across owned/unowned/impassable land.
- Country labels use full names, shape alignment, collision, culling, and incremental lifecycle.
- Political, terrain, and province-ID modes switch successfully.
- Map-only captures are reproducible across named benchmark views.
- Prebaked map textures avoid known compute-import instability in normal production.

## Captured Resource Baseline

| Metric | Captured range/value |
|---|---:|
| Video memory monitor | Approximately `543–590 MB` |
| Texture memory monitor | Approximately `330–357 MB` |
| Buffer memory monitor | Approximately `18.8–33.7 MB` |
| Label layouts | `703` full-name layouts |
| Territory-fitted labels | `581` |
| Shape-aligned labels | `546` |
| Close-zoom screen fallbacks | `122` |
| Current profile visible label nodes | `39` |
| Label initial layout CPU | `544.886 ms` distributed in batches |
| Label initial wall completion | `5270.838 ms` on this capture run |

Godot monitor memory values include renderer allocations outside the named map textures. They are a repeatable baseline, not a per-layer VRAM breakdown; TD-013 requires the external capture.

## Review Sign-off Still Required

- Art Direction assessment of hierarchy and target deltas.
- UX assessment of two-second ownership comprehension and label readability.
- Historical/Content confirmation of the France/Orléans subject example and political-status semantics.
- Rendering/QA external GPU pass capture, concentrating on the country-label draw passes and total map GPU cost.
