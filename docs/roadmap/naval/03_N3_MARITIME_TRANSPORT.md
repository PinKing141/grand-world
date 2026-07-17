# 03 - N3 Maritime Transport

**Status:** Validation - N3.1 through N3.4 complete for every trigger reachable without N4 combat (capacity shortfall from attrition, recovery/destruction for a fleet halted mid-route, and the full embark/sail/disembark UX and save/repetition gate); battle pause, fleet retreat, and peace/extinction paths remain blocked on N4 or a pre-existing extinction-cleanup gap. Ready for N3 exit-gate review once those close. See [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) and its evidence/ folder.  
**Depends on:** N1 routes/access and N2 fleets/ships/logistics  
**Unlocks:** overseas warfare, naval interception stakes, colonisation transport hooks

## Objective

Implement one atomic, save-safe relationship between a land army and a carrier fleet from embarkation request through final disembarkation. No army may be duplicated, lost from all registries, present in two places, or permanently stranded.

## Capacity Model

- Transport capacity is defined by ship records and summed by fleet.
- Initial rule: one transport-capacity unit carries one regiment.
- Required capacity uses authoritative regiment count, not displayed strength.
- Capacity is reserved per operation before embarkation begins.
- Damaged transport capacity follows an explicit threshold rule; it cannot fluctuate unpredictably from presentation values.
- One fleet may carry multiple armies only through distinct reservations whose total never exceeds usable capacity.

## Transport Operation Record

Each operation has:

- Stable operation ID.
- Owning/issuing country.
- Army ID and carrier fleet ID.
- Origin coastal province/port and destination coastal province.
- Reserved capacity and participating transport ship IDs when exact assignment is needed.
- Current state and state start/completion day.
- Planned sea path and current carrier location.
- Interception/battle pause reference.
- Accumulated transport losses.
- Cancellation/recovery target.
- Failure/recovery reason.

The army and fleet store the operation ID as a reverse reference. Validation requires all three references to agree.

## State Machine

```text
planned
  -> embarking
  -> embarked
  -> sailing
  -> battle_paused (optional, repeatable)
  -> awaiting_disembark
  -> disembarking
  -> completed

Any active state
  -> cancelling
  -> returned / recovered / destroyed
```

### Planned

- Validate army ownership/status/location.
- Validate fleet ownership/status/location.
- Validate origin coast/port adjacency.
- Validate destination and sea route.
- Reserve capacity atomically.

### Embarking

- Army remains on land but is movement-locked and unavailable for new battle/movement orders according to the approved lock timing.
- Fleet remains docked/adjacent and cannot depart independently.
- Completion day is explicit and modified by port, army size, damage, and commander only through bounded integer rules.

### Embarked/sailing

- Army is removed from land-presence queries and references the carrier operation.
- Army does not own a fake sea province.
- Fleet movement advances normally while the operation follows the carrier.
- Ordinary army commands reject with an exact `army is embarked` reason.

### Battle paused

- Fleet interception pauses embark/disembark progress and route advancement according to battle rules.
- Army cannot participate as a normal land force.
- Transport ship losses immediately recalculate safe capacity and casualty exposure.

### Disembarking

- Destination access, control, coast adjacency, and capacity state are revalidated.
- Army remains aboard until the completion day.
- Hostile disembarkation applies a defined delay and landing penalty; it does not bypass land battle rules.

### Completed

- Army receives the destination land province exactly once.
- Movement lock and operation references clear atomically.
- Capacity reservations release.
- Event and UI report final losses and arrival.

## Commands

- `EmbarkArmyCommand` or `CreateTransportOperationCommand`.
- `SetTransportDestinationCommand` only if destination changes are allowed after embarkation.
- `CancelTransportOperationCommand`.
- `DisembarkArmyCommand` for explicit destination confirmation where needed.
- Fleet movement remains a fleet command but validates active transport constraints.

A combined player action may submit one high-level transport command, but the authoritative state machine must remain explicit and inspectable.

## Validation Rules

The operation rejects when:

- Army or fleet does not exist or has a different owner.
- Army is fighting, retreating, recovering, already transported, or movement-locked.
- Fleet is fighting, retreating, repairing, already over capacity, or cannot accept a mission.
- Origin is not a valid coast served by the fleet's port/zone.
- Destination has no legal disembark connection.
- Required transport capacity is unavailable.
- Diplomatic access or wartime rules prohibit the origin/destination.
- No sea path exists.
- The issuer lacks control of the army/fleet.

Preview uses the same validation and returns embark days, sailing days, disembark days, capacity, supplied status, and major risk warnings.

## Loss and Recovery Policy

Transport failure must be deterministic and total:

- Combat damage to non-transport ships does not reduce capacity.
- Lost/disabled transports reduce capacity immediately.
- If usable capacity falls below reserved capacity, affected armies take deterministic regiment/strength losses using stable operation and army ordering.
- Surviving capacity remains reserved; reservations cannot become negative.
- If the carrier fleet retreats, the operation follows it and targets the retreat port.
- If the carrier fleet is destroyed, survivors attempt the nearest legal friendly/accessible coast according to one bounded recovery rule.
- If no legal recovery exists, the army is explicitly destroyed with an event and war report; it never remains in an unqueryable state.
- Peace, country extinction, annexation, access loss, and port ownership changes each have explicit recovery paths.

## Interaction with Land Warfare

- Embarking armies stop contributing to siege/battle presence when the lock completes according to the approved timing.
- Embarked armies never appear in `armies_in_province`.
- Disembarkation into an empty legal province establishes land location, then normal warfare evaluates on the next defined daily step.
- Disembarkation into hostile presence produces a landing battle/penalty through the land warfare system, not a separate duplicate battle engine.
- Retreat destinations cannot route through transport automatically unless a future rule explicitly authorises it.

## UI and Feedback

- Transport assignment shows army regiments versus available capacity.
- Origin, destination, route, total days, supply, and interception danger are visible before confirmation.
- Fleet/army panels show the shared operation and current state.
- Map route distinguishes embark, sailing, and disembark segments.
- Outliner groups carrier and carried armies.
- Alerts cover insufficient transports, interrupted landing, transport losses, invalidated destination, and stranded-state recovery.
- Cancellation explains where the army will return and whether losses/costs apply.

## Save and Reload Requirements

Every state above must round-trip exactly. On load, validation checks:

- Operation -> army -> fleet reverse references.
- Reserved capacity against live transports.
- Location consistency.
- Completion days and path indexes.
- Battle pause reference.
- Country ownership and legal recovery possibility.

Malformed operations reject the save with a precise path/reference message unless a documented migration repair is safe and deterministic.

## Work Packets

- **N3A:** operation record, reservation index, commands, and invariants.
- **N3B:** embark/disembark timing and land-presence integration.
- **N3C:** carrier movement, route, access revalidation, and cancellation.
- **N3D:** interception pause, transport losses, retreat, destruction, and recovery.
- **N3E:** UI/route presentation and notifications.
- **N3F:** save corruption, replay, edge-case, and stress validation.

## Required Tests

- Capacity exact fit, insufficient capacity, multiple armies, and competing reservations.
- Cancel before/during/after embarkation.
- Save/load at every state and on every boundary day.
- Access, ownership, war, alliance, and subject changes mid-operation.
- Fleet split/merge/repair/movement rejection while carrying armies.
- Interception, retreat, partial transport loss, total carrier loss, and recovery.
- Hostile landing and normal land-battle handoff.
- Country extinction and peace during transport.
- No army appears both on land and aboard.
- No capacity goes negative or remains reserved after terminal state.
- England-France Channel operation repeats deterministically across seeds/frame rates/game speeds.

## Exit Gate

N3 is complete when an English and French army can independently cross the Channel using real transport capacity; operations can be cancelled, intercepted, damaged, rerouted, saved, and reloaded; and exhaustive invariant tests prove that no terminal or failure path leaves a duplicated, invisible, or stranded army.
