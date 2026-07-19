# FL4.3 - Admiral Policy and Content

**Status:** Complete (policy decision, no code needed - see "Why no code was needed" below).
**Satisfies:** [04_FL4_STARTING_CONTENT_AND_LEADERS.md](../04_FL4_STARTING_CONTENT_AND_LEADERS.md)'s FL4.3 scope.

## Decision

**G1 ships with no starting naval admirals.** Every one of the five starting fleets (`starting_fleet_ara_mediterranean`, `starting_fleet_cas_atlantic`, `starting_fleet_eng_channel`, `starting_fleet_fra_atlantic`, `starting_fleet_por_atlantic`) begins with `admiral_id == ""` and an explicit `admiral_status: "no reviewed named naval leader assigned"` field in `assets/grand_world_1444_naval_forces.json`, carried into the [FL4.2 content report](FL4_2_STARTING_CONTENT_REPORT.md) rather than silently omitted.

This is the "approve a deterministic generated-leader policy before generating any leader" bullet resolved as **defer, not generate**: G1 approves neither reviewed named historical admirals (no source/reviewer/date content pipeline for period naval leaders exists yet) nor a synthetic generated-leader policy (no naval-specific leader-generation formula has been designed or reviewed). Rather than ship an unreviewed placeholder leader under either path, G1 ships none, and the player/AI can assign an admiral from the normal court through the already-existing, already-tested `AssignAdmiralCommand` at any point after campaign start.

| Field | Value |
|---|---|
| Source | This document. |
| Reasoning | Neither a reviewed named-admiral content set nor an approved generated-leader formula exists for G1's scope; shipping an unreviewed one under either name would violate FL4.1's own "do not present gameplay estimates as exact historical counts" principle applied to leaders instead of ships. |
| Reviewer | naval-roadmap-gate |
| Review date | 2026-07-19 |

## Why no code was needed

Every mechanical requirement FL4.3 lists was checked against already-existing, already-tested machinery, confirmed still correct rather than assumed:

- **"One admiral cannot command multiple fleets"** - `AssignAdmiralCommand.validate()` (`commands/assign_admiral_command.gd:36-38`) already rejects assigning a character who already holds `admiral_fleet_id` pointing at a different fleet.
- **"Dead/ineligible leaders cannot remain assigned"** - `CharacterSystem`'s death-cleanup path (`character_system.gd:296-301`) already reciprocally clears `fleet.admiral_id` and `character.admiral_fleet_id` on death, general character-system machinery that applies to every admiral regardless of how they were assigned.
- **"Define save migration behavior for older saves without starting admirals"** - trivially satisfied: every save, old or new, already represents "no admiral" as `admiral_id == ""` - the same value a starting fleet now begins with. There is no migration to write because there is no new field or new empty-vs-absent distinction being introduced.
- **An admiral-less fleet is a fully legal, fully functional state** - confirmed by reading every consumer of `admiral_id`: none of `NavalCombatSystem`, `NavalAISystem`, `FleetMissionSystem`, or `BlockadeSystem` require a non-empty `admiral_id` for any eligibility, combat, or mission check. Missions, movement, combat, and blockade all function identically whether or not a fleet has an admiral.

Building a new admiral-generation policy, eligibility model, or replacement-behaviour system now would be inventing mechanics FL4.3 explicitly says must be "approved before generating any leader" - exactly the trap [FL2_CLOSURE_AUDIT.md](FL2_CLOSURE_AUDIT.md) already named for FL2.4's inert missions ("that would be presenting a control that lies about doing something"), applied here to leader content instead of mission content.

## Verification

- `tests/starting_naval_forces_test.gd` (pre-existing): confirms `initialize_world()` succeeds and every fleet's aggregate/membership is correct with no admiral assigned - implicitly proving the admiral-less path is not just "legal in theory" but exercised by the actual starting-content initialization test.
- No new test was needed for the death-cleanup/exclusivity guarantees above - both are pre-existing, general character-system behaviour, already covered by `tests/phase_7_character_test.gd` and naval fleet-management tests (`tests/naval_hud_integration_smoke.gd`'s admiral assignment section) that predate this packet.

## Deliberately out of scope for this packet

- **Reviewed named historical admirals** - would need a real content-sourcing pass (names, dates, ranks, provenance) this session has no source material for; explicitly deferred, not silently dropped, per FL4.1's own "unknown ... require a source" principle.
- **A generated-leader policy/formula** - same reasoning; a real design decision (eligibility, skill bounds, traits) that should be reviewed on its own, not improvised to fill a content gap.
