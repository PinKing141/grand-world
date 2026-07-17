# N5.1 - Port Fully Blockaded/Unblocked Events

**Status:** Recorded. "Province blockade level changed across meaningful thresholds" and "Coastal siege support changed" remain open, unchanged from the previous round.
**Satisfies:** the "port fully blockaded/unblocked" portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N5.1's threshold-events item, and another item of [05 - N5 Strategic Effects](../05_N5_STRATEGIC_EFFECTS.md) "Events and Queries"
**Scope:** `BlockadeSystem.process_day()` extended to store each blockaded province's actual bp value (not just a boolean), and two new events, `port_fully_blockaded`/`port_unblocked`, fired specifically for registered ports crossing the bp==10000 boundary. No new persisted field, no schema bump - this reuses `blockaded_provinces` exactly as the previous round's evidence doc anticipated.

## Why this reused the previous round's infrastructure directly, without a schema bump

The previous round (`N5_1_BLOCKADE_STARTED_ENDED_EVENTS.md`) named this as the natural next step: `blockaded_provinces` already had to persist *something* to detect the started/ended transition, and storing the actual bp value instead of a bare boolean costs nothing extra structurally - the field is still a `Dictionary` keyed by province ID, still validated the same way, still checksummed the same way. Widening a `true` value to an integer bp value is additive from every consumer's perspective that only ever checked `.has(key)` (both this file's own started/ended assertions and any future reader), so no `SAVE_SCHEMA_VERSION` bump was needed - this is the same "no version bump for an additive, backward-compatible field widening" reasoning already used elsewhere when a `.get(key, default)` read pattern makes an old absent value safe.

## Architectural choices

**"Port fully blockaded/unblocked" only fires for registered ports (`NavalDefinitions.is_port()`), while "blockade started/ended" continues to fire for any blockaded coastal province.** 05_N5's own wording draws this distinction explicitly - "Blockade started/ended" is stated generally, while "Port fully blockaded/unblocked" names a port specifically. This mirrors the same `is_port()` gate coastal-siege-assist already uses for the identical reason (a stricter, more defensible reading of "port" than "any coastal land neighbour of a blockading fleet's sea zone").

**The full/unblocked transition is computed from the *same* stored bp values the started/ended transition already reads, in the same loop, not a second pass over the data.** `process_day()` now does both comparisons - `was_blockaded` vs `is_blockaded` (presence) and `was_full` vs `is_full` (value >= 10000) - for each candidate province in a single iteration, since both checks need the same `previous`/`current` dictionaries already in scope.

**No new bounds relaxation on the "blockade started/ended" logic.** A province can be genuinely blockaded (non-zero bp, firing `blockade_started`) without ever reaching full (10000 bp, firing `port_fully_blockaded`) - the two signals are independent and can be in any combination: started-but-never-full, started-then-full, full-then-back-to-partial-but-still-started, or all the way to ended. The test coverage below exercises the specific partial -> full -> partial -> ended sequence to prove the two signals genuinely track different thresholds rather than accidentally firing together.

## What was built

- `scripts/simulation/simulation_event_bus.gd`: `port_fully_blockaded(province_id: int)`, `port_unblocked(province_id: int)`.
- `scripts/simulation/blockade_system.gd`: `process_day()` now stores `province_blockade_bp()`'s actual integer value in `blockaded_provinces` instead of `true`, and emits the two new events for registered ports crossing the 10000-bp boundary.
- `scripts/simulation/campaign_world_state.gd`: `apply_save_dict()` gained a bounds check on each recorded blockade value (must be in `(0, 10000]`) - the "Bounds for... blockade..." validation category 07_DATA_COMMAND_EVENT_SAVE_CONTRACTS.md's Load Validation section already calls for, now meaningful since the stored value carries real information instead of always being `true`.
- `tests/naval_blockade_test.gd`: extended (no new file) with a section proving the two signals track independently - a 3-power fleet produces a genuine but partial blockade (`blockade_started` fires, `port_fully_blockaded` does not); adding enough additional power reaches a full blockade (`port_fully_blockaded` fires, `blockade_started` does not re-fire); withdrawing the second fleet drops back to partial (`port_unblocked` fires, `blockade_ended` does not fire, since the blockade is still genuinely active); withdrawing the remaining fleet finally fires `blockade_ended`.

## Results (verified via `naval_blockade_test.gd`, exit 0, no errors)

- A partial (non-zero, sub-10000) blockade fires `blockade_started` but never `port_fully_blockaded`.
- Reaching exactly full power (one ship per required-power point, matching the earlier target-resistance clamp test's own fixture pattern) fires `port_fully_blockaded` exactly once, without re-firing `blockade_started` for an already-active blockade.
- Dropping back below full power while remaining genuinely blockaded fires `port_unblocked` exactly once, without firing `blockade_ended`.
- Only releasing the blockade entirely fires `blockade_ended`.
- No regression: re-ran all 42 Godot phase/core/naval tests after this round's changes - 41/42 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4/N5 evidence doc so far.

## Deliberately simple / deferred

- **No "province blockade level changed across meaningful thresholds" event.** *(Built in a later round - see [N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md](N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md), a quartile-bucket scheme reusing the same stored bp values.)*
- **No "coastal siege support changed" event.** *(Built in a later round - see [N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md](N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md).)*
- **No naval-blockade-scale stress/performance test.** Unchanged from the previous round - this change adds no new O(fleets) scans of its own (it reuses `province_blockade_bp()`'s already-computed value), but the underlying deferred performance item remains open regardless.
