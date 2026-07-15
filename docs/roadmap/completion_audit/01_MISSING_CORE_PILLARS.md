# 01 — Missing Core Pillars

These are P0 systems. A player will immediately notice their absence in a global 1444 campaign, and later content depends on their schemas. They must be designed before unrestricted Phase 9 content production.

## Pillar A — Naval Warfare and Maritime Transport

### Current state

The project recognises coasts, sea connections, straits and the `naval_supplies` trade good, but armies that require transport cannot cross water. There are no usable fleets, transport capacity, naval battles, blockades, repairs or naval AI.

### Minimum 1.0 scope

- Fleet entity, owner, location, commander, composition, morale, strength and maintenance.
- Ship classes for heavy ships, light ships, galleys and transports, with date-appropriate unlock data.
- Port and sea-zone graph, embark/disembark rules and transport capacity.
- Naval movement orders and interception opportunities.
- Naval combat with positioning, morale, retreat, losses and capture/sinking outcomes.
- Blockade power, coastal siege effect and economic pressure.
- Repair, reinforcement, basing rights and naval access.
- Naval attrition and supply range appropriate to the chosen abstraction.
- Player UI for fleets, ship construction, transport assignment, combat and blockades.
- AI capable of building fleets, protecting coasts, transporting armies and avoiding suicidal engagements.
- Save/load, deterministic replay, soak and stress coverage.

### Production slices

1. **N1 — Maritime graph authority:** ports, sea zones, ownership/access and deterministic pathfinding.
2. **N2 — Fleet logistics:** fleet entities, construction, basing, repair, supply and maintenance.
3. **N3 — Transport loop:** embark, capacity reservation, sea movement, interception and disembark.
4. **N4 — Naval combat:** engagements, morale, casualties, retreat and battle reports.
5. **N5 — Strategic effects:** blockades, coastal siege support and trade protection hooks.
6. **N6 — Naval AI and UX:** fleet missions, danger evaluation, automation and player feedback.

### Exit gate

A deterministic England–France test must transport armies across the Channel, allow interception and battle, apply blockade effects, survive save/load mid-operation and complete 100 seeded repetitions without desync or stranded transport state.

## Pillar B — Exploration and Colonisation

### Current state

The full world and many native countries are present, but there is no unexplored map state, explorer/conquistador mission, colonist, settlement, colonial growth, colonial nation or overseas-discovery AI. This leaves much of the global map strategically inert.

### Minimum 1.0 scope

- Country-specific terra incognita and discovery state.
- Discovery spread rules and map-sharing actions.
- Explorers, conquistadors or equivalent expedition leaders.
- Exploration missions and route-risk rules.
- Colonist capacity, range, travel time, cost and recall.
- Colony growth, native population/policy interaction, failure and completion.
- Colonial ownership conflict, treaty/claim rules and colonial wars.
- Colonial regions and subject formation.
- Colonial liberty, tariffs and independence pressure at the selected depth.
- Appropriate treatment of indigenous states; they must remain active actors, not empty land.
- AI strategy for exploration, colonial choice, defence and subject management.
- Clear map modes, alerts, tooltips and progress presentation.

### Production slices

1. **C1 — Discovery authority:** per-country visibility, discovery events and save-safe fog state.
2. **C2 — Expedition loop:** leaders, missions, range and risk.
3. **C3 — Colony loop:** colonist assignment, cost, growth, native interaction and completion.
4. **C4 — Colonial polity:** regions, colonial subjects, tariffs, liberty and independence hooks.
5. **C5 — AI and balance:** historical priorities without scripted inevitability.

### Exit gate

Portugal and Castile must independently discover viable Atlantic routes, establish and sustain colonies, encounter existing states correctly, form a colonial subject when conditions are met and continue correctly through save/load and deterministic replay.

## Pillar C — Global Trade Network

### Current state

The economy has 31 trade goods, province production and value, but no network moves that value. There are no nodes, routes, merchants, steering, collection, trade power or trade conflict. The existing trade value is therefore only a local economic input.

### Minimum 1.0 scope

- Authored trade nodes or an approved alternative market geography.
- Directed routes with cycle prevention and validation.
- Province-to-node membership and coastal/river/port modifiers.
- Country trade power from provinces, ships, buildings, subjects and policies.
- Merchant assignment, collection and steering.
- Value creation, retention, transfer, leakage and income accounting.
- Embargoes, trade agreements and war effects.
- Light-ship or equivalent protection mission integration.
- Trade map mode, route visualisation, node panel and explainable income tooltips.
- AI merchant/fleet allocation under a bounded CPU budget.

### Production slices

1. **T1 — Network data:** node schema, route graph, membership tools and validation.
2. **T2 — Monthly calculation:** deterministic value and power propagation with debug traces.
3. **T3 — Player agency:** merchants, collection/steering and buildings/policies.
4. **T4 — Maritime/diplomatic hooks:** trade fleets, blockades, embargoes and subjects.
5. **T5 — UX, AI and balance:** map mode, explanations, AI allocation and performance budgets.

### Exit gate

Every eligible province must resolve to one valid trade node, the route graph must be cycle-safe, monthly global calculation must remain deterministic, country trade income must be fully explainable, and the calculation must meet its simulation budget during a 100-year world soak.

## Pillar D — Holy Roman Empire

### Current state

Central Europe contains the expected political fragmentation, but there is no Emperor, elector, imperial authority, Free City status, prince obligations, reform ladder or internal-imperial diplomacy. The region looks appropriate but does not play appropriately.

### Minimum 1.0 scope

- HRE membership at country and province level.
- Emperor eligibility, election, succession and elector votes.
- Imperial authority gains/losses and display.
- Imperial incidents, unlawful territory and defensive obligations.
- Free Cities, princes, electors and religion eligibility rules.
- Reform ladder with data-driven effects and AI voting.
- Emperor calls, refusal consequences and external-threat handling.
- Dismantling/leaving/joining rules with explicit historical constraints.
- HRE interface, map overlays, alerts and explainable voting tooltips.
- AI evaluation for elections, reforms and imperial diplomacy.

### Production slices

1. **H1 — Membership and offices.**
2. **H2 — Election and authority.**
3. **H3 — Obligations and incidents.**
4. **H4 — Reform progression and dismantling.**
5. **H5 — UX, AI and historical setup validation.**

### Exit gate

The 1444 setup must identify valid members, electors and Emperor; the imperial election must survive ruler death and save/load; external attacks must trigger correct obligations; and reform voting must be deterministic and explainable.

## Pillar E — Reformation and Religious Upheaval

### Current state

The project has religion, tolerance and conversion foundations, but no historical Reformation trigger, centres/spread model, confessional diplomacy, religious leagues or equivalent period-defining arc.

### Minimum 1.0 scope

- Date/context-sensitive Reformation trigger with bounded historical variance.
- Protestant and Reformed emergence or the project’s approved equivalents.
- Province conversion pressure and centres of spread.
- Country conversion decisions, resistance and unrest.
- Confessional diplomacy and opinion effects.
- HRE religion interaction and religious-conflict escalation.
- Religious leagues or a deliberately scoped alternative.
- Peace outcomes that alter confessional rules.
- AI conversion/league decisions and historical guardrails.
- Player alerts, map mode and readable conversion forecasts.

### Production slices

1. **R1 — Trigger and denominations.**
2. **R2 — Province spread and country conversion.**
3. **R3 — Diplomatic and HRE interaction.**
4. **R4 — Religious conflict and settlement.**
5. **R5 — AI, UX, historical validation and balance.**

### Exit gate

In multi-seed 1444–1650 soaks, the Reformation must emerge within an approved historical window, spread through explainable rules without producing a fixed identical map, interact correctly with HRE membership and survive save/load without conversion-state loss.

## Shared Architecture Requirements

All five pillars must:

- use stable IDs and externalised data;
- mutate simulation state only through the command system;
- use deterministic RNG streams;
- include schema-versioned save migration;
- expose debug/AI-reason traces;
- define monthly and daily CPU budgets before global enablement;
- ship with integration, replay and soak tests;
- include content validators before worldwide data entry begins.

