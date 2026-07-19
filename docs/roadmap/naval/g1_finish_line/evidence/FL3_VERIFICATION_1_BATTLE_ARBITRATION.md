# FL3 Verification 1/4 - Same-Zone Player/AI Battle Arbitration

**Status:** Complete. Targeted test passes (see Verification). A related, previously-undiscovered gap was found and recorded, not fixed here (see "A real gap found while verifying this").
**Satisfies:** the first of [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md)'s four untested "Automated verification" roadmap claims - "AI and player targeting the same sea zone still produces one authoritative battle."

## What was verified, and how

`NavalCombatSystem._start_battles()` runs exactly once per scheduler day, off a single deterministic full-`fleet_registry` scan (`naval_combat_system.gd:145`) - it groups every fleet by its current `location_id`, then forms at most one battle per zone per day, entirely independent of *how* any fleet arrived there. Reasoning about the code suggested this claim was already true by construction (there is no code path where "the player's fleet arriving" and "the AI's fleet arriving" are treated as two separate battle-formation events), but this session's own established standard is to prove a claim through the real pipeline rather than trust the reasoning alone - `tests/naval_ai_player_battle_arbitration_test.gd` does that:

- A player-issued `MoveFleetCommand` is submitted directly (`scheduler.submit()`), the same call `simulation_controller.move_fleet()` makes for a real UI action.
- An AI-issued `MoveFleetCommand` targeting the *same* destination zone is submitted through `NavalAISystem._submit()` - the real function every AI decision (including reinforcement's own `MoveFleetCommand` usage) goes through, not a synthetic bypass.
- Both commands land in the scheduler's command queue before any day advances, so both are genuinely "today's" commands regardless of source.
- The scheduler is then advanced day by day - not a fixed number of days, and not assuming simultaneous arrival - until both fleets are independently observed to have reached the target zone via the real `FleetMovementSystem`. In the run this evidence is based on, the two fleets (a 1-hop sail each, from different origin ports) happened to arrive two days apart, which is itself part of what the test proves: arrival order and timing do not matter to the outcome.
- Once both fleets are co-located and at war, exactly one `naval_battle_registry` entry exists, at the correct zone and war, with the two fleets correctly split onto opposing sides and both referencing the identical `battle_id` - not two independently-formed records that happen to coexist.

## A real gap found while verifying this - recorded, not fixed

While tracing exactly how `_start_battles()` picks a war for a zone, a genuine, previously-undocumented limitation surfaced: the function picks **one** `war_id` for an entire zone (the first pairwise war match found among that zone's candidate fleets, scanned in fleet-ID order) and only ever sorts candidates into that single war's attacker/defender sides. If three or more countries' fleets share a zone across **two different active wars** at once (e.g. ENG-vs-FRA and ENG-vs-SCO both active, with ENG, FRA, and SCO fleets all present), the country whose war was *not* selected is silently excluded from battle formation entirely that day - not queued, not retried, not reported as a rejected candidate, simply skipped. This is a real, reachable simulation-layer gap (not a naval-AI-planning one, and not the same gap as the player/AI arbitration bullet this packet closes), but it is a genuinely separate, larger fix - `_start_battles()` would need to group candidates by *which* war they belong to and potentially form more than one battle per zone per day, not a small change. Recorded here as a known, deliberately deferred gap rather than expanded into scope this packet did not set out to cover.

## Verification

- `tests/naval_ai_player_battle_arbitration_test.gd` (new): the full scenario described above, driven entirely through the real command/scheduler/`FleetMovementSystem`/`NavalCombatSystem` pipeline - no direct registry manipulation to force co-location.
- Registered in `tools/testing/run_all_tests.py`.

## Deliberately out of scope for this packet

- **Fixing the multi-simultaneous-war-in-one-zone gap** found above - a real, separate, larger fix; recorded for a future packet rather than expanded into here.
- **Verification packets 2-4** (the full AI recovery matrix, trace-neutrality, a measured performance budget) - each its own tracked packet, not attempted here.
