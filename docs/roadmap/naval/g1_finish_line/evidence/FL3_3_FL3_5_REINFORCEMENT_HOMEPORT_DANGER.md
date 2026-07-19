# FL3.3 / FL3.5 - Reinforcement, Home Port, and Danger-Aware Transport

**Status:** Complete for the scoped slices below. Targeted tests pass (see Verification).
**Satisfies:** FL3.3's reinforcement bullet in full, FL3.3's home-port bullet for its one mechanically real case, and FL3.5's "acceptable danger" bullet - all recorded in [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md).

## Reinforcement (FL3.3)

"Compare reinforcement arrival time and value before joining a battle" turned out to need no new "join battle" command at all: `NavalCombatSystem._join_reinforcements()` already scans every active battle daily and automatically adds any fleet that happens to share its zone to that battle's side, regardless of how the fleet got there - a coincidental arrival and an ordered one are treated identically. `_consider_reinforcement()`'s only job is the order itself: send an idle, uncommitted fleet (docked or at sea, not already on a mission or mid-transport) toward an active battle its own country has a side in, gated by two checks matching the roadmap's own two-part framing:

- **Value**: only when that side's summed power is currently *less* than the opposing side's (`_side_power()`, the same comparison `_consider_retreat()` already uses) - reinforcing a side already winning comfortably is not worth committing a fleet for.
- **Arrival time**: only when a legal route exists within `REINFORCEMENT_MAX_ARRIVAL_DAYS` (10) - a fleet weeks away is fighting a different war by the time it gets there.

Slotted into `_plan_tactical()` right after `_consider_mission_completion()` and before escort/intercept - an active battle outcome is treated as more urgent than routine positioning duty, but less urgent than a fleet's own survival (retreat/repair still come first).

## Home port (FL3.3)

**A real finding, not assumed**: `home_port_id` has no downstream mechanical effect anywhere in the simulation today. Repair and supply eligibility already key off a fleet's *current* location via `NavalAccessPolicy.can_base()`, not its declared home port - confirmed by grep, no repair/supply/morale system reads `home_port_id` at all. Building the roadmap's full "access, repair, supply, threat, objective distance" home-port-selection model would be tuning a field nothing downstream actually reads yet.

What *is* real: a fleet's home-port record can go stale (the port captured, access revoked) and then stay silently wrong forever, since nothing previously reassigned it. `_consider_home_port()` closes that one case - if a fleet's current home port no longer passes `can_base()`, it is reassigned to the country's own lowest-sorted-ID remaining port (the same "legal and deterministic beats optimal" tie-break `_best_construction_port()` already established), or the rejection is recorded if no port remains at all. This keeps the record honest without inventing selection criteria for a field with no other consumer.

## Danger-aware transport routing (FL3.5)

"Confirm... acceptable danger before reserving." `_plan_transport()` now checks the sea route it already computes (previously only checked for existence, the route itself was discarded) against `NavalThreatMap`: any non-port zone along the path reading above `THREATENED_ZONE_THREAT_THRESHOLD` (the same bound `_review_posture()` already uses for "worth taking seriously," not a second invented danger scale) rejects the candidate and records why, rather than sailing an unarmed transport through blind.

**Two related limitations found and deliberately left open, not silently dropped:**
- **Proactive escort reservation** is still not attempted - FL3.4's `_consider_escort()` reactively picks up escort duty for a fleet that happens to already share a zone with a sailing transport, but nothing here goes looking for an escort *in advance* of departure.
- **Escort does not follow the voyage.** Discovered while scoping this bullet: an escort fleet assigned via `_consider_escort()` does not actually move with the transport it is guarding - `SetFleetMissionCommand` only tags the fleet, nothing makes it travel the transport's route. Once the transport sails on to its next leg, `_consider_mission_completion()` correctly notices the transport is no longer in the escort's zone and stands the escort down. This is a real, distinct gap from proactive reservation - escort as built is "same-zone co-location," not "accompanies the whole crossing." Fixing it would mean giving an escorting fleet movement orders synchronized to the transport's own route, a separate, larger mechanism.

## Verification

- `tests/naval_ai_reinforcement_homeport_transport_test.gd` (new): a docked reserve fleet ordered to reinforce an active battle its own side is losing, with a control proving no order is issued when that side is already stronger; a fleet's home port reassigned to a still-owned port after the original loses basing rights (capture), with a control proving no reassignment when the home port is still legal; and a transport candidate correctly rejected (no operation created) when its only legal route crosses a zone a strong hostile fleet occupies.
- All seven pre-existing naval-AI test files (`naval_ai_test`, `naval_ai_threat_test`, `naval_ai_organisation_test`, `naval_ai_transport_test`, `naval_threat_map_test`, `naval_ai_strategic_posture_test`, `naval_ai_tactical_missions_test`) re-run clean, including `naval_ai_test.gd`'s own two-instance 215-day determinism replay.
- **A real bug was found and fixed during this packet's own verification, not before**: `_consider_reinforcement()` used `MoveFleetCommandScript` without preloading it, a hard parse error that broke `NavalAISystem` compilation entirely. Every dependent test failed or partially executed against a null object as a result - some still printed a misleading "passed" at the end (Godot's headless script execution logs a hard script error and continues past it rather than halting, the same "quit() doesn't stop the calling coroutine" class of surprise this project has hit before with `_require()`). Fixed by adding the missing `const MoveFleetCommandScript = preload(...)`; every test was then re-run and its full output grepped for `SCRIPT ERROR`/`Parse Error`/`Nonexistent function`, not just checked for a trailing "passed" line, to confirm the fix was real and not another silent false pass.
- Registered in `tools/testing/run_all_tests.py`.
- Broader regression (`naval_battle_blockade_stress_smoke`, `naval_destructive_edge_gate_test`, `naval_hud_integration_smoke`) and the 100-seed Channel release gate re-run clean.

## A process note worth recording

Every test file in this project that accumulates failures into an array (`_check()`) rather than halting immediately (`_require()`) is vulnerable to the same false-pass risk this packet's own bug exposed: a hard script error (a bad reference, a null call) is logged by Godot and execution continues past it in headless mode, so a test can print "passed" at the end even though it never actually ran its real assertions. Grepping full test output for `SCRIPT ERROR`/`Parse Error`/`Nonexistent function`/`Invalid call`/`Invalid access` - not just checking for the trailing pass message - is now this session's standard verification step going forward, not just for this packet.
