# MV-0 — Direction Lock Working Package

**Milestone state:** In progress  
**Gate:** Visual Greenlight  
**Runtime visual changes authorised by this package:** MV-0 engineering decisions are approved for the readability slice; global art production remains gated

## Purpose

This folder contains the evidence and decisions required before MV-1 changes the live map renderer. It distinguishes measured facts, proposed direction, accepted technical constraints, and items that require art/product approval.

## Documents and Evidence

| Artifact | Purpose | State |
|---|---|---|
| [MV-0 Status](MV0_STATUS.md) | Deliverable-level progress, blockers, and next actions | Active |
| [Current Baseline Review](MV0_BASELINE_REVIEW.md) | Visual review of reproducible current-state captures | Drafted; hands-on approval pending |
| [Asset and Render Audit](MV0_ASSET_RENDER_AUDIT.md) | Generated sizes, imports, hashes, shader facts, provenance, and gaps | Generated and stale-checkable |
| [Reference Board](MV0_REFERENCE_BOARD.md) | Legally safe external references and functional lessons | Seeded; approval pending |
| [Zoom and Layer Matrix](MV0_ZOOM_LAYER_MATRIX.md) | Strategic/regional/close visibility and hierarchy contract | Proposed |
| [Technical Decisions](MV0_TECHNICAL_DECISIONS.md) | Accepted constraints, proposed ADRs, and required spikes | Active |
| [Scale, Projection, and Realm Audit](MV0_SCALE_PROJECTION_REALM_AUDIT.md) | France measurements, matched camera comparison, and appanage rules | Engineering decision accepted; art review pending |
| [Rendering Architecture and Budgets](MV0_RENDERING_ARCHITECTURE_AND_BUDGET_DECISIONS.md) | AA, imports, labels, resolution tiers, hardware, and external-profile gate | Engineering decision accepted; performance/provenance blockers explicit |
| `mv0_asset_render_audit.json` | Machine-readable audit evidence | Generated |
| `tests/baselines/map_visual_mv0/current/` | Ten map-only GPU captures and runtime metrics | Captured on current development hardware |
| `tests/baselines/map_visual_mv0/camera_comparison/` | Matched perspective and orthographic France captures | Captured and automatically validated |
| `mv0_performance_probe.json` | Layer-isolation results for labels, armies, base map, simulation, and every HUD | Captured post-fix |

## Reproduce

~~~powershell
python tools/map_visual_audit/build_map_visual_audit.py --check

python tools/map_visual_audit/capture_mv0_baselines.py `
  --godot C:\path\to\Godot_v4.7-stable_mono_win64_console.exe

python tools/map_visual_audit/capture_mv0_camera_comparison.py `
  --godot C:\path\to\Godot_v4.7-stable_mono_win64_console.exe
~~~

The screenshot job requires a normal Forward+ rendering window. It is not a dummy-headless test.

## Gate Rule

MV-0 is not complete because documents exist. Visual Greenlight requires:

- Target political, terrain/water, and typography mock-ups.
- [Target mock-up production brief](MV0_TARGET_MOCKUPS.md) and [concept-frame folder](targets/README.md).
- Art/Product approval of the visual thesis and reference board.
- A valid external GPU frame/pass capture or an explicitly approved alternative profiler.
- Approved source texture rights, river data, and final water scope. AA/sampling, label architecture, camera projection, and terrain/height tiers now have accepted engineering decisions.
- A credible projection that the approved stack can meet the 60 FPS target.

Until then, the accepted engineering corrections may continue through MV-1, but target mock-ups and global visual-content production remain subject to Art/Product and provenance gates.
