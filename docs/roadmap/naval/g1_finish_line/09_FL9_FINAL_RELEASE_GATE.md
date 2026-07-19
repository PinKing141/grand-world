# FL9 - Final G1 Release Gate

**Status:** Blocked on FL1-FL8
**Goal:** Re-audit the complete naval pillar as untrusted and issue the only decision that may unlock C1.

## Entry conditions

- FL1-FL8 are marked `Complete` with dated evidence.
- No open P0 or P1 naval, UI, accessibility, performance or project-gate issue exists.
- Working tree, commit, Godot version, Python dependencies and hardware are recorded.

## Final audit path

Reverify, in order:

1. Port and sea-zone authority.
2. Fleet creation, construction and starting content.
3. Basing, repair, reinforcement and maintenance.
4. Deterministic pathfinding and access changes.
5. Embarkation and capacity reservation.
6. Movement, detection and interception.
7. Combat, positioning, morale, losses, capture, pursuit and retreat.
8. Disembarkation and land-AI handoff.
9. Blockades, coastal effects and downstream query contracts.
10. Naval AI and player/AI contention.
11. Player map, fleet controls, feedback and accessibility.
12. Save/load, corruption rejection and old-schema migration.
13. Deterministic replay, global stress, rendering and export.

## England-France Channel acceptance

Run 100 fixed seeds twice each. Every execution must build fleets, embark an army, save/load during transport, cross the Channel, allow interception, resolve combat, retreat or continue correctly, disembark without state loss, apply/remove a blockade, and end the war while naval operations are active.

Required terminal result across all runs:

- Zero desyncs.
- Zero invalid references.
- Zero leaked capacity reservations or battle/transport locks.
- Zero duplicated or stranded armies.
- Zero unexplained terminal operations.

## Destructive matrix

Re-run carrier destruction, partial capacity, split/merge/transfer lock, captured destination, revoked access, peace during movement/battle, embark/disembark cancellation, no retreat port, battle/retreat save-load, AI/player same-zone orders, annexation with fleets and old schemas without naval data.

## Required run order

1. Data/schema validators.
2. Targeted FL1-FL8 tests.
3. Complete registered naval suite.
4. Destructive lifecycle gate.
5. One-seed Channel diagnostic.
6. 100-seed Channel gate and replay.
7. Rendered acceptance and global naval stress.
8. Windows export and exported startup/action flow.
9. Canonical full project suite.

Do not update evidence after a failed prerequisite as though later checks were authoritative. Record failures and keep the gate blocked.

## Final evidence document

Record exact commands, versions, commit/working-tree state, pass counts, seeds, checksums, timings, performance budgets, hardware, export result, manual reviewers, known issues and the severity decision for every issue.

## Verdict rule

- `PASS`: all required evidence is current, every gate passes and no P0/P1 issue remains. G1 may be approved and C1 may be considered separately.
- `FAIL`: any required check fails, times out, is skipped without approval, lacks evidence, or leaves a P0/P1 issue. G1 remains blocked and C1 must not start.

FL9 must never be marked complete merely because implementation exists. Only a documented `PASS` verdict closes this roadmap.
