# N4 - Reinforcement and Voluntary Retreat

**Status:** Recorded - the second N4 round, closing two items [N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md](N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md) explicitly deferred: reinforcement and voluntary retreat. Positioning breakdown, morale, capture, peace/lifecycle interaction, and UX/gate remain open.  
**Satisfies:** the remaining reinforcement item in [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N4.1, and the voluntary-retreat item in N4.3  
**Scope:** friendly fleets joining an in-progress battle, and a player/AI-issued command to withdraw a still-fighting fleet before it is defeated. Capture and the full positioning/morale model are a separate, larger design question left for a later round - see the first evidence doc's reasoning for why sinking/forced-retreat, not these, were the minimum needed to close N4's first packet.

## Why this pair, and why now

The first N4 round closed the loop a battle needs to *start and end on its own*. These two items are the natural next increment: reinforcement is what happens when the world keeps moving fleets around while a battle is already running (otherwise a fleet arriving mid-fight just sits uselessly next to a battle it can see but never joins), and voluntary retreat is the other half of "retreat" that forced-retreat-on-defeat alone doesn't cover - 04_N4 explicitly separates them ("Player/AI may request retreat" vs. the automatic loser's-survivors retreat already built). Both are small, self-contained additions to the existing `NavalCombatSystem`/battle-record shape - neither needed a new registry or a new state machine, unlike capture (which needs ownership-transfer and a "control" concept not yet modeled) or morale (which needs a new battle-morale field nothing currently tracks). That made them the right size for one more round before those larger items.

## Architectural choices

**Reinforcement mirrors `WarfareSystem._join_reinforcements()` exactly, including its place in the daily tick order.** `NavalCombatSystem.advance_day()` now calls `_join_reinforcements()` before `_resolve_battles()`, the identical ordering land combat already uses, so a fleet that arrives today is folded into today's positioning before any damage is calculated - "Newly arrived ships enter positioning/active selection on the defined next phase, not midway through already-calculated damage" (04_N4 "Reinforcement"). The eligibility checks are the same ones `_start_battles()` already applies to a fresh engagement (no existing battle reference, not already in battle/retreating status, an active war between the reinforcing country and one of the battle's existing sides) - reinforcement is "the same engagement rule, applied to an existing battle" rather than a second, divergent rule.

**Voluntary retreat is a command, not a system-driven check, because it is fundamentally a player/AI decision, not a world-state consequence.** Every other piece of `NavalCombatSystem` runs unconditionally inside `advance_day()`; `RequestFleetRetreatCommand` is the one naval-combat action that goes through the normal command `validate()`/`apply()` gate, the same as every other player-issued naval order this roadmap has built (`MoveFleetCommand`, `CreateTransportOperationCommand`, etc.). `NavalCombatSystem.withdraw_fleet()` is the reusable mutation the command calls into - a public, non-underscore-prefixed function, the one exception to this file's otherwise-private helper functions, because it is meant to be called from outside the file (mirroring how `FleetSystem.move_ships()` and `TransportSystem`'s public accessors are the intentional entry points into their own systems).

**Withdrawing the last fleet on a side ends the battle exactly like a combat defeat, not a special "aborted" outcome.** `withdraw_fleet()` removes the fleet from its side's list, then checks whether that side is now empty; if so, it calls the same `_finish_battle()` a hull-based defeat would call, with the withdrawing side losing. This was a deliberate choice, not an oversight: 04_N4 does not describe a third "abandoned" battle outcome distinct from attacker/defender winning, and treating a full withdrawal as anything other than a loss would let a losing side dodge war-score consequences simply by retreating one tick before defeat - "a withdrawal is still a loss for war-score purposes."

**The minimum-retreat-round gate is enforced once, in `validate()`, using the battle's own `round` counter - no new timer field was added.** 04_N4: "Retreat is unavailable until a minimum battle duration unless a side is destroyed/collapsed." The "unless destroyed/collapsed" exception needs no special-casing here, because a side that has actually collapsed is handled entirely by the existing forced-retreat path in `_finish_battle()` - `RequestFleetRetreatCommand` only exists to let a *still-fighting* fleet leave early, so the exception clause doesn't intersect with this command's own scope at all.

## What was built

- `NavalCombatSystem`: `_join_reinforcements()`; `MIN_RETREAT_ROUNDS` constant; `withdraw_fleet()` (public).
- `scripts/simulation/commands/request_fleet_retreat_command.gd` (new).
- One new `SimulationEventBus` signal: `naval_battle_reinforced`.
- `simulation_controller.gd`: `request_fleet_retreat()` wrapper method, following the existing pattern.
- `tests/naval_combat_test.gd` extended with reinforcement and voluntary-retreat coverage (not a new file - the existing fixtures, scheduler helper, and war setup were already in place and needed no changes).

## Results (verified via `naval_combat_test.gd`, exit 0, no errors)

- A friendly fleet placed at an already-active battle's location joins that exact battle (not a new, overlapping one) on the next tick, correctly attributed to its side, with battle status applied.
- `RequestFleetRetreatCommand` is rejected before `MIN_RETREAT_ROUNDS` and accepted once that threshold is reached.
- Withdrawing the sole attacking fleet clears its battle reference immediately, removes it from the battle's side list, and ends the battle with the defender recorded as the winner - the same outcome shape a hull-based defeat would produce.
- No regression: re-ran all 41 Godot phase/core/naval tests after this round's changes - 40/41 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4 evidence doc so far.

## Deliberately simple / deferred

Unchanged from the first N4 evidence doc except for the two items this round closed (reinforcement, voluntary retreat). Still open: full positioning breakdown and named modifier sources, morale-based early collapse, capture, pursuit, peace/commander/country-lifecycle interaction during an active battle, all UX (battle marker/panel/report/retreat control), and naval-battle-scale stress/performance evidence.
