# FL3.5 - Escort Lifecycle

**Status:** Complete. Targeted test passes (see Verification).
**Satisfies:** the two escort-lifecycle gaps [FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md](evidence/FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md) recorded and deliberately left open when FL3.5's danger-aware routing shipped: "proactive escort reservation is still not attempted" and "an escort assigned this way does not follow the transport's route once it moves on."

## What shipped

### Proactive reservation

`_plan_transport()` now calls `_consider_proactive_escort_reservation()` the instant a transport operation is actually created (not before - reserving an escort for a candidate that then fails validation would be a wasted, unexplained order). It looks for one other idle, docked fleet still at the same departure port and tags it `protect_transport` immediately, so it is ready to depart with its convoy rather than only noticing it by coincidence once both happen to already be at sea together. A no-op, not an error, when no second fleet is available at that port - proactive escort is a bonus to the transport operation, not a requirement of it.

### Follows the voyage

`_consider_mission_completion()`'s own `"protect_transport"` justification widened from "co-located with a sailing operation *right now*" to "this country has *any* sailing operation left at all" - the fleet is no longer abandoned to idle the instant it parts zones with its convoy. That alone only stops premature abandonment; the actual chasing is a new function, `_consider_escort_follow()`, slotted into `_plan_tactical()` right after mission completion and before reinforcement: a fleet already on `protect_transport` duty, not currently co-located with any of its country's sailing transport operations, is ordered to the lowest-numbered such operation's current zone, bounded by a new `ESCORT_FOLLOW_MAX_ARRIVAL_DAYS` (reusing `REINFORCEMENT_MAX_ARRIVAL_DAYS`'s own "not worth chasing something too far away" reasoning rather than a second arbitrary bound). Docked escorts are included, not just at-sea ones - an escort reserved proactively before its convoy has even sailed must still be able to leave port once the transport gets underway.

Real distance-based prioritisation across multiple simultaneous convoys is not attempted - the lowest-ID sailing operation wins ties, the same "legal and deterministic beats optimal" precedent this pillar already uses elsewhere (`_best_construction_port()`, `_find_legal_landing()`).

## Verification

- `tests/naval_ai_escort_lifecycle_test.gd` (new): a transport operation created alongside an idle same-port fleet proactively reserves that fleet as escort in the same tick; an escort no longer co-located with its country's sailing transport is ordered to chase it (and is actually observed moving, not just recorded as deciding to); a control proves an escort already sharing a zone with its transport is never given a redundant move order; a control proves `_consider_mission_completion()` no longer abandons a temporarily-separated escort to idle as long as *some* sailing operation remains; a final case proves the escort still correctly stands down to idle once its country genuinely has nothing left to escort.
- `tests/naval_ai_test.gd`, `tests/naval_ai_trace_neutrality_test.gd` (pre-existing, re-run clean): both two-instance 215-day determinism replays against the real Iberian fixture still reproduce an identical outcome and checksum, and the trace toggle's neutrality still holds - confirming the widened tactical chain (a new `_consider_escort_follow()` step, a widened mission-completion condition, a second command sometimes submitted per `_plan_transport()` tick) introduces no nondeterminism and no trace-dependent behaviour.
- `tests/naval_ai_transport_test.gd`, `tests/naval_ai_reinforcement_homeport_transport_test.gd`, `tests/naval_ai_tactical_missions_test.gd`, `tests/naval_ai_organisation_test.gd`, `tests/naval_ai_event_replan_test.gd`, `tests/naval_destructive_edge_gate_test.gd` (pre-existing, re-run clean) - confirming no interaction with existing transport, tactical, organisation, event-replanning, or destructive-lifecycle behaviour. `naval_ai_transport_test.gd`'s own single-fleet-per-port fixture was specifically checked to confirm proactive reservation correctly finds no second fleet there and never fires, leaving that test's own `last_decision.category == "transport"` assertion unaffected.
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after every edit in this packet.

## Deliberately out of scope for this packet

- **Multi-convoy distance-based escort prioritisation** - lowest-ID tie-break only, matching this pillar's own established "legal and deterministic beats optimal" precedent rather than a new distance-scoring model.
- **Escort reservation for an already-existing (not just newly-created) transport operation** - proactive reservation only fires at creation time; an operation that was already sailing before this packet's own code ran (e.g. loaded from an old save) relies on `_consider_escort()`'s existing reactive pickup, unchanged.
- **The remaining untested "Automated verification" claim** (a measured performance budget) - now that split/transfer (FL3.3), event-triggered replanning, and escort lifecycle (this packet) have all landed and are no longer expected to change planning cost further, this is the one remaining item before FL3 is fully closed.
