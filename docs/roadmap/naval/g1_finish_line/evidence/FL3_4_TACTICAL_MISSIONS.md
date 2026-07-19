# FL3.4 - Tactical Mission Decisions

**Status:** Complete for the four newly real missions plus the stand-down mechanism they needed. Targeted tests pass (see Verification).
**Satisfies:** the FL3.4 findings recorded in [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md) - `patrol`, `intercept`, `protect_coast`, and `escort` (mapped to the existing `protect_transport` mission) now have real assignment logic, consuming `NavalThreatMap`.

## What shipped

Four new `_consider_*()` functions, slotted into `_plan_tactical()`'s existing priority chain by urgency:

1. **Escort** (`_consider_escort()`, mission `protect_transport`) - an idle warship sharing a zone with one of this country's own actively sailing transport operations takes up escort duty there. Checked first among the new missions: a fleet should not go hunting while its own convoy sails unescorted through the same water.
2. **Intercept** (`_consider_intercept()`) - an idle warship sharing a zone with an *enemy* transport operation actually sailing through it right now. Deliberately does not chase hostile combat fleets - that is blockade/evade's own job. This is specifically the roadmap's own distinction: catching enemy shipping in the act, not fighting enemy warships.
3. **Protect coast** (`_consider_protect_coast()`) - checked after blockade/evade (a fleet capable of striking the enemy directly, or one that must flee, has a more urgent job). Broader than blockade's own port-specific target: *any* owned land neighbour of a threatened zone counts, not just a hostile-owned one worth blockading, so a fleet can defend home coastline under threat even when there is nothing of the enemy's to blockade there.
4. **Patrol** (`_consider_patrol()`) - the lowest-priority positioning mission, the last real assignment considered before a fleet is simply left to hold station. A fleet with nothing more urgent to do keeps some presence in a currently safe zone.

## The missing other half: stand-down

Building escort surfaced a real problem, not assumed: `patrol`, `intercept`, `protect_coast`, and `protect_transport` have no completion condition anywhere in the simulation layer - `FleetMissionSystem` only ever resolves `blockade`/`return_to_port`/`repair` (the same "fully inert" finding the FL2 closure audit already made about these mission tags, now confirmed true from the AI side too). Without a fix, a fleet the AI assigned one of these four would carry the tag forever - an escort fleet would stay "escorting" a transport operation that finished days ago, wasted and never reconsidered.

`_consider_mission_completion()` is the fix: checked right after repair/return (before any new assignment is considered), it re-evaluates whichever of the four self-assigned conditions justified the fleet's *current* mission, and stands it down to `idle` the moment that condition no longer holds - freeing it up for fresh reconsideration on the country's next tactical tick. `blockade`/`return_to_port`/`repair` are deliberately untouched by this function; they already have real completion conditions (or, for `blockade`, an existing tested precedent this packet does not alter).

## Verification

- `tests/naval_ai_tactical_missions_test.gd` (new): escort assigned to an idle warship sharing a zone with its own sailing transport; intercept assigned for a hostile sailing transport in the same zone, with a control proving a non-hostile (no active war) transport is never intercepted; protect_coast assigned for hostile power near owned coastline with no reachable blockade target (a real fixture zone confirmed against the live maritime graph to have no hostile-owned land neighbour, isolating it from blockade); patrol assigned to an idle fleet in an otherwise-safe zone with nothing else to do; and mission-completion stand-down proven both ways - a fleet marked `protect_transport` with no transport operation left in its zone is reset to `idle`, while an otherwise-identical fleet whose transport operation is still actually there is correctly left alone.
- `tests/naval_ai_test.gd`, `tests/naval_ai_threat_test.gd`, `tests/naval_ai_organisation_test.gd`, `tests/naval_ai_transport_test.gd`, `tests/naval_threat_map_test.gd`, `tests/naval_ai_strategic_posture_test.gd` (pre-existing, unmodified by this packet): all re-run clean, including `naval_ai_test.gd`'s own two-instance 215-day determinism replay.
- Registered in `tools/testing/run_all_tests.py`.

## Deliberately out of scope for this packet

- **`trade_protection`** - not part of the roadmap's own FL3.4 candidate list (which names patrol, interception, coast protection, blockade, escort, repair, retreat, idle-return - eight, all now real). `trade_protection` is explicitly FL5's job (it needs a trade-protection *output* to mean anything, which does not exist yet), not re-opened here.
- **Reinforcement** ("compare reinforcement arrival time and value before joining a battle") - explicitly FL3.3's own still-open item, not this function's.
- **Positioning/class-matchup/hull-crew-morale-adjusted "effective power"** for these new missions' own trigger conditions - they use the same raw `total_attack` comparison the rest of this file already uses (per the closure audit's own FL3.4 finding, unchanged and not re-opened by this packet).
