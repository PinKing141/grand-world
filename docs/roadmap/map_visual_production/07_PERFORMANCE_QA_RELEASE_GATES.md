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

MV-0 approved two production tiers. The development-minimum target is 1280×720 low at 30 FPS on the Radeon 610M/Ryzen 3 7320U-class machine; the recommended validation target is 1920×1080 medium at 60 FPS on a Forward+-capable GPU with at least 4 GiB graphics memory. Phase 9 must validate real machines before publishing commercial specifications. Full tier details are in [MV-0 Rendering Architecture and Budgets](mv0/MV0_RENDERING_ARCHITECTURE_AND_BUDGET_DECISIONS.md).

### Steady presentation at 1920×1080 / 60 FPS

| Budget | Reference target |
|---|---:|
| Total frame | ≤ 16.67 ms at P95 |
| Complete map GPU contribution | ≤ 6.0 ms at P95 on reference GPU |
| Map presentation CPU contribution | ≤ 2.0 ms at P95 during normal camera motion |
| UI contribution during map interaction | ≤ 2.0 ms at P95 |
| Simulation + AI | Uses its own phase budgets and cannot be hidden by paused-only captures |
| Normal-play hitch | No recurring frame > 50 ms |
| Country label render cost | ≤ 2.0 ms at P95; ≤ 4 steady draw submissions |

The total sub-budgets intentionally leave headroom for simulation, UI, OS/driver variance, audio, and future effects.

### Current measured implementation — 14 July 2026

On the Radeon 610M development machine at 1920×1080, the batched-label orthographic pass measured `13.270 ms` P50 and `14.716 ms` P95 during all-layer camera motion, with `25.106 ms` maximum and no frame above 50 ms. The no-label comparison measured `14.623 ms` P95. Country labels used three MSDF atlas-page batches and no `Label3D` nodes in the focused regression test. This passes the provisional ordinary-motion P95 gate on this machine; it does not replace external GPU pass analysis or multi-machine release validation.

After moving the full border hierarchy to the final screen shader on 15 July 2026, the same 1920×1080 all-layer motion probe measured `13.408 ms` P50, `15.358 ms` P95, `27.993 ms` maximum, and zero frames above 50 ms. The dynamic border/control pass therefore remains inside the provisional `16.67 ms` P95 gate, with approximately `1.31 ms` of measured P95 headroom on this machine. External GPU attribution and broader hardware validation are still required.

After adding canonical lake classification/shore treatment, semantic command paths, invalid-destination shape feedback, corrected transparent MSDF labels, subject pattern classes, and the war-goal double border on 15 July 2026, the final all-layer rerun measured `13.352 ms` P50, `15.391 ms` P95, `23.770 ms` maximum, and zero frames above 50 ms. The implementation remains inside the provisional gate with approximately `1.28 ms` P95 headroom. That margin is still narrow: external GPU attribution and lower/higher-spec hardware coverage remain mandatory before approval.

After adding the four accessibility profiles, deterministic dense-overlay fixture, world-seam route splitting, batched battle/siege marker layer, and canonical shared province-edge lattice on 15 July 2026, the optimized isolated 1920×1080 all-layer motion probe measured `13.266 ms` P50, `15.748 ms` P95, `26.185 ms` maximum, and zero frames above 50 ms. Ordinary movement remains inside the `16.67 ms` P95 gate with approximately `0.92 ms` headroom on the Radeon 610M development machine. Exact regional classification skips the redundant strategic SDF path at full weight. A separate deterministic extreme-war gate now creates 120 active wars and 720 logical battle/siege records, validates compression to 42 visible clusters on the reference camera, holds conflict rendering to two draw batches, and applies a provisional `66.67 ms` P95 ceiling to the event/zoom-driven full rebuild path. The ordinary movement margin remains narrow; external GPU attribution, real save-derived war captures, incremental conflict updates, and broader hardware validation remain open.

After replacing the temporary army bars with atlas-backed country shields and the battle/siege bars with the project-original cartographic icon atlas on 15 July 2026, the same 1920×1080 all-layer motion probe measured `13.307 ms` P50, `15.796 ms` P95, `26.258 ms` maximum, six draw calls at P95, and zero frames above 33.3 ms. This is only `0.048 ms` above the preceding P95 capture and remains inside the `16.67 ms` gate with approximately `0.87 ms` headroom. The no-army comparison measured `15.702 ms` P95, but the difference is too small relative to run-to-run timing noise to attribute as a precise marker cost. The result validates the batched atlas architecture on the Radeon 610M reference machine; it does not replace external GPU profiling or broader hardware certification.

After upgrading every country shield from a 64×64 cell to a supersampled 128×128 cell, increasing its readable screen footprint, and adding half-texel atlas clamping on 15 July 2026, the 1920×1080 all-layer motion probe measured `13.221 ms` P50, `14.999 ms` P95, `23.657 ms` maximum, six draw calls at P95, and zero frames above 33.3 ms. The 4096×4096 RGBA atlas has an approximately 64 MiB uncompressed GPU footprint, versus approximately 16 MiB for the earlier 2048×2048 atlas. The timing improvement relative to the preceding capture is treated as run-to-run variance, not as an optimization claim; the meaningful result is that higher-resolution markers remain within the `16.67 ms` P95 gate on the Radeon 610M reference machine.

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

MV-0 sets a total graphics-allocation ceiling of 1.25 GiB for the development-minimum tier and 3 GiB for the recommended tier. Map textures are limited to 512 MiB and 1 GiB respectively. In addition:

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

**Engineering status (15 July 2026):** The runtime map settings expose four persisted presentation profiles: Normal, Red-green safe, Blue-yellow safe, and High contrast. Automated tests verify settings-to-shader propagation, and the map uses hatch, line rhythm, double borders, and marker silhouettes so key states are not hue-only. This is implementation evidence, not final accessibility certification; simulation review and hands-on testing with affected players remain required.

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
