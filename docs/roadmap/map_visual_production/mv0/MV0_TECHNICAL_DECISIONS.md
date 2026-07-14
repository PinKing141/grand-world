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

**Status:** Proposed; Design/Historical approval required.

Default political mode shows the country that legally owns each province. Subjects/appanages such as Orléans keep their own colour and border. Relationship is expressed through a subject border/cue or dedicated realm/diplomatic presentation. Overlord realm grouping never rewrites authoritative ownership.

Country labels fit approved owned/integrated components, not every subject province.

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

**Status:** Spike required.

Compare at minimum:

- Current engine defaults.
- MSAA options appropriate to the 3D plane.
- TAA and/or screen-space AA.
- Signed-distance/analytic edge refinement.
- Texture sampling, mip, and pixel-alignment changes.

Judge still sharpness, camera shimmer, coast/border steps, label blur, terrain detail, GPU time, and minimum hardware. A global blur that hides stairs but softens labels is not acceptable.

## TD-007 — Label Rendering Architecture

**Status:** Spike required.

Compare improved `Label3D`/MSDF, projected screen-space labels, world/decal labels, and a hybrid. Preserve the existing full-name, safe-fit, collision, lifecycle, performance, and export gates.

## TD-008 — Height and Categorical Texture Imports

**Status:** Spike required; do not ship current settings without proof.

The generated audit found:

- `terrain_class_map.png` uses compressed import and mipmaps despite categorical class semantics.
- `heightmap.png` uses compressed import and mipmaps while driving geometry.
- `biome_map.png` is also categorical source data but imported as ordinary compressed/mipmapped art.

Compare output error, VRAM, load, filtering, and distant sampling before changing settings. Generated source data may remain full-fidelity on disk even if a separately validated runtime derivative is introduced.

## TD-009 — Terrain/Water Resolution Tier

**Status:** Spike required.

Province authority is `5632×2048`; current terrain, height, and water art is `2816×1024`. Compare:

- Current half-resolution art with improved material/detail layers.
- Full-resolution macro assets.
- Half-resolution macro plus tiled micro materials/normal detail.
- Tiled/streamed regional approach only if budgets demand it.

## TD-010 — Rivers

**Status:** Proposed.

Use authoritative vector/graph-like river data with stable IDs, width class, flow/source/mouth, and lake/coast connections. Generate render geometry/textures from the data. Do not paint rivers permanently into the political or terrain base.

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
| TD-004 country/subject semantics | Design + Historical Content + UX |
| TD-005 layer contract | Rendering + Technical Art + UX |
| TD-006 AA | Side-by-side still/motion/GPU spike |
| TD-007 labels | Typography still/motion/performance spike |
| TD-008 imports | Pixel/error/memory comparison |
| TD-009 resolution tier | Regional captures + memory/load comparison |
| TD-010 rivers | Tools/Map Content/Rendering design |
| TD-011 water | Art + Rendering quality-tier spike |
| TD-012 mock-ups | Art/Product Visual Greenlight |
| TD-013 GPU capture | QA/Rendering evidence |
