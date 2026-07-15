# MV-0 Status — Direction Lock

## Overall State

**In progress. Visual Greenlight has not passed.**

The baseline, audit pipeline, target concepts, technical decisions, and first MV-1 production renderer pass now exist. Formal art/product approval, source-rights resolution, retained external GPU pass analysis, and multi-machine validation remain open.

## Deliverable Status

| ID | Deliverable | State | Evidence / remaining work |
|---|---|---|---|
| MV0-01 | Standard current captures | **Implemented** | Ten Forward+ map-only captures plus manifest; hands-on review sign-off remains |
| MV0-02 | CPU/GPU frame, memory, and hitch baseline | **Implemented; external trace review open** | Final post-edge-lattice all-layer 1080p motion P50/P95 `13.266/15.748 ms`, max `26.185 ms`; no frames above 50 ms |
| MV0-03 | Legal reference board and visual thesis | **Partial** | Research board seeded; Art/Product approval and historical-atlas board pending |
| MV0-04 | Political, terrain/water, typography target mock-ups | **Produced; approval pending** | All three concepts exist under `mv0/targets/`; coherent-direction review and Art/Product scoring remain |
| MV0-05 | Zoom bands and layer matrix | **Engineering accepted** | Matrix written; orthographic strategic/regional policy selected; motion/UX art approval remains |
| MV0-06 | Render architecture and decisions | **Engineering accepted and first-pass implemented** | Orthographic camera, optional perspective transition, batched labels, palette/accessibility profiles, canonical shared-edge lattice with strategic SDF fallback, realm cues, border hierarchy, canonical lake treatment, seam-safe screen-stable command paths, batched conflict markers, and restrained coast treatment are live; authoritative rivers/final water art remain |
| MV0-07 | Reference hardware and provisional budgets | **Implemented for production** | Low-end and recommended validation tiers plus frame/memory budgets approved; multi-machine release validation remains |
| MV0-08 | Asset resolution, ownership, and licensing audit | **Implemented with blockers** | Deterministic audit passes; unverified imported province/definition/water sources remain release blockers |
| MV0-09 | Reproducible-build preflight debt | **Partial** | Audit/capture tools reproducible; UID/generated-file policy and dirty-worktree separation remain |

## Current Development Baseline Machine

| Component | Captured value |
|---|---|
| System | Lenovo 82VG |
| OS | Windows 11 Home, build 26200 |
| CPU | AMD Ryzen 3 7320U, 4 cores / 8 logical processors |
| GPU | AMD Radeon 610M, driver `32.0.21030.11004` |
| Reported adapter memory | 2 GiB |
| Physical system memory | Approximately 5.74 GiB usable/reported |
| Renderer/API | Godot 4.7 Forward+, D3D12 feature report `12_0` |

This is a useful low-end development baseline, not yet the approved minimum or recommended specification.

## Open Gate Blockers

1. No approved coherent set of three project-original target mock-ups.
2. Imported province topology, definition data, and water texture lack complete source/licence records.
3. RenderDoc capture was proven on the updated AMD driver, but the capture must be retained with pass-level analysis; earlier attempts also recorded D3D12 readback-memory failures.
4. Country/subject/uncolonised/wasteland semantics have an engineering contract but still require final Design/Historical presentation approval.
5. River representation/ingestion architecture is accepted and validated, but an approved river source and final water art scope remain unresolved.

## Immediate Execution Queue

1. Complete and review Targets B/C alongside Target A, then approve one coherent direction.
2. Retain and analyse an external GPU capture of the orthographic France/Low Countries view now that the batched renderer is active.
3. Resolve or replace province topology, definition, and water sources.
4. Review the implemented realm/border/palette/coast pass against the three target concepts and record Art/Product decisions.
5. Review/approve the reference board, political semantics, river representation, and water scope.

## Resolved During MV-0

- Removed periodic `650–800 ms` normal-play stalls caused by the hidden `SimulationHUD` checksum refresh.
- Added a rendered layer-isolation probe covering labels, armies, base map, simulation, every HUD, and static/moving camera states.
- Confirmed the base map can remain below `16.67 ms` at P95 on the development machine when country labels are disabled.
- Corrected categorical and height import policy and enabled MSDF font rendering.
- Added derivative-aware political-border AA without a global blur pass.
- Captured and validated matched perspective/orthographic France views; after tiny-label culling, orthographic measured `29.647 ms` P95 versus `30.995 ms` for perspective on the current machine.
- Initialized Auvergne, Bourbonnais, Foix, and Orléans as separately owned French appanages in the 1444 scenario.
- Replaced per-country `Label3D` rendering with screen-space MSDF glyph batches: the measured view uses three atlas-page draws and zero `Label3D` nodes.
- Added exact screen translation during orthographic panning and deferred full visibility rebuilds until a meaningful pan distance or movement settle.
- Reached `15.748 ms` all-layer motion P95 at 1920×1080 after replacing province-interior contours with the exact shared-edge lattice on the Radeon 610M development machine.
- Implemented orthographic strategic/regional presentation with an opt-in close perspective transition.
- Added normalized political colours, appanage/subject realm tinting, lighter internal-realm edges, sovereign/province/coast hierarchy, and removed the cyan water multiplier.
- Corrected the final material to sample `terrain_class_map.png` as categorical authority instead of accidentally sampling `terrain_base_map.png` in that slot.

## Gate Decision

**Visual Greenlight: NOT PASSED.**

Reason: MV-0 has reliable evidence now, but visual target frames and several render/data decisions still require proof and approval. Starting a global art pass at this point would create avoidable rework.
