# 07 — Performance, QA, and Release Gates

## Purpose

Make visual quality measurable. The map is the most persistent screen in the game, so average beauty is not enough: it must remain responsive during camera motion, map-mode changes, wars, ownership transfers, long campaigns, exports, and supported hardware/settings.

These gates extend [Quality, Performance, and Release Gates](../QA_PERFORMANCE_RELEASE_GATES.md). The project-wide target remains 1920×1080 at 60 FPS with 16.67 ms frame time and no recurring normal-play hitch above 50 ms.

## Reference Hardware Policy

MV-0 must define:

- Minimum-spec CPU/GPU/RAM/storage and supported Windows version.
- Recommended/reference CPU/GPU/RAM/storage.
- Driver versions and graphics API.
- Godot version and render method.
- Target resolutions, high-DPI policy, and graphics tiers.
- Capture tool and repeatable benchmark procedure.

Performance numbers without build ID, scene, camera bookmark, settings, hardware, driver, and capture duration are observations, not accepted evidence.

## Provisional Map Budgets

These budgets are starting targets and must be revised from MV-0 captures. Tightening requires evidence; loosening requires an approved trade-off.

### Steady presentation at 1920×1080 / 60 FPS

| Budget | Reference target |
|---|---:|
| Total frame | ≤ 16.67 ms at P95 |
| Complete map GPU contribution | ≤ 6.0 ms at P95 on reference GPU |
| Map presentation CPU contribution | ≤ 2.0 ms at P95 during normal camera motion |
| UI contribution during map interaction | ≤ 2.0 ms at P95 |
| Simulation + AI | Uses its own phase budgets and cannot be hidden by paused-only captures |
| Normal-play hitch | No recurring frame > 50 ms |

The total sub-budgets intentionally leave headroom for simulation, UI, OS/driver variance, audio, and future effects.

### Dynamic update budgets

| Event | Provisional target |
|---|---:|
| Hover/selection response | Visible response < 100 ms; prefer next rendered frame |
| Map-mode switch | First correct response < 100 ms; expensive refinement may stream without blocking input |
| Routine province ownership transfer | No frame > 33.3 ms attributable to map update |
| Large peace/mass occupation update | Budgeted across frames; no recurring > 50 ms hitch |
| Label incremental rebuild | Preserve current sub-frame batching and measured regression thresholds |
| Graphics/label setting change | No stale layer; apply safely or clearly request reload |

### Memory/load budgets

Set exact limits after asset-tier decisions. Until then:

- Track dedicated texture memory by semantic layer and quality tier.
- No unbounded node, glyph, material, render-target, or generated-texture growth during a 100-year soak.
- Avoid holding source, high, medium, and low copies in memory simultaneously without a documented streaming reason.
- Clean packaged startup must report missing assets as a blocking failure, not silently render a fallback void.

## Benchmark Scenes

Every performance and visual milestone uses fixed bookmarks:

| ID | Region/view | Stress purpose |
|---|---|---|
| B01 | Whole world, strategic zoom | Global labels, country fill, culling, water, memory |
| B02 | France/Low Countries, regional | Dense provinces, subjects, borders, labels, markers |
| B03 | Italy/Alps, close/regional | Relief, microstates, dense borders, diagonal labels |
| B04 | Scandinavia/Baltic | Islands, straits, snow/forest, long labels, water |
| B05 | Sahara/Sahel/Nile | Desert transition, wasteland, major river, sparse labels |
| B06 | Maritime Southeast Asia | Coast/island density, fragmented labels, water GPU load |
| B07 | Andes | Long mountain relief, climate/material variation |
| B08 | Major European war | Armies, routes, battles, occupation, overlay composition |
| B09 | Large peace transfer | Dynamic colour/border/label invalidation |
| B10 | Dense UI + map drag | Panel movement, tooltips, map input, UI/map compositing |

For each bookmark capture political, terrain, war or relevant data mode at required zoom bands and quality tiers.

## Visual Test Pyramid

### Level 1 — Data and math tests

- Map transform round trip.
- Province/terrain/label alignment.
- Border classification.
- Colour distance and palette reservation.
- River graph and coast/lake continuity.
- Label component selection and bounds.
- LOD thresholds/hysteresis.
- Marker clustering.
- Localisation and fallback rules.

### Level 2 — Synthetic render fixtures

Small deterministic maps covering:

- Adjacent colour edge.
- Coast, lake, island, strait, and world seam.
- Concave and disconnected realm.
- Long and microstate label.
- Overlapping borders/occupation/selection.
- Terrain extremes and river mouth.
- Marker/label collision.

These catch exact layer errors faster than full-world screenshots.

### Level 3 — Golden benchmark captures

GPU-rendered PNG comparisons at fixed bookmark, build settings, resolution, graphics tier, mode, date, seed, and state.

Use perceptual comparison with:

- Exact masks for ownership/ID-critical pixels where appropriate.
- Tolerances for approved animated/noisy layers.
- Region-of-interest reporting.
- Difference image and changed-pixel metrics.
- Manual approval for intentional golden updates.

### Level 4 — Interaction tests

- Pan, WASD/arrows, zoom, drag threshold, click selection, marker selection.
- Map-mode change and label toggle.
- Hover/selection while time advances.
- Ownership transfer, formation, annexation, release, colonisation, occupation, and peace.
- UI panel drag/resize/focus while map animates.
- Resolution, window/fullscreen, UI scale, and DPI change.

### Level 5 — Packaged-build exploratory review

Human review in a real exported build checks motion, hierarchy, comprehension, fatigue, discoverability, and defects that image comparison cannot judge.

## Readability Gates

### Two-second political test

In a new view, a reviewer should identify:

- Selected country and province.
- Sovereign country boundaries.
- Province subdivision at regional/close zoom.
- Subject/appanage distinction where the mode presents it.
- Water, uncolonised land, and wasteland.

Record failures by root cause: palette, border, label, overlay, terrain contrast, marker clutter, or incorrect data.

### Label readability test

- No internal tag replaces a country name.
- Target text remains sharp at supported resolutions and normal viewing distance.
- Label contrast passes the approved map-text standard across terrain/modes.
- Country names do not visually claim unowned/subject territory outside approved realm rules.
- Dense-region collision and priority are acceptable in motion.
- Full-name microstate treatment is discoverable at the intended zoom.

### Motion readability test

Capture slow/fast pan and continuous zoom. Review for:

- Border shimmer.
- Texture crawling/moiré.
- Label blur or unstable snapping.
- LOD popping/flicker.
- Water/foam distraction.
- Marker clustering thrash.
- frame-time spikes correlated with layer changes.

## Accessibility Matrix

Test at minimum:

- Default colour vision.
- Protanopia, deuteranopia, and tritanopia simulations.
- High-contrast borders/labels.
- Reduced motion.
- Low map-detail/clutter setting.
- Minimum and maximum supported label/UI scale.
- Keyboard-accessible alternatives for locating essential map entities.

No essential state may rely on hue alone. Use line style, pattern, icon, shape, text, or state-specific marker support.

## Compatibility Matrix

Before Visual Beta, lock:

- Supported Windows versions.
- Minimum/recommended GPU and driver families.
- Required Vulkan/graphics API features.
- Forward+ policy and any fallback renderer limitations.
- 16:9, ultrawide, minimum supported window, fullscreen, high DPI, and multi-monitor policy.
- Low/medium/high settings and their memory footprint.
- Export template, addon, and shader compilation validation.

## Profiling Procedure

For each milestone build:

1. Use a clean launch and fixed build ID.
2. Warm shader/import caches according to the documented cold/warm test distinction.
3. Run each bookmark for a fixed duration and command stream.
4. Capture CPU main/render threads, GPU passes, draw calls, primitives, texture/render-target memory, node counts, and frame percentiles.
5. Run with simulation paused and advancing to separate presentation from simulation cost.
6. Compare against the previous approved build and budget.
7. Store captures and a short interpretation report.

Track P50, P95, P99, worst recurring event, and one-off transition separately. A good average does not excuse repeated interaction hitches.

## Long-Session and State-Change Tests

Required profiles:

- Ten minutes of continuous pan/zoom/mode switching.
- Repeated open/close/drag of all map-related panels.
- Repeated language and label-setting changes where supported.
- Repeated formation/release/annexation/peace fixture.
- Fifty-year and 1444–1700 AI soaks with periodic screenshots and memory samples.
- Save/load cycle during a large war and after global ownership changes.
- Graphics-tier cycling if runtime switching is supported.

Failure indicators:

- Growing label/marker/object counts without corresponding world state.
- Increasing texture/render-target memory.
- Stale country colours or borders.
- Labels for extinct countries.
- Disappearing terrain/water after load.
- Shader compilation stalls during ordinary play.
- Frame-time degradation correlated with campaign age.

## Headless and Rendered Test Policy

Use separate jobs:

### Logic-headless

- Data validation.
- Simulation and save/load.
- Label layout math.
- Bake reproducibility.
- Export package contents/startup where supported.

### GPU-rendered

- Shader/material correctness.
- Visual regression screenshots.
- Anti-aliasing and text sharpness.
- GPU performance and memory.
- Driver/quality-tier compatibility.

Do not treat Godot's dummy headless renderer as proof of shipping visual output. The previously observed dummy-renderer null-texture crash must be reported as an environment/render-driver failure unless reproduced in the supported rendered path. Windows Application Control failures for newly generated unsigned temporary executables remain separate from package validity; the documented trusted-host PCK fallback may test the package, but release testing still requires a normally runnable distributable on an approved machine.

## Defect Severity for Map Visuals

| Severity | Examples |
|---|---|
| P0 Blocker | Land/water missing; ownership corrupt; map cannot render; export missing core map asset; catastrophic GPU crash |
| P1 Critical | Wrong country colour/label; unusable camera hitch; unreadable borders; recurring supported-driver failure; raw tags shown widely |
| P2 Major | Significant regional terrain/river error; mode-specific label failure; marker overlap with workaround |
| P3 Minor | Local texture seam at rare zoom; small label offset; polish inconsistency |
| P4 Trivial | Negligible decorative mismatch with no readability impact |

## Milestone Gates

### Visual Greenlight

- Baseline captures and target mock-ups approved.
- Reference hardware and budgets documented.
- Rendering, label, terrain, and asset decisions have owners.

### Political Vertical Slice

- Benchmark political scenes pass visual and interaction review.
- Ownership/state transitions are correct.
- Provisional budgets pass with headroom.

### Environment Gate

- Representative terrain/water regions pass.
- Political readability is preserved.
- Pipeline can produce a new region without architecture changes.

### Presentation Alpha

- All required map layers and objects exist.
- Open P1 defects have owners and approved close plans.
- Automated global run reaches 1700 without presentation corruption.

### Visual Content Complete

- All planned regions/content are present and reviewed.
- No missing required label, river, terrain class, ownership semantic, or normal-play marker.
- Source/provenance and validation reports pass.

### Visual Beta

- Feature lock active.
- Zero P0; P1 trends to zero and no unowned critical issue.
- Reference hardware/settings matrix passes.
- Visual baselines are locked except approved bug/accessibility/localisation updates.

### Visual Release Candidate

- Zero P0 and zero unmitigated P1.
- Packaged build passes clean install, new campaign, save/load, and long soak.
- Asset provenance/legal review passes.
- Release capture and performance archive is complete.
- Known visual issues and fallbacks are documented.

