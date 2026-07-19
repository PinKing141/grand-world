# FL3 Verification 2/4 - Full AI Recovery Matrix

**Status:** Complete. Targeted test passes (see Verification). Two real gaps were found and fixed while building it, not assumed already correct.
**Satisfies:** the second of [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md)'s four untested "Automated verification" roadmap claims - "AI recovers from destroyed fleets, blocked/captured ports, access loss, peace, debt and insufficient sailors."

## What "recovery" means here

The closure audit's own framing distinguishes a one-shot rejection from genuine recovery: several of the six named scenarios already had a rejection proven (insufficient sailors, for instance, was already recorded as `insufficient_sailors` and left alone), but nothing proved the AI actually *resumes useful work* once the obstacle clears. `tests/naval_ai_recovery_matrix_test.gd` proves a full before/during/after story for each scenario it covers: a real obstacle, the AI's correct reaction to it, the obstacle clearing, and the AI genuinely resuming - not just a cleared flag nothing else reads.

## Two real gaps found and fixed, not assumed

### 1. Destroyed fleets never freed their admiral

`NavalCombatSystem._begin_retreat()`'s no-legal-retreat branch erased a destroyed fleet's ships and fleet record, but never looked up or cleared its admiral's `admiral_fleet_id` - a gap [FL2_5_SCUTTLE_COMMAND.md](FL2_5_SCUTTLE_COMMAND.md) had already found and explicitly left open ("a real, pre-existing dangling-reference gap in combat-driven destruction, out of scope to fix here"). Left unfixed, `_best_available_admiral()` would exclude that character forever (its `admiral_fleet_id` still pointed at a fleet that no longer existed), making the character permanently uncommandable - directly blocking "recovers from destroyed fleets," since the AI could never reuse that admiral again. Fixed by mirroring `ScuttleFleetCommand.apply()`'s own admiral-cleanup exactly (`naval_combat_system.gd`).

### 2. A blockading fleet was invisible to every other tactical decision after peace

`BlockadeSystem`'s own queries already correctly zero out the instant a war ends - proven in [FL5_2_BLOCKADE_COASTAL_CONTRACT.md](FL5_2_BLOCKADE_COASTAL_CONTRACT.md). But nothing previously reset the fleet's own `mission` tag back to `idle`, and every other tactical `_consider_*` function (`_consider_reinforcement`, `_consider_escort`, `_consider_intercept`, `_consider_blockade_or_evade`, `_consider_protect_coast`, `_consider_patrol`) requires `mission == "idle"` before it will even look at a fleet. A fleet still tagged `"blockade"` after peace was therefore not merely *ineffective* at blockading - it was permanently excluded from every future tactical reconsideration, parked forever. `_consider_mission_completion()` (`naval_ai_system.gd`) previously handled `protect_transport`/`intercept`/`protect_coast`/`patrol` but explicitly excluded `blockade`, on the reasoning that "blockade already has a real completion condition." That reasoning was correct for `BlockadeSystem`'s own effect calculation but incomplete for the AI's own reconsideration - fixed by adding a `"blockade"` case, reusing the existing `_zone_has_blockade_target()` query (itself already war-gated) to decide when the mission is no longer justified.

## Verification

- `tests/naval_ai_recovery_matrix_test.gd` (new), five scenarios:
  - **Destroyed fleets**: a fleet with an assigned admiral is destroyed through the real no-legal-retreat combat path (every port in the graph hostile-owned, the same fixture shape `naval_destructive_edge_gate_test.gd`'s own `_test_retreat_and_save()` already established, since `NavalAccessPolicy.can_dock()` treats any *unowned* port as legally dockable by anyone - simply flipping two provinces is not enough to strand a fleet against the real full graph). The freed admiral is then genuinely reassigned to a surviving fleet by the AI's own organisation planning.
  - **Debt**: a country in debt classifies `recovery` (frozen ship count) on `_review_posture()`; clearing debt and reviewing again, on the same persistent AI state, resumes the ambitious multiplier - not just a fresh world classifying correctly in isolation.
  - **Insufficient sailors**: construction is proactively rejected while sailors are unavailable; replenishing sailors and re-planning actually queues a real ship on the very next tick.
  - **Peace mid-blockade**: proves the fix above end to end - a fleet takes up blockade duty, the war ends, `_consider_mission_completion()` stands it down to `idle`, and the freed fleet is then genuinely picked up by `_consider_patrol()` on the very next tactical consideration, not just theoretically eligible.
  - **Captured/blocked construction port**: `_best_construction_port()` already scopes to `_country_ports()` (owned and enabled only), so a captured port drops out automatically with no special-case code; construction correctly lands at the country's one remaining owned port instead of failing.
  - **Access loss / captured home port** is deliberately not duplicated here - `tests/naval_ai_reinforcement_homeport_transport_test.gd`'s own `_test_home_port_reassigned_on_access_loss()` already proves that exact recovery story end to end.
- `tests/naval_ai_test.gd`, `tests/naval_ai_tactical_missions_test.gd`, `tests/naval_combat_test.gd`, `tests/naval_ai_reinforcement_homeport_transport_test.gd`, `tests/naval_destructive_edge_gate_test.gd` (pre-existing, re-run clean) - confirming both fixes changed no existing test's expected outcome, including `naval_ai_test.gd`'s own two-instance determinism replay and `naval_destructive_edge_gate_test.gd`'s own destruction/retreat/lifecycle matrix.
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after every edit in this packet.

## Deliberately out of scope for this packet

- **Blocked ports via active blockade specifically** (as opposed to captured/ownership-lost ports) - `EconomySystem._complete_naval_construction()`'s existing blockade-pause behaviour (N5.2, already tested in `naval_blockade_test.gd`) already covers this at the simulation layer; not naval-AI-specific and not duplicated here.
- **Verification packets 3-4** (trace-neutrality, a measured performance budget) - each its own tracked packet, not attempted here.
