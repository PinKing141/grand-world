# 04 - N4 Naval Combat

**Status:** Validation - engagement, positioning, class-priority targeting, hull/crew/morale damage, morale collapse, sinking, disabled-ship capture, bounded pursuit, reinforcement, forced/voluntary retreat, transport pause/release, peace/extinction lifecycle, war score, reports, save/load, and stress checks pass. Final rendered and release-gate evidence remains open.
**Depends on:** N1 movement/access, N2 ships/fleets/logistics, N3 carrier-loss policy  
**Unlocks:** meaningful interception, naval war score, contested transport, blockade defence

## Objective

Resolve hostile fleet contact as deterministic daily engagements with explainable positioning, morale, hull damage, retreat, capture, and sinking. Combat must create strategic consequences without becoming a manually controlled tactical game.

## Engagement Start

An engagement may begin when:

- Hostile fleets occupy the same sea zone after movement/interception resolution.
- At least one fleet has an order/mission that permits engagement.
- War/diplomatic hostility is valid.
- Neither side is in a non-interactable terminal state.
- Detection/interception conditions succeed where the target is not automatically visible/engageable.

Start evaluation uses sorted zone, war, and fleet IDs. One fleet cannot enter two battles. Reinforcing fleets join the existing battle for their war/side rather than spawning an overlapping battle.

## Detection and Interception

The first abstraction is strategic, not hidden-unit simulation. Detection score may use:

- Light-ship/scouting contribution.
- Admiral manoeuvre.
- Fleet speed and size.
- Sea-zone class.
- Mission posture.
- Target transport burden and damage.
- Seeded bounded roll when uncertainty is approved.

Transport, blockade, patrol, intercept, protect, avoid, return-to-port, and repair missions define whether a fleet seeks or avoids contact. The reason trace records every score and threshold.

## Battle Record

An active naval battle stores:

- Stable battle ID, war ID, sea-zone ID, and start day.
- Attacker/defender leaders and sorted fleet IDs.
- Side country membership.
- Current round and minimum-retreat day.
- Initial and current ship/strength/morale totals.
- Positioning basis points and modifiers for both sides.
- Engagement width/active ship assignment.
- Per-round losses, captures, sunk ships, and withdrawn ships.
- Reinforcement history.
- Retreat requests/destinations.
- Outcome, winning side, war-score value, and report summary.

Ships retain their own hull/crew state. Battle summaries cache totals but never replace ship records as authority.

## Combat Phases per Day

1. Validate participants and remove destroyed/invalid references.
2. Accept eligible reinforcements in stable order.
3. Calculate side positioning and engagement slots.
4. Select active ships and targets by stable class/priority/ID rules.
5. Resolve attacker and defender fire using pre-round snapshots where simultaneous damage is intended.
6. Apply hull, sailor/crew, and morale losses.
7. Resolve disabled, captured, sunk, and withdrawn ships.
8. Evaluate side morale collapse and legal retreat.
9. Update war score and emit one round event.
10. End battle or persist the next-round state.

The ordering must be documented precisely enough that two implementations cannot produce different results.

## Positioning

Positioning is the main fleet-composition control. It uses integer basis points and may include:

- Admiral manoeuvre and naval traits.
- Fleet speed relative to opponent.
- Light-ship scouting contribution.
- Fleet-size/coordination penalty.
- Damaged or undersupplied penalty.
- Sea-zone coastal/inland/open classification.
- Mission/interception initiative.
- Galley suitability.
- Transport burden.
- Deterministic bounded roll.

Positioning controls how many appropriate ships engage effectively, target quality, and damage efficiency. The UI must show the top positive/negative sources.

## Ship-Class Roles

- **Heavy:** highest general battle power and durability; expensive, slower, and supply-heavy.
- **Light:** scouting, pursuit, interception, screening, and later trade protection; vulnerable to concentrated heavy fire.
- **Galley:** efficient coastal/inland combat and cost; reduced open-ocean performance.
- **Transport:** carries armies and is screened behind combat ships where possible; weak combat and high strategic loss exposure.

Variants modify values but preserve these family roles. No class receives an undocumented hard-coded exception outside definitions/modifier functions.

## Damage Model

All arithmetic is integer/fixed-point. A conceptual damage trace includes:

```text
base class attack
x current hull/crew effectiveness
x maintenance and morale effectiveness
x positioning/targeting effectiveness
x commander and terrain modifiers
x deterministic roll
/ target defence
= bounded hull, crew, and morale damage
```

Requirements:

- Damage is clamped and cannot heal or underflow.
- One roll stream is namespaced by battle/round/side/ship or another collision-safe identity.
- Sinking occurs at zero hull or a defined catastrophic result.
- Disabled/withdrawn ships stop attacking.
- Morale collapse can end a side before every ship sinks.
- Carried armies receive transport-loss consequences through N3 after ship results commit.

## Capture

Capture is possible only under explicit conditions such as disabled hull, collapsed morale, winning-side presence, and available control. Captured ships:

- Change owner atomically.
- Leave the losing fleet.
- Join a deterministic captured/reserve fleet or named winning fleet.
- Record original owner and capture battle.
- Enter damaged/low-morale state.
- Affect war score and reports.
- Do not immediately fight again in the same round unless explicitly allowed.

Transport capture while carrying armies follows the approved prisoner/destruction/recovery rule; it cannot silently transfer an enemy army as a normal friendly unit.

## Retreat and Pursuit

- Retreat is unavailable until a minimum battle duration unless a side is destroyed/collapsed.
- Player/AI may request retreat; command validates leader/side/fleet ownership.
- Destination is the nearest legal, supplied port or safe sea zone according to one policy.
- All retreat paths use N1 deterministic pathfinding.
- Retreating fleets are movement-locked and cannot start missions/transport operations.
- Pursuit damage, if included, is one bounded resolution step rather than an unbounded chase simulation.
- A fleet with no legal retreat resolves through explicit surrender/destruction rules.

## Reinforcement

- Friendly fleets entering the battle zone may reinforce if war side, mission, and status permit.
- Reinforcement day and side are recorded.
- Newly arrived ships enter positioning/active selection on the defined next phase, not midway through already-calculated damage.
- Fleets carrying armies retain their transport reference.
- Battle membership reverse indexes update atomically.

## War Integration

Naval combat contributes:

- Battle war score based on relative losses and strategic value.
- Captured/sunk ship statistics.
- Transport/army losses.
- Optional prestige/tradition hooks only if their owning systems approve them.
- Battle report retained in the war registry or bounded history store.

Peace immediately ends hostile engagement according to one safe disengagement rule and clears battle locks without healing or resurrecting ships.

## Player Feedback

- Naval battle marker at the sea-zone anchor.
- Battle panel with participants, commanders, class counts, positioning, morale, hull, reserves, daily losses, captures, and sunk ships.
- Tooltips explaining major modifiers and target/class roles.
- Retreat control with earliest legal date and destination explanation.
- Final report comparing starting/surviving/captured/sunk totals and transport casualties.
- Notifications grouped by battle rather than one per ship/round.

## AI Requirements Introduced in N4

- Estimate effective friendly/enemy power with uncertainty margin.
- Reinforce valuable winnable battles.
- Avoid or retreat from overwhelming enemies.
- Value transport survival above low-value interception.
- Return damaged survivors to a legal repair port.
- Record candidate scores and rejection reasons.

Full mission planning is completed in N6.

## Work Packets

- **N4A:** battle records, engagement start, reverse indexes, and save validation.
- **N4B:** positioning, active-ship selection, deterministic damage, and class roles.
- **N4C:** morale, sinking, capture, retreat, pursuit, and reinforcement.
- **N4D:** transport-loss, war-score, peace, commander, and event integration.
- **N4E:** marker, battle panel, final report, and AI-safe evaluation API.
- **N4F:** balance fixtures, replay, malformed-save, stress, and performance validation.

## Required Tests

- Identical result from identical seed/order/save state.
- Different frame rates and game speeds do not alter rounds.
- Stable targeting and reinforcement ties.
- Heavy/light/galley/transport roles produce expected directional outcomes.
- Coastal versus open-ocean galley modifiers apply once and explain correctly.
- Morale defeat, total sinking, capture, voluntary retreat, forced retreat, and no-retreat outcomes.
- Admiral death/removal during battle.
- Peace, alliance change, country extinction, fleet split rejection, and save/load mid-round.
- Partial and total transport losses invoke N3 exactly once.
- No ship exists in two fleets/battles or remains in a completed battle.
- Large multi-fleet battle meets approved daily budget.

## Exit Gate

N4 is complete when the Channel fixture can detect/intercept transports, reinforce, resolve multiple deterministic battle outcomes, retreat to legal ports, report captured/sunk ships and army losses, update war score, and round-trip a mid-battle save without checksum drift or invalid membership.
