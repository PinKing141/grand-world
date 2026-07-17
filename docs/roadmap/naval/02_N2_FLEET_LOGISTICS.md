# 02 - N2 Fleet Logistics

**Status:** Validation - N2.1 through N2.5 complete except export evidence, which is blocked on Godot export templates not being installed in this environment (attempted; confirmed the exact blocker; not something this roadmap track can resolve on its own). Ready for N2 exit-gate review once that's unblocked. See [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) and its evidence/ folder.  
**Depends on:** N1 graph/access/range APIs and approved state contracts (satisfied - N1 complete)  
**Unlocks:** transport and naval combat

## Objective

Create persistent fleets and ships that countries can construct, organise, move, base, maintain, damage, repair, and save. N2 proves the peacetime naval loop before armies or combat depend on it.

## Fleet and Ship Model

Fleets are stable containers and order recipients. Ships are stable individual records.

A fleet owns:

- Identity, owner, display name, home port, and current location.
- Sorted ship membership.
- Admiral assignment.
- Movement path/timing and status.
- Mission, maintenance posture, morale, supply, repair, and battle/transport references.
- Cached aggregate strength, speed, blockade, transport, and maintenance values derived from ships.

A ship owns:

- Stable ship ID and owner.
- Class/variant definition ID.
- Fleet membership.
- Construction/completion date and optional name.
- Hull strength, crew/sailor strength, and morale contribution.
- Captured-from provenance where applicable.
- Repair and disabled state.

No authoritative aggregate may disagree with the underlying ships. Aggregates are recomputed in stable ship-ID order when membership or damage changes.

## Ship Definitions

Versioned external definitions must support:

- Family: heavy, light, galley, or transport.
- Display name and localisation key.
- Unlock/start/end date and technology requirements.
- Purchase cost and construction days.
- Sailor cost and monthly maintenance.
- Maximum hull and combat morale.
- Attack, defence, speed, positioning weight, engagement width, and retreat contribution.
- Blockade power, transport capacity, supply weight, and repair rate.
- Coastal/inland-sea modifiers.
- Upgrade/successor ID without mutating existing ships.
- Content provenance and review status.

Definitions reject negative values, missing successors, invalid technology tracks, circular upgrades, unknown family names, and impossible date ranges.

## Country Naval Economy

Country runtime state gains:

- Current sailors and maximum sailors.
- Monthly sailor recovery and displayed sources.
- Naval maintenance basis points.
- Naval force guidance/soft-limit inputs if approved during balance.
- Monthly naval expense breakdown.
- Optional repair and basing expenses as separate ledger lines.

Sailors derive from eligible coastal development, ports, buildings, technology, government, ideas, and modifiers. The first slice uses a simple explainable formula; later content extends modifiers without changing the resource identity.

Naval expenses must reconcile exactly:

```text
ship maintenance
+ active repair
+ fleet basing fees (when implemented)
+ construction payments according to the chosen queue policy
= displayed naval expense
```

Low maintenance reduces expense but lowers morale, sailor reinforcement, repair readiness, and mission effectiveness. Raising maintenance cannot instantly restore morale.

## Ship Construction

Construction is an authoritative queue record with:

- Construction ID.
- Country, port, ship definition, and quantity/index.
- Start and completion days.
- Amount paid/refundable.
- Reserved sailors if the approved rule reserves them at start.
- Status and exact blocked reason.

Validation requires:

- Country owns or legally controls/uses the port according to construction policy.
- Port is enabled and has the required shipyard level.
- Ship definition is unlocked on the scheduled day.
- Treasury and sailors satisfy the cost policy.
- Queue/capacity limit is not exceeded.
- Province is not in a state that forbids construction.

On completion, the ship joins a deterministic port reserve fleet or a specified compatible fleet. IDs are allocated from stable counters, never object instance IDs.

Cancellation defines exact refund and sailor-release rules. Ownership/control changes pause, transfer, cancel, or seize queues through one documented policy; they must not silently delete money or duplicate ships.

## Fleet Organisation

Commands will support:

- Create fleet from eligible ships at one location.
- Rename fleet as presentation state if names are saved.
- Merge co-located friendly fleets.
- Split selected ships into a new fleet.
- Transfer selected ships between co-located fleets.
- Disband/sell/scuttle ships only through an explicit destructive action.
- Set home port.
- Set maintenance posture or country-wide naval maintenance.
- Assign/remove admiral.

Invariants:

- Every active ship belongs to exactly one fleet or an explicit port reserve.
- A ship cannot appear in two membership lists.
- Fleets cannot merge across locations, owners, battles, or incompatible transport reservations.
- A fleet with no ships is removed or converted to a clearly defined empty reserve state in the same atomic operation.
- Captured ships change owner, fleet, and maintenance accounting together.

## Movement

Movement mirrors the proven army arrival-day model:

- Validate one route from the N1 authority.
- Store destination, remaining path, path index, start day, next arrival day, and progress.
- Revalidate the next leg when access/topology-relevant state changes.
- Emit ordered, moved, completed, blocked, and cancelled events.
- Presentation interpolates only; it never advances location.

Fleet speed is derived from the slowest effective ship plus approved commander/mission modifiers. Splitting a fleet can change future leg timing but cannot rewrite a leg already movement-locked without a defined cancellation.

## Basing, Supply, Attrition, and Repair

### Basing

- Home port must be owned or supported by enduring fleet basing rights.
- Temporary docking may use a wider access rule than home basing.
- Loss of basing rights triggers a grace/forced-departure policy, not deletion.

### Supply

- Every at-sea fleet queries nearest valid supply port and range cost.
- Supplied/unsupplied state and reason are saved or reproducibly derived.
- Missions may refuse to start outside range even when direct movement remains possible.

### Attrition

- Checked on an explicit interval using integer values and a named RNG stream only where variance is approved.
- Depends on time at sea, supply status, sea class, fleet damage, and technology.
- Cannot reduce hull or sailors below defined bounds.
- Produces event/notification thresholds rather than daily spam.

### Repair and reinforcement

- Requires a legal repair port and a docked fleet.
- Consumes time, sailors, and money according to definitions.
- Stable ship-ID order decides allocation when resources are insufficient.
- Player may prioritise ships/fleets if that control is approved; otherwise allocation rules are explicit.
- Repair never resurrects sunk or scuttled ships.

## Admirals

- Admirals reference existing character IDs.
- Character must be alive, belong to/serve the country, and satisfy role rules.
- A character cannot command an army and fleet simultaneously unless the character design explicitly changes.
- Death, dismissal, country extinction, and save migration clear invalid assignments.
- Martial and approved traits contribute through one naval modifier function; UI shows the sources.

## Commands and Events

Minimum commands:

- `ConstructShipCommand`, `CancelShipConstructionCommand`.
- `CreateFleetCommand`, `MergeFleetsCommand`, `SplitFleetCommand`, `TransferShipsCommand`.
- `MoveFleetCommand`, `CancelFleetMovementCommand`.
- `SetFleetMissionCommand`, `SetFleetHomePortCommand`.
- `SetNavalMaintenanceCommand`.
- `AssignAdmiralCommand`.
- Explicit repair/scuttle commands if repair is not automatic.

Minimum events include construction start/cancel/complete, fleet organisation/location/status changes, supply changes, repair progress/completion, attrition losses, maintenance changes, and admiral assignment.

## N2 Player Surface

- Minimal naval tab and fleet list.
- Port ship-construction list with costs, unlocks, time, and rejection explanations.
- Fleet composition, speed, range, supply, maintenance, morale, hull, and repair status.
- Split/merge/transfer controls.
- Move-route preview and expected arrival.
- Home-port and admiral controls.
- Outliner entries and idle/damaged/unsupplied alerts.

Final styling waits for N6, but every action must be operable and testable.

## Work Packets

- **N2A:** definition loader/validator and representative four-family data.
- **N2B:** save registries, reverse indexes, aggregates, migration, checksum.
- **N2C:** ship construction/cancellation and naval economy.
- **N2D:** fleet organisation, movement, access, basing, and supply.
- **N2E:** attrition, repair, reinforcement, and admiral lifecycle.
- **N2F:** minimal UI, AI-safe APIs, integration tests, and performance capture.

## Required Tests

- Exact construction/cancellation accounting and completion day.
- Unlock, port, treasury, sailor, ownership, and queue rejection paths.
- No duplicate/orphan ships after split, merge, transfer, capture fixture, or save/load.
- Movement deterministic across frame rates and speeds.
- Access loss and home-port loss recover safely.
- Supply range cache invalidates correctly.
- Repair/attrition never exceed bounds or disagree with ledger totals.
- Admiral lifecycle and exclusivity remain valid.
- Old schema migration produces valid empty naval state.
- New campaign starting fleets validate.
- Full-world idle and active fleet stress meets N2 budgets.

## Exit Gate

N2 is complete when England, France, Portugal, Castile, and Aragon can begin with or construct representative fleets; those fleets can organise, move, base, consume maintenance, lose supply, take attrition, repair, assign admirals, and round-trip saves without invalid references or accounting differences.
