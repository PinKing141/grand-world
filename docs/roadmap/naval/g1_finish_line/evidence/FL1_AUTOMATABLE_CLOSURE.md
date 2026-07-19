# FL1 Automatable Closure

**Date:** 2026-07-20
**Result:** PASS - every named headless follow-up in FL1.2, FL1.3 and FL1.4 is implemented and regression-tested. FL1 remains at `Validation` only because its rendered/manual acceptance is owned by FL6.

## Changes

- `FleetMarkerLayer` and `NavalHUD` now retarget a live selection to the deterministic merge survivor when the selected source fleet is merged away. A split preserves the surviving source selection.
- A new lifecycle test drives cancellation, peace cleanup and two real quick-save/quick-load reconciliations. It proves selected route geometry is restored when present and removed when absent. The merge test also proves retargeting cannot retain route geometry from the removed source.
- `BlockadeSystem.blockade_contributors()` and `primary_blockading_country()` derive deterministic attacker attribution from the same eligibility, targeting and damage-aware effective-power rules as blockade strength. `ConflictMarkerLayer` carries this structured attribution and `NavalHUD` resolves attacker names and power.
- The blockade presentation contract is now explicit: the persistent, colour-independent port icon is the always-on cue; the existing on-demand blockade overlay colours every affected coastal land province. A second independent coastline-geometry authority is intentionally not introduced.

## Verification

- Full-project Godot editor parse check: PASS.
- `tests/naval_fleet_organisation_hud_test.gd`: PASS, including split preservation and merged-away selection retargeting in both HUD and map.
- `tests/fleet_marker_lifecycle_test.gd`: PASS (`cancellation=1 save_load_restore=1 save_load_clear=1 peace_cleanup=1`).
- `tests/naval_blockade_test.gd`: PASS, including deterministic multi-fleet contributor aggregation and primary attacker.
- `tests/conflict_marker_layer_smoke.gd`: PASS, including structured attacker metadata and player-facing attacker name.

## Remaining boundary

Supported-resolution inspection, keyboard-only use, colour-vision review, rendered frame timing and real GPU/hardware checks remain FL6 work. No further headless FL1 implementation gap is named.
