# 00 - Scope and Architecture Lock

**Status:** Discovery  
**Depends on:** implemented Phases 2-8  
**Unlocks:** N1 Maritime Graph Authority

## Outcome

Approve a bounded naval abstraction whose IDs, ownership, command surfaces, save state, and downstream trade/colonisation hooks will not require worldwide content to be re-authored.

## Player Promise

The player can treat coastlines as strategic geography. Fleets require money, sailors, ports, access, supply, and time. Armies require real transport capacity. Hostile fleets can intercept one another. Naval victories, blockades, repairs, and losses affect wars and economies. Every important result is explainable.

## In Scope for G1

- Stable sea zones and ports.
- Fleet and individual ship simulation records.
- Heavy, light, galley, and transport ship families with dated variants.
- Ship construction and cancellation.
- Sailors, naval maintenance, reinforcement, repair, supply, attrition, and basing.
- Fleet movement, missions, interception, reinforcement, and retreat.
- Army embarkation, capacity reservation, carriage, and disembarkation.
- Naval battles with positioning, morale, hull damage, capture, and sinking.
- Blockade power, coastal siege assistance, economic pressure, and trade hooks.
- Admirals using the existing character framework.
- Player fleet markers, panels, construction, transport, combat, blockade, alerts, and outliner entries.
- AI fleet planning and explainable decisions.
- Schema migration, exact save/load, checksum, replay, soak, stress, content validation, and export validation.

## Explicit Non-Goals

- The global trade-node calculation; naval only publishes stable protection/blockade inputs.
- Exploration, terra incognita, colonists, colonies, or colonial subjects.
- Privateering, piracy, treasure fleets, naval doctrines, marine unit trees, or custom ship design.
- Manual tactical control during battle.
- Individual crew members, ammunition inventories, wind vectors, tides, or detailed weather simulation.
- One scene-tree node per ship.
- Final worldwide starting fleets for all countries.
- Final naval sound, VFX, paintings, or release art beyond approved functional assets.
- Replacing land warfare or diplomacy with naval-specific duplicate systems.

## Authority Decisions

### Geography

- Existing water province IDs are sea-zone IDs.
- A port uses its coastal land province ID; ports do not receive a second ID namespace.
- `assets/province_graph.json` remains the topology authority.
- Runtime never derives sea adjacency from map pixels.
- Authored overrides correct exceptional port exits, straits, closed water, and invalid generated links.

### State

- `CampaignWorldState` owns all mutable naval records.
- Static class, port, and starting-fleet definitions live in versioned external data.
- Fleets and ships are dictionaries keyed by stable string IDs, matching current army/war conventions.
- Ships are individual data records so damage, capture, sinking, and construction remain exact.
- Presentation may pool or batch markers, but presentation never owns authoritative location or strength.

### Mutation

- Player, AI, events, and debug tools submit the same naval commands.
- Commands validate without changing state and apply atomically in queue order.
- UI never edits registries directly.
- Daily systems may advance already-authorised orders but may not invent a player order.
- Every rejection gives a stable human-readable reason.

### Determinism

- Important money, morale, hull, supply, positioning, blockade, and progress values use integers/basis points.
- Registry iteration is sorted by stable ID.
- Equal-cost path ties resolve by stable sea-zone/port ID.
- Naval RNG uses named campaign streams, never frame time or global random calls.
- Frame rate, rendering, animation, and input sampling cannot change authoritative outcomes.

### Time

- Fleets receive arrival days, not frame-speed movement.
- Construction, embarkation, disembarkation, repair, and retreat have explicit start/completion days.
- Daily combat resolves once per campaign day.
- Maintenance, sailor recovery, and strategic economic totals reconcile on the monthly boundary unless a rule explicitly needs daily timing.

### Location

A fleet has exactly one authoritative location state:

- `docked`: a legal port province.
- `at_sea`: a sea zone.
- `moving`: current zone plus remaining sea path and next arrival day.
- `battle`: a sea zone plus battle ID.
- `retreating`: current zone plus forced destination/path.

An army has exactly one transport relationship. It is either on land or references one active transport operation and carrier fleet. It cannot be simultaneously present in a land battle and aboard a fleet.

## Cross-System Daily Order

The scheduler order will be locked before N2 integration:

1. Apply queued commands for the day.
2. Complete ship construction due that day.
3. Advance fleet movement and arrival.
4. Evaluate interception and start/reinforce engagements.
5. Resolve active naval battle rounds and forced retreats.
6. Advance embarkation/disembarkation operations that are not battle-paused.
7. Advance land movement and land warfare.
8. Apply blockade contribution to coastal sieges.
9. Process daily naval attrition/supply rules that cannot wait for month start.
10. Publish events, then run scheduled AI through the normal command queue.

Monthly order must make naval expenses and blockade penalties appear once and reconcile with the displayed ledger. The exact placement relative to the existing economy system will be covered by an integration test.

## Performance Principles

- Process active fleets, operations, and battles rather than scanning every sea zone for every country.
- Maintain reverse indexes for fleet owner, location, port occupancy, transport reservations, and active battle membership.
- Cache maritime paths and invalidate only when access/topology-relevant state changes.
- Build sea-zone threat maps on staggered AI intervals, not every rendered frame or every country-day.
- Batch fleet markers and route presentation using the existing marker approach.
- Define measured CPU, memory, save-size, and load-time budgets before global N6 activation.

## Compatibility with Later Pillars

### Exploration and colonisation

The exploration phase may add mission types, discovery visibility, expedition leaders, and range modifiers. It consumes fleet location, mission, supply range, admiral, and sea-zone path APIs without changing fleet identity.

### Global trade

The trade phase consumes light-ship protection output, blockade output, port modifiers, sea-zone IDs, and country mission assignments. Naval does not calculate final trade-node income.

### Diplomacy and subjects

Naval access, fleet basing rights, war membership, alliances, and subject permissions extend the existing pair relationship records. They do not create a parallel diplomacy registry.

### Characters

Admirals are characters with an exclusive naval command assignment. Character death, succession, country change, and save validation must clear or transfer assignments safely.

## Architecture Lock Checklist

- [x] Stable record schemas approved. *(existing dictionary-keyed-by-stable-string-ID convention, confirmed against `CampaignWorldState` in [N0_BASELINE_INVENTORY.md](evidence/N0_BASELINE_INVENTORY.md))*
- [x] Port derivation and override policy approved. *(implemented and validated in N1.1: [N1_1_DATA_AUDIT.md](evidence/N1_1_DATA_AUDIT.md))*
- [x] Ship-as-record abstraction approved. *(as written above under "State"; no ship registry exists yet - applies from N2 onward)*
- [x] Transport casualty/stranding policy approved. *(abstraction stance as written; detailed rules are N3's to specify, not N0's)*
- [x] Naval access and basing-right semantics approved. *(as written above under "Mutation"/"Location" and detailed in [01 - N1](01_N1_MARITIME_GRAPH_AUTHORITY.md#access-and-basing-rules); implementation is N1.3)*
- [x] Combat abstraction and class roles approved. *(as written under "In Scope for G1" and "Explicit Non-Goals"; implementation is N4)*
- [x] Blockade economy/siege interfaces approved. *(as written under "Compatibility with Later Pillars"; implementation is N5)*
- [x] Save migration policy approved. *(reuses the existing `SAVE_SCHEMA_VERSION` sequential-migration pattern; confirmed in [N0_BASELINE_INVENTORY.md](evidence/N0_BASELINE_INVENTORY.md))*
- [x] Scheduler order approved. *(the Cross-System Daily Order above, confirmed consistent with the actual `SimulationScheduler.advance_one_day()` order in [N0_BASELINE_INVENTORY.md](evidence/N0_BASELINE_INVENTORY.md))*
- [x] Initial content countries and historical-review standard approved. *(England/France/Burgundy Channel + Portugal/Castile/Aragon Iberian fixtures, provenance template, recorded in [N0_TEST_FIXTURES.md](evidence/N0_TEST_FIXTURES.md))*
- [ ] Performance baseline captured and numerical budgets recorded. *(still open - no profiling harness exists yet; per this document's own "Performance Principles" section this is required "before global N6 activation," not before N1 production, so it does not block N1 - carried forward as a tracked gap)*
- [x] England-France fixture IDs and expected setup recorded. *(Calais/Kent/Picardie, Straits of Dover/The Channel; see [N0_TEST_FIXTURES.md](evidence/N0_TEST_FIXTURES.md))*

## Exit Gate

N0 exits when no unresolved decision can change sea-zone IDs, port IDs, fleet/ship identity, army transport ownership, save references, or the interfaces expected by colonisation and trade. Approval must be recorded in the delivery checklist before N1 production begins.

**Approved 2026-07-17.** All decisions above that bear on sea-zone IDs, port IDs, fleet/ship identity, army transport ownership, save references, or colonisation/trade interfaces are locked as written. The one open item (performance baseline) is explicitly N6-gated per this document's own text and does not block N1 production. N1 production (N1.2 runtime graph API onward) may proceed.
