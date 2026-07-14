# MV-0 Status — Direction Lock

## Overall State

**In progress. Visual Greenlight has not passed.**

The baseline, audit pipeline, research seed, zoom/layer proposal, and technical decision queue now exist. Target mock-ups, formal approvals, source-rights resolution, and external GPU diagnosis remain before MV-1 may alter the renderer as an approved production pass.

## Deliverable Status

| ID | Deliverable | State | Evidence / remaining work |
|---|---|---|---|
| MV0-01 | Standard current captures | **Implemented** | Ten Forward+ map-only captures plus manifest; hands-on review sign-off remains |
| MV0-02 | CPU/GPU frame, memory, and hitch baseline | **Partial** | Hidden checksum stalls fixed; current motion P50/P95 `21.340/24.236 ms`, max `26.348 ms`; label-isolation P95 `29.907` versus `14.783 ms` without labels; external GPU pass capture pending |
| MV0-03 | Legal reference board and visual thesis | **Partial** | Research board seeded; Art/Product approval and historical-atlas board pending |
| MV0-04 | Political, terrain/water, typography target mock-ups | **In progress** | Production brief, invariants, layer ownership, prompts, and review sheet locked; Target A is in production and Targets B/C are queued |
| MV0-05 | Zoom bands and layer matrix | **Proposed** | Matrix written; validate through motion/UX review |
| MV0-06 | Render architecture and decisions | **Partial** | Layer contract and ADR queue written; AA, labels, imports, resolution, rivers, and water spikes open |
| MV0-07 | Reference hardware and provisional budgets | **Partial** | Current development machine captured; minimum/recommended target hardware approval pending |
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

1. No approved project-original target mock-ups.
2. Imported province topology, definition data, and water texture lack complete source/licence records.
3. No accepted AA/sampling decision.
4. No accepted final label render-method decision.
5. No accepted terrain/height/water resolution strategy.
6. No external GPU pass capture explaining the current camera-motion misses.
7. Country/subject/uncolonised/wasteland semantics require Design/Historical approval.
8. River source/representation and water quality scope remain proposed.

## Immediate Execution Queue

1. Capture an external GPU frame for France/Low Countries political view, with special attention to the label passes.
2. Complete and review the three target mock-ups defined in [MV0_TARGET_MOCKUPS.md](MV0_TARGET_MOCKUPS.md).
3. Review/approve the reference board and political semantics.
4. Run AA/sampling and data-texture import comparison spikes.
5. Lock MV-1 tasks only after those comparisons choose a direction.

## Resolved During MV-0

- Removed periodic `650–800 ms` normal-play stalls caused by the hidden `SimulationHUD` checksum refresh.
- Added a rendered layer-isolation probe covering labels, armies, base map, simulation, every HUD, and static/moving camera states.
- Confirmed the base map can remain below `16.67 ms` at P95 on the development machine when country labels are disabled.

## Gate Decision

**Visual Greenlight: NOT PASSED.**

Reason: MV-0 has reliable evidence now, but visual target frames and several render/data decisions still require proof and approval. Starting a global art pass at this point would create avoidable rework.
