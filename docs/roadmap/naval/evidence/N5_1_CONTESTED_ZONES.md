# N5.1 - Contested Zones

**Status:** Recorded, using the elimination reading of "reduce or eliminate," not a proportional contest. Reverse indexes remain deliberately not built; threshold events remain open.
**Satisfies:** the contested-zones portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N5.1, and the remainder of the N5A/N5B work packets in [05 - N5 Strategic Effects](../05_N5_STRATEGIC_EFFECTS.md)
**Scope:** `BlockadeSystem._zone_is_contested()`, folded into `is_fleet_eligible()` as one more disqualifying condition. No new persistent state, no proportional/diminishing-return contest formula, no change to `NavalCombatSystem`.

## Why this was a small, targeted addition rather than a new subsystem

Before this round, `is_fleet_eligible()` already excluded a fleet with a non-empty `battle_id` (the "in active battle = ineligible" rule N5.1's first evidence doc recorded as its simplification of "an active naval battle pauses/contests power"). Investigating how a battle actually starts (`NavalCombatSystem._start_battles()`, and this session's own N4 evidence docs) revealed that hostile fleets sharing a sea zone already trigger a battle automatically the day after they co-locate - meaning an opposing fleet's arrival *already* eliminates a blockade's eligibility, indirectly, within one simulated day. The daily tick order (`WarfareSystem.advance_day()` runs before `NavalCombatSystem.advance_day()` within the same `advance_one_day()` call, per `simulation_controller.gd`'s `daily_systems` registration order) means every blockade-consuming daily check - war score, siege assist, repair - runs *before* that day's battle-starting pass. The result is a genuine, narrow gap: on the exact day an opposing fleet arrives in a blockaded zone, the blockade still counts as fully uncontested for every daily consumer, for one tick, before the battle mechanism catches up. `_zone_is_contested()` closes exactly that gap - it does not duplicate or replace the existing "in battle" exclusion, which still handles every day *after* the first.

## Architectural choices

**Eliminating contribution when contested, not reducing it proportionally.** 05_N5 explicitly allows either ("reduce or eliminate"). This slice picks elimination because it is the same binary-threshold shape every other first-slice rule in `BlockadeSystem` already uses (damage-effectiveness threshold, siege-assist threshold, repair/construction-penalty threshold) - and because it makes the new rule strictly consistent with the *existing* "in active battle = ineligible" rule it is closing a timing gap around, rather than introducing two different contest strengths for what is functionally the same situation one day apart.

**A contesting fleet must be AT_SEA, not merely present in the fleet registry at that location_id.** `is_fleet_eligible()` already requires the *blockading* fleet to be AT_SEA (not docked, not mid-transit) to actually be "in" a zone; `_zone_is_contested()` applies the identical requirement to the opposing fleet for symmetry - a defender's fleet sitting safely in port does not contest a blockade of a *different* province, even if its `location_id` happens to match by coincidence (docked fleets use their port's province_id as `location_id`, not a sea zone, so this is mostly a defensive symmetry check rather than a scenario that arises often in practice).

**No mission requirement on the contesting fleet.** A blockading fleet must have `mission == "blockade"`; a *contesting* fleet does not need to, since 05_N5's contested-zones language is about "opposing eligible fleets" being present and able to fight, not about the defender specifically counter-blockading. An idle patrol or any other at-sea warship contests just by being there and hostile.

**No change to `NavalCombatSystem` or the daily tick order.** The alternative fix would have been reordering `daily_systems` so `NavalCombatSystem` runs before `WarfareSystem`, closing the gap "for free." This was rejected: N4's evidence docs already establish `FleetMovementSystem` → `WarfareSystem` → `NavalCombatSystem` as a deliberate "movement, then combat" ordering mirroring land's equivalent sequence, and reordering it purely to serve blockade timing would risk subtly changing reinforcement/retreat timing this session has already tested and documented elsewhere. Adding one explicit, self-contained check to `BlockadeSystem` - the system that actually owns this concern - was the smaller, lower-risk change.

## What was built

- `scripts/simulation/blockade_system.gd`: `_zone_is_contested()`; `is_fleet_eligible()` gained one more disqualifying condition calling it.
- `tests/naval_blockade_test.gd`: extended (no new file) with a contested-zones section - an opposing at-sea fleet sharing the blockader's zone drops `province_blockade_bp()` from a full 10000 to exactly zero, and `is_fleet_eligible()` itself returns false for the blockading fleet; a second check confirms a *docked* opposing fleet does not contest.

## Results (verified via `naval_blockade_test.gd`, exit 0, no errors)

- An England fleet sized to exactly meet Picardie's required power (a full, uncontested 10000 bp blockade) drops to exactly zero the moment a Burgundy fleet arrives AT_SEA in the same zone, before any battle has started.
- `is_fleet_eligible()` itself, not just the derived bp value, correctly reports the blockading fleet as ineligible once contested.
- A Burgundy fleet docked at a port sharing the same `location_id` coincidentally does not contest - the blockade remains at its full, uncontested value.
- No regression: re-ran all 42 Godot phase/core/naval tests after this round's changes - 41/42 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4/N5 evidence doc so far. `naval_combat_test.gd` passes unaffected, confirming this change does not alter battle-starting behaviour itself - only blockade eligibility.

## Deliberately simple / deferred

- **No proportional/diminishing-return contest.** A contesting fleet's own strength, size, or eligibility for blockade duty itself is irrelevant - any single hostile at-sea ship fully zeroes an otherwise-overwhelming blockade for that one tick. 05_N5's fuller "diminishing-return/cap rule applied once" language (for combining *friendly* fleets) and any proportional weighing of contesting strength remain unbuilt.
- **No reverse indexes.** Still deliberately a pure query layer, unchanged from N5.1's original scope.
- **No threshold events.** Still open - nothing persists a previous blockade value to diff a contested-vs-uncontested transition against.
- **`_zone_is_contested()` adds one more O(fleets) scan inside `is_fleet_eligible()`, which is itself already called inside O(fleets) loops elsewhere in `BlockadeSystem`.** This makes eligibility checks effectively O(fleets²) in the worst case - on top of the already-deferred "full-coast calculation meets approved budget" performance item, now measurably worse. No caching or reverse index was added to address this, consistent with this round's correctness-first, performance-later precedent.
