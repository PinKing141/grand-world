# Phase 5 — Warfare, Occupation, Peace, and Diplomacy

## Mission

Complete the core conflict loop from diplomatic intent to war declaration, movement, battle, occupation, war score, and negotiated peace.

## Production Gate

War Loop Gate.

## Player Outcome

The player can form a relationship, declare a valid war, move armies, fight battles, occupy provinces, negotiate peace, and legally transfer territory.

## Entry Conditions

- Economy Loop Gate passes.
- Armies can move deterministically.
- Countries can recruit and maintain forces.
- Command, event, save, and notification frameworks are stable.

## Major Deliverables

### Diplomatic Relationships

Initial relationship state:

- Bilateral opinion.
- Alliance.
- Rivalry placeholder.
- Truce expiration.
- Military access.
- War status.
- Subject relationship placeholder.

### Diplomatic Commands

- ImproveRelationsCommand.
- FormAllianceCommand.
- BreakAllianceCommand.
- RequestMilitaryAccessCommand.
- GrantMilitaryAccessCommand.
- DeclareWarCommand.
- OfferPeaceCommand.
- AcceptPeaceCommand.

### War Goals

Initial war goal:

- Conquer a specific province.

Required rules:

- Attacker and defender.
- Valid target.
- Truce check.
- Access and participant setup.
- Ticking war score.
- Peace-term eligibility.

### WarState

Track:

- War ID and name.
- Start date.
- Attacker leader.
- Defender leader.
- Participants.
- War goal.
- Battles.
- Occupied provinces.
- Battle score.
- Occupation score.
- Ticking score.
- Current total war score.

### Battle Prototype

Initial factors:

- Soldiers.
- Morale.
- Attack.
- Defence.
- Terrain.
- Commander placeholder.
- Seeded combat roll.
- Reinforcement.
- Retreat threshold.

The first battle system must be deterministic, explainable, and debuggable rather than historically exhaustive.

### Battle Lifecycle

~~~text
Opposing armies meet
→ Battle begins
→ Daily combat rounds
→ Casualties and morale loss
→ One side retreats or is destroyed
→ Battle result contributes war score
→ Survivors resume movement after recovery
~~~

### Occupation

- Owner remains unchanged.
- Controller changes after occupation.
- Occupation progress.
- Army requirement.
- Fort placeholder.
- Occupation map overlay.
- Economic penalty.

### Siege Prototype

Initial values:

- Fort level.
- Garrison.
- Required besieging strength.
- Siege progress.
- Seeded periodic roll.
- Breach placeholder.

### Peace Deals

Initial terms:

- Transfer occupied war-goal province.
- Transfer additional eligible province.
- Money payment.
- White peace.

Each term defines:

- War-score cost.
- Eligibility.
- AI value hook.
- State changes.
- Notification and history entry.

### Diplomatic and War UI

- Country diplomacy panel.
- Relationship summary.
- Declare-war flow.
- War-goal selection.
- War overview.
- Battle result.
- Peace negotiation.
- Truce display.

### Map Modes and Overlays

- Diplomatic relations.
- War participants.
- Occupation.
- War goal.
- Military access.

### Save Integration

Save:

- Relationships.
- Active wars.
- Participants.
- Battles.
- Army morale and casualties.
- Occupations.
- Sieges.
- Truces.
- Peace offers.

## Rules of Authority

- Armies may change controller through occupation.
- Only a peace settlement or explicit scripted effect changes legal owner.
- UI and AI submit the same diplomatic commands.
- War score informs peace but does not automatically transfer provinces.

## Acceptance Criteria

- A valid war can be declared.
- Invalid war declarations explain the blocking rule.
- Opposing armies in one province begin a battle.
- Combat produces deterministic results from the same inputs and seed.
- Defeated armies retreat according to rules.
- Provinces can become occupied without changing legal owner.
- Peace can transfer legal ownership.
- Truces are created and expire on the correct day.
- Saving and loading during war preserves battles, occupations, armies, and score.
- The campaign can complete repeated wars without stale participants or references.

## Performance Gates

- Battles update on daily ticks, not every rendered frame.
- War-score totals are cached and updated from events.
- Map overlays update only when relevant state changes.
- Battle debug data can be disabled in normal builds.

## QA Focus

- Simultaneous army arrival.
- Reinforcement during battle.
- Army destruction.
- Country annexation during another war.
- Alliance breaking during war.
- Separate peace.
- Leader leaving a war.
- Province transferred while occupied.
- Save/load during a battle round.
- Truce expiration and immediate declaration.

## Primary Risks

- Diplomacy scope expands faster than the core war loop.
- Battle formulas become opaque.
- Owner/controller confusion causes state corruption.
- Peace deals create invalid country and province indexes.
- Multi-country wars multiply edge cases.

## Scope Controls

The phase proves one complete war loop. Defer:

- Naval battles.
- Complex coalition wars.
- Dozens of war-goal types.
- Detailed combat width and unit composition.
- Advanced fort zones of control.
- Aggressive expansion networks.
- Full subject diplomacy.

