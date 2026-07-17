# Naval and Maritime Production Roadmap

**Status:** N0 complete; N1 (maritime graph) in validation — see [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md)  
**Roadmap milestone:** P0 Global Pillar A / G1 Maritime First Playable  
**Campaign period:** 11 November 1444 to 1 January 1700  
**Implementation rule:** no slice enters production until its inputs, state ownership, commands, tests, and exit evidence are explicit.

## Purpose

This package turns the completion audit's naval pillar into implementation-sized slices. It is the detailed authority for fleets, ports, sea movement, maritime transport, naval combat, blockades, naval AI, and the supporting player interface.

The naval phase is not complete when ships can move. It is complete only when the player and AI can construct and maintain fleets, transport armies without corrupting land state, fight deterministic battles, blockade coasts, save and reload every operation state, and understand the result through the interface.

## Existing Foundation

The project already contains reusable foundations:

- 566 baked water-region records that can serve as stable sea-zone IDs.
- 1,373 graph records marked coastal.
- 1,859 graph records with sea-neighbour relationships.
- Baked strait information and deterministic land pathfinding patterns.
- Stable province and country IDs.
- Authoritative `CampaignWorldState`, command queue, scheduler, event bus, and seeded RNG streams.
- Land movement, wars, battles, sieges, occupation, commanders, economy, construction, maintenance, saves, checksums, AI reason traces, and map markers.
- An original navy marker in the generated marker atlas.

The phase extends these systems. It must not create a parallel campaign clock, duplicate country ownership, infer topology from rendered textures at runtime, or mutate simulation state from UI code.

## Document Index

| Document | Scope | Completion question |
|---|---|---|
| [00 - Scope and architecture lock](00_SCOPE_AND_ARCHITECTURE_LOCK.md) | Product boundary, authority, invariants, cross-system order | Are the decisions stable enough to begin N1? |
| [01 - N1 Maritime graph authority](01_N1_MARITIME_GRAPH_AUTHORITY.md) | Sea zones, ports, access, range, deterministic pathfinding | Can every legal naval route be resolved and explained? |
| [02 - N2 Fleet logistics](02_N2_FLEET_LOGISTICS.md) | Fleets, ships, construction, sailors, maintenance, repair, basing | Can fleets be created, sustained, damaged, and restored? |
| [03 - N3 Maritime transport](03_N3_MARITIME_TRANSPORT.md) | Capacity reservation, embarkation, carriage, interception, disembarkation | Can an army cross water without becoming duplicated or stranded? |
| [04 - N4 Naval combat](04_N4_NAVAL_COMBAT.md) | Engagements, positioning, morale, hull damage, retreat, capture, sinking | Can hostile fleets produce deterministic, explainable outcomes? |
| [05 - N5 Strategic naval effects](05_N5_STRATEGIC_EFFECTS.md) | Blockades, siege support, economic pressure, trade hooks | Does maritime control affect the wider campaign? |
| [06 - N6 Naval AI and UX](06_N6_AI_AND_UX.md) | Missions, threat evaluation, automation, fleet panels, map feedback | Can player and AI use the complete loop safely? |
| [07 - Data, command, event, and save contracts](07_DATA_COMMAND_EVENT_SAVE_CONTRACTS.md) | Canonical records, stable IDs, commands, events, schema migration | Can every naval state be validated, replayed, and saved? |
| [08 - Starting content and historical validation](08_STARTING_CONTENT_AND_HISTORICAL_VALIDATION.md) | Ship definitions, ports, initial fleets, leaders, provenance | Is the Channel/Iberian content sufficient and reviewable? |
| [09 - QA, determinism, performance, and release gates](09_QA_DETERMINISM_PERFORMANCE_GATES.md) | Automated/manual matrix, budgets, soak and compatibility evidence | Is the phase stable at global scale? |
| [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) | Small work packets, dependencies, evidence, sign-off | What is the next bounded batch of work? |

## Critical Path

```text
N0 scope and contracts
    -> N1 maritime graph
    -> N2 fleet logistics
    -> N3 transport loop
    -> N4 naval combat
    -> N5 blockade and strategic effects
    -> N6 AI, UX, global validation
    -> G1 Maritime First Playable
```

N2 content research and UI wireframes may begin while N1 is being validated, but state-changing gameplay must follow the dependency order. Trade and colonisation may consume approved naval interfaces; they must not change naval identity or transport contracts after G1 without a schema review.

## Global Definition of Done

The naval pillar is complete only when all of the following are true:

- The England-France Channel scenario transports an army, permits interception, resolves battle, and applies a blockade.
- The scenario survives save/load during construction, fleet movement, embarkation, battle, retreat, repair, blockade, and disembarkation.
- One hundred seeded repetitions produce deterministic results with no orphan ship, duplicated army, negative reservation, invalid port, or stranded transport state.
- AI can build, base, repair, protect, transport, intercept, retreat, and explain why it chose an action.
- Every player command has a visible result or precise rejection reason.
- Naval maintenance, repair, construction, blockade pressure, and losses reconcile with the economy ledger.
- Full-world daily/monthly processing meets approved CPU, memory, save-size, and loading budgets.
- The supported hardware matrix completes the rendered fleet/marker/UI checks without device loss or layout failure.
- Starting fleet and port content has provenance and review status.
- Exported Windows builds include every required data, script, UI, icon, test fixture, and migration resource.

## Status Discipline

Each slice uses: `Not started`, `Discovery`, `In production`, `Validation`, `Complete`, `Blocked`, or `Deferred`. A slice cannot be marked complete from roadmap prose or class existence. Its exit tests and evidence paths must be recorded in [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md).
