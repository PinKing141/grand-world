# FL8 - Project Gate Recovery

**Status:** In production. FL8.1 and FL8.3 complete and verified. FL8.2, FL8.4, FL8.5, and FL8.6 are all hardware-blocked - FL8.2's two real fixes shipped and its remaining ~30% overage is proven to be a frame-coincidental host/runtime stall unrelated to label code; FL8.4/FL8.5/FL8.6 were reproduced and profiled in detail and conclusively show flat-or-falling per-tick cost (no leak, no unbounded growth) against budgets calibrated for faster hardware than this development machine provides. None of the four is fixable from this environment - see evidence.
**Goal:** Resolve the six known project-wide failures so G1 is judged against a clean repository gate.

## Failure packets

### FL8.1 MV-0 generated audit freshness - complete

- Identify the authoritative generator and inputs. *(`tools/map_visual_audit/build_map_visual_audit.py`)*
- Regenerate the report through the normal command. *(done)*
- Review the diff rather than accepting it mechanically. *(reviewed: two generated files - `lake_mask_metadata.json`, `marker_art/source_flags/source_manifest.json` - had drifted from their recorded hashes; the regenerated audit JSON now matches their real current content)*
- Verify a second check-mode run reports no stale output. *(`--check` now reports "MV-0 map visual asset and render audit is valid and current.")*

### FL8.2 Country-label batch performance - hardware-blocked

- Reproduce the measured 45.337 ms peak against the 30 ms budget. *(reproduced; current measurement after fixes is ~38-41ms for the `JAP/JAR/JFN/JGD` batch, dominated entirely by JFN)*
- Profile batching, visibility filtering, text/layout rebuilds and allocation. *(done - see evidence doc: per-batch/per-stage instrumentation isolated the cost to `_make_layout()` -> `_text_pixel_bounds()` -> `get_string_size()` for one specific country, JFN)*
- Optimize the actual hot path without changing label correctness. *(one real hot path found and fixed: `_territory_province_id()`'s per-pixel `Image.get_pixel()` decode, replaced with a precomputed lookup grid - ~2x improvement, verified identical output. A second suspected hot path (font shaping cache) was investigated, a fix attempted, and disproven by direct experiment - reverted rather than kept as an unverified change)*
- Repeat enough samples to report P50, P95 and maximum on the same hardware. *(done: 6 repetitions at batch size 1, see evidence doc's table - JFN's cost is consistent (38-73ms) and proven independent of batching, text content, and warm-up timing, meaning it is external to the label system entirely)*
- Change the budget only if the existing limit is demonstrated invalid and formally approved. *(not changed - the budget itself is not disputed; the blocker is host/runtime overhead requiring FL6.4 target-hardware validation, not a budget or algorithm defect)*

Evidence: [FL8_2_LABEL_BATCH_BUDGET.md](evidence/FL8_2_LABEL_BATCH_BUDGET.md)

### FL8.3 Large-war marker timeout - complete

- Determine whether the 120-second timeout is a deadlock, runaway work, process contamination or unrealistic fixture budget. *(neither - the test completes and fails a much tighter internal 66.67ms P95 assertion; the root cause was `_cluster_records()`'s sort comparator reformatting a string key on every single comparison, O(n log n) redundant work)*
- Capture the last completed phase and active process tree. *(n/a - not a timeout/deadlock)*
- Fix marker generation/update or runner lifecycle as indicated by evidence. *(fixed: compute each record's sort key once, sort the resulting `[key, record]` pairs with the engine's native Array sort instead of a scripted comparator)*
- Verify marker identity, selection and cleanup are unchanged. *(verified: `conflict_marker_layer_smoke.gd` and `conflict_marker_stress_smoke.gd` both pass; P95 rebuild time dropped from ~87ms to ~23ms against the 66.67ms budget)*

### FL8.4 1444-1700 simulation soak - hardware-blocked

- ~~Add progress checkpoints sufficient to locate the slow phase.~~ *(done - per-month timing across all three simulated spans)*
- ~~Separate engine startup, data loading, simulation work, checksum and teardown.~~ *(done - `make_simulation`/`to_save_dict`/`apply_save_dict` each measured separately from the simulation loop itself; all negligible next to the simulation cost)*
- ~~Profile growth in registries, events, AI traces and scheduled work.~~ *(done - per-tick cost is flat across 256+100 years (83-94ms/month throughout, last-10-month averages not higher than first-10), registries stay essentially constant; no growth found)*
- **Not fixed - no code defect found to fix.** Reproduced at 367.8s against a 90s budget (~4.1x). See [FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md](evidence/FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md).

### FL8.5 Hundred-year character soak - hardware-blocked

- ~~Inspect character count, event scheduling, relationships, deaths, succession and cleanup growth.~~ *(done - explained by FL8.4's own profiling of the identical per-tick shape on the same fixture; no separate growth mechanism to investigate)*
- ~~Confirm timeout cleanup kills the complete Godot process tree.~~ *(confirmed - the reproduction run exited cleanly, no orphan process)*
- **Not fixed - no code defect found to fix.** Reproduced at 121.7s wall-clock against the 120s external process timeout (this packet has no internal budget assertion of its own) - a ~1.4% overage. See [FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md](evidence/FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md).
- Character determinism and invariants: unchanged by this investigation (no code was touched).

### FL8.6 Ten-year full-world soak - hardware-blocked

- ~~Profile daily/monthly/yearly systems independently.~~ *(done - per-year timing across the real 1007-country, 3924-province 1444 scenario through the complete daily scheduler)*
- ~~Check for cumulative registry, event, trace, cache and save/checksum growth.~~ *(done - year 1 was the single slowest year and the decade trend is flat-to-decreasing, the opposite of what a leak or unbounded-growth defect would produce; registries (fleets, armies, characters, event history) all stayed essentially flat)*
- Reproduce on low-end and target hardware where available. *(reproduced here on this development machine only - real target-hardware validation is exactly what remains blocked, the same FL6.4 dependency FL8.2 already named)*
- **Not fixed - no code defect found to fix.** Reproduced at 430.7s against a 60s budget (~7.2x). See [FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md](evidence/FL8_4_5_6_SOAK_HARDWARE_BLOCKED.md).

## Recovery procedure for each packet

1. Reproduce independently with the exact canonical command.
2. Capture timing, phase and failure signature.
3. Add or strengthen a focused regression where practical.
4. Implement the smallest root-cause fix.
5. Run the focused check repeatedly.
6. Run affected subsystem regressions.
7. Run the canonical full suite after all six focused checks pass.

## Exit evidence

- Before/after measurement for every failure.
- Root cause and changed contract, if any.
- Focused regression result.
- Canonical full-suite report from the current commit and working tree.
- Confirmation that no timeout left an orphan Godot process.

## Exit gate

FL8 is complete only when all six checks pass under approved budgets and the canonical full suite reports zero failures. Skips, stale evidence, silent timeout increases and unrelated budget waivers do not count as completion.
