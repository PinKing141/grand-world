# MV-0 Technical Decisions and Spike Queue

## Status Vocabulary

- **Accepted:** The project can build against this decision; changing it requires a new decision record.
- **Proposed:** Recommended direction requiring named approval/evidence.
- **Spike required:** No implementation choice is authorised until alternatives are measured.
- **Deferred:** Not required for the current gate, with a working fallback.

## TD-001 — Primary Rendering Method

**Status:** Accepted for the current project baseline.

Use Godot 4.7 Forward+ as the primary renderer. The current map uses compute/prebaked GPU textures and a spatial map material that are not supported by the Compatibility renderer in the established project setup.

**Consequences**

- GPU visual tests must run with a normal Forward+ rendering window.
- Logic-headless tests remain separate.
- Phase 9 must either declare Forward+ minimum requirements or fund a separately validated fallback.

**Revisit when:** Supported hardware requirements cannot meet the Forward+ path.

## TD-002 — One World Mesh During the Readability Slice

**Status:** Proposed.

Keep the current one-world-mesh architecture through MV-1/MV-2 while separating layer responsibilities and measuring memory. Do not combine a visual redesign with a premature tiling/streaming rewrite.

**Revisit trigger**

- High-quality texture tiers exceed the approved memory/load budget.
- Regional updates require unacceptable full-world work.
- Precision, culling, or seam defects cannot be solved cleanly.

## TD-003 — Authoritative IDs Versus Smoothed Presentation

**Status:** Proposed.

Province IDs remain exact lossless data. Presentation borders/coasts may use topology-constrained distance fields or smoothed contours only if selection and visible edges agree within an approved screen-pixel tolerance.

Never filter, compress, or mip categorical province/class data as normal colour artwork without explicit proof that semantics remain exact.

## TD-004 — Political Country/Subject Semantics

**Status:** Engineering accepted and scenario data implemented; final Design/Historical presentation approval required.

Default political mode shows the country that legally owns each province. Subjects/appanages such as Orléans keep their own colour and border. Relationship is expressed through a subject border/cue or dedicated realm/diplomatic presentation. Overlord realm grouping never rewrites authoritative ownership.

Country labels fit approved owned/integrated components, not every subject province.

The 1444 scenario initializes Auvergne, Bourbonnais, Foix, and Orléans as French appanages while retaining their legal province ownership. Brittany and Provence are not included. See [MV-0 Scale, Projection, and Realm Audit](MV0_SCALE_PROJECTION_REALM_AUDIT.md).

## TD-005 — Render-Layer Contract

**Status:** Proposed.

~~~text
authoritative land/water and map transform
→ terrain macro + relief/material
→ water/coast/river
→ political/data fill
→ semantic borders
→ war/occupation/control
→ hover/selection/command
→ map objects
→ labels
→ optional atmosphere/post
~~~

Every layer declares data source, blend, zoom/mode policy, invalidation, quality fallback, accessibility, and budget.

## TD-006 — Anti-Aliasing and Sampling

**Status:** Accepted and initially implemented.

Use analytic derivative-aware smoothing for political distance-field borders, MSDF for labels, exact nearest sampling for ID/categorical textures, and linear mip sampling for continuous height/presentation textures. Disable default FXAA, TAA, and 3D MSAA on the low-end tier. A future measured 2× MSAA option may target geometry/map objects; it does not replace analytic shader-edge AA. See [MV-0 Rendering Architecture and Budgets](MV0_RENDERING_ARCHITECTURE_AND_BUDGET_DECISIONS.md).

## TD-007 — Label Rendering Architecture

**Status:** Architecture accepted; production migration is MV-1/MV-4 P1.

Use batched screen-space MSDF atlas text, anchored by the existing deterministic world-space territory layouts. Preserve full-name, safe-fit, collision, lifecycle, performance, and export gates. The current per-country Label3D implementation is an MSDF fallback only and is rejected as the final path because dense regional views produce hundreds of draw submissions.

## TD-008 — Height and Categorical Texture Imports

**Status:** Accepted and implemented for the vertical slice.

`terrain_class_map.png` and `biome_map.png` now use lossless unmipped categorical imports. `heightmap.png` uses lossless import with mipmaps because it is continuous displacement data. Province IDs and every derived semantic lookup remain exact and nearest sampled.

## TD-009 — Terrain/Water Resolution Tier

**Status:** Accepted for MV-1/MV-3 vertical slices; revisit only on measured quality/budget evidence.

Province authority is `5632×2048`; current terrain, height, and water art is `2816×1024`. Compare:

Keep full-resolution semantic authority, half-resolution continuous macro height/terrain/water, and add tiled micro materials/normal detail. Tiling/streaming or full-resolution macro variants require measured MV-3 evidence and memory/load approval.

## TD-014 — Strategic Camera Projection

**Status:** Accepted for MV-1 implementation.

Use orthographic projection at strategic and regional zoom. A gentle perspective close-detail tier is optional only if its transition passes selection, label, scale, and motion tests. The inherited 75° perspective default is rejected for the final strategic-map presentation. After tiny-label culling, the matched France capture measured `29.647 ms` P95 orthographic versus `30.995 ms` perspective on the current low-end machine. See [MV-0 Scale, Projection, and Realm Audit](MV0_SCALE_PROJECTION_REALM_AUDIT.md).

## TD-010 — Rivers

**Status:** Architecture accepted; content source unresolved.

Use authoritative vector/graph-like river data with stable IDs, width class, flow/source/mouth, and lake/coast connections. Generate render geometry/textures from the data. Do not paint rivers permanently into the political or terrain base.

The schema, ingestion validator, template, and contract tests are implemented under `tools/hydrography/`. Runtime river rendering remains blocked until a reviewed, licensable source produces an approved non-empty definition file.

## TD-011 — Water Scope

**Status:** Proposed.

MV-3 requires deep/shallow distinction, restrained motion, coast transition, lakes, seams, reduced-motion, and a low-cost tier. Reflection is optional P2 and cannot block a successful non-reflective material.

## TD-012 — Target Mock-ups

**Status:** Required before Visual Greenlight.

**Production brief:** [MV0_TARGET_MOCKUPS.md](MV0_TARGET_MOCKUPS.md) locks the three prompts, invariants, layer ownership, review rubric, and runtime translation constraints.

Produce three project-original target frames using the same camera bookmarks as the current baseline:

1. France/Low Countries political mode.
2. Sahara/Nile terrain mode.
3. Italy/Alps regional political/terrain integration with final typography direction.

Each mock-up annotates layer changes and identifies which elements are authored, generated, runtime, and optional.

## TD-013 — External GPU Capture

**Status:** Required.

Godot monitors and wall-clock captures establish symptoms but do not identify GPU pass cost. Capture the France/Low Countries political benchmark with an approved GPU profiler/RenderDoc-compatible workflow, storing:

- Build ID and driver.
- Pass/event list.
- GPU timing where available.
- Render-target and texture memory.
- Draw/primitive counts.
- Screenshot and interpretation.

The MV-0 layer-isolation probe has already established two facts for that capture:

- The previous catastrophic periodic stall was CPU-side hidden `SimulationHUD` checksum work and is fixed.
- The dense view drops from `206` P95 draw calls with labels to `2` without them, and from roughly `29.9 ms` to `14.8 ms` P95 wall-frame interval. Inspect label draw passes first.

## Approval Queue

| Decision | Required approval/evidence |
|---|---|
| TD-002 world mesh | Rendering/Technical Art after memory projection |
| TD-003 data/presentation edge | Rendering + QA selection agreement fixture |
| TD-004 country/subject semantics | Engineering rule/data accepted; Design + Historical Content + UX presentation sign-off open |
| TD-005 layer contract | Rendering + Technical Art + UX |
| TD-006 AA | Accepted; monitor still/motion regressions and confirm with external GPU trace |
| TD-007 labels | Architecture accepted; batched renderer implementation and Typography Gate open |
| TD-008 imports | Accepted and reimported; deterministic audit passes |
| TD-009 resolution tier | Accepted for vertical slices; MV-3 may reopen with measured evidence |
| TD-010 rivers | Tools/Map Content/Rendering design |
| TD-011 water | Art + Rendering quality-tier spike |
| TD-012 mock-ups | Art/Product Visual Greenlight |
| TD-013 GPU capture | QA/Rendering evidence |
| TD-014 camera projection | Engineering accepted; Art/UX motion approval open |
