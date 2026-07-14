# MV-0 — Direction Lock Working Package

**Milestone state:** In progress  
**Gate:** Visual Greenlight  
**Runtime visual changes authorised by this package:** None until the relevant comparison decision is approved

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
| `mv0_asset_render_audit.json` | Machine-readable audit evidence | Generated |
| `tests/baselines/map_visual_mv0/current/` | Ten map-only GPU captures and runtime metrics | Captured on current development hardware |
| `mv0_performance_probe.json` | Layer-isolation results for labels, armies, base map, simulation, and every HUD | Captured post-fix |

## Reproduce

~~~powershell
python tools/map_visual_audit/build_map_visual_audit.py --check

python tools/map_visual_audit/capture_mv0_baselines.py `
  --godot C:\path\to\Godot_v4.7-stable_mono_win64_console.exe
~~~

The screenshot job requires a normal Forward+ rendering window. It is not a dummy-headless test.

## Gate Rule

MV-0 is not complete because documents exist. Visual Greenlight requires:

- Target political, terrain/water, and typography mock-ups.
- [Target mock-up production brief](MV0_TARGET_MOCKUPS.md) and [concept-frame folder](targets/README.md).
- Art/Product approval of the visual thesis and reference board.
- A valid external GPU frame/pass capture or an explicitly approved alternative profiler.
- Decisions for AA/sampling, label render method, source texture rights, terrain/height tiers, river data, and water scope.
- A credible projection that the approved stack can meet the 60 FPS target.

Until then, import/shader findings are risks to test, not permission for unreviewed visual changes.
