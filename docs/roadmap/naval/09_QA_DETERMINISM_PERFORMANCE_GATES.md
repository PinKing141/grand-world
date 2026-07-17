# 09 - QA, Determinism, Performance, and Release Gates

**Status:** Planned  
**Applies to:** every naval slice and G1 exit

## Quality Rule

Each slice adds focused tests when its contract lands. Testing is not a final N6 clean-up task. A slice cannot exit with only happy-path UI evidence.

## Test Layers

### Definition/data tests

- Schema/version and enum validation.
- Unknown/duplicate/circular references.
- Port and graph topology.
- Starting fleet membership and unlocks.
- Historical/provenance status completeness.

### Unit/system tests

- Pathfinding/access/range.
- Construction/economy/repair.
- Fleet organisation/movement.
- Transport state transitions and reservations.
- Combat positioning/damage/retreat/capture/sinking.
- Blockade/siege/economy outputs.
- AI candidate evaluation and mission state.

### Integration tests

- Commands -> state -> events -> UI queries.
- Scheduler ordering boundaries.
- War/diplomacy/character/economy/land movement interactions.
- Save/load during every active state.
- Map marker and selection wiring.
- Exported startup/content/action flow.

### Replay and soak tests

- Frame-rate and game-speed independence.
- Save/reload continuation checksum.
- Repeated seeded Channel scenario.
- Regional multi-year autonomous naval loop.
- Full-world idle/active fleet simulation.

### Rendered/manual tests

- Fleet markers, route lines, clusters, selection and battle markers.
- Naval panels/modals/tooltips/outliner/alerts.
- Supported resolutions and UI scales.
- Low-end and target GPU stability.
- Mouse/keyboard focus and cancellation safety.

## Determinism Matrix

For identical initial state and command schedule, compare:

- 30, 60, 120, and uncapped rendered frame rate where available.
- Game speeds 1-5.
- Continuous run versus frequent pause/step.
- Continuous run versus save/reload at selected boundaries.
- Headless versus rendered authoritative checksum.
- Supported Windows hardware profiles where authoritative parity is required.

Compare fleet/ship/transport/battle/blockade registries, country economy/sailors, wars, armies, RNG streams, counters, and final checksum.

## Save Boundary Matrix

Required save points:

- Ship under construction and due on load day.
- Fleet split/merge/transfer completion.
- Fleet mid-leg, blocked, unsupplied, retreating, repairing.
- Embark planned, embarking, embarked, sailing, battle-paused, disembarking, cancelling.
- Battle before round, after damage, during reinforcement, retreat requested, battle ending.
- Active blockade and coastal siege.
- Admiral death/assignment boundary.
- War peace and access/basing change boundary.

Each save must load exactly or reject with an expected precise error when intentionally corrupted.

## Invariant Audit

Run after commands, day/month boundaries in tests, save load, and soak checkpoints:

- Every ship has one valid owner and fleet/reserve.
- Fleet membership is reciprocal and unique.
- Fleet location/status/path fields agree.
- Army has at most one transport operation and exactly one land/transport presence.
- Capacity reservations are nonnegative, reciprocal, and within usable transport capacity or in explicit loss recovery.
- Battle membership is reciprocal and unique.
- Destroyed/captured ships have no stale memberships.
- Terminal operations/battles leave no locks or reservations.
- Admirals are alive/eligible/exclusive.
- Ports/zones/paths/definitions exist.
- Hull, crew, morale, maintenance, progress, blockade, supply, and war score remain bounded.
- Naval ledger totals equal authoritative expenses/loss modifiers.
- Counters cannot collide with allocated IDs.

## Channel Acceptance Scenario

The canonical fixture must:

1. Load reviewed England/France ports, fleets, ships, sailors, and war state.
2. Begin ship/repair action where needed.
3. Reserve capacity and embark an English or French army.
4. Sail through the Channel.
5. Permit enemy detection/interception.
6. Resolve battle with transport stakes.
7. Retreat/repair survivors where applicable.
8. Establish or contest a blockade.
9. Apply siege/economic/war-score effects.
10. Disembark surviving army or produce an explicit terminal loss.
11. Save/load at a seeded mid-operation point.
12. Finish with no invariant violation.

Run 100 seeds. Record outcome distribution, not merely pass count: victories, retreats, sunk/captured ships, army arrival/loss, blockade duration, treasury/sailor bands, and completion days.

## Stress Fixtures

- Dense sea zone with many friendly/hostile fleets and marker clustering.
- Large fleet battle with reinforcements and transports.
- Many simultaneous ship constructions/repairs.
- Many active transport operations.
- Multiple blockades along one coast and one sea zone adjacent to many provinces.
- Global AI countries with staggered planning.
- Long campaign with fleet capture/owner changes and country extinction.

Stress data may be synthetic but must use valid IDs and normal commands.

## Performance Budget Process

Numerical budgets are locked during N0/N1 after profiling the current simulation on:

- Reference/target development hardware.
- The current Intel UHD 600 low-end compatibility laptop where practical.
- Headless test environment.

Measure separately:

- Maritime graph load and path-query P50/P95/worst.
- Daily fleet movement/logistics.
- Daily active battle cost by ship/fleet count.
- Transport operations.
- Blockade coast aggregation.
- Monthly sailors/maintenance/repair.
- AI strategic and tactical planning.
- Save size/write/load and checksum.
- Fleet marker/route/battle rendering frame time.
- Peak memory/VRAM impact.

Budgets are added to this document as measured numbers before N6 global enablement. Until then, implementations must still follow bounded-work rules and produce profiling counters.

## Required Instrumentation

- Active/idle fleet, ship, operation, battle, blockade counts.
- Daily/monthly microseconds by naval subsystem.
- AI countries/candidates evaluated and deferred.
- Path-cache hits/misses/invalidations.
- Maximum fleets/ships per zone and markers/clusters visible.
- Save naval bytes and load-validation time.
- Invariant audit duration.
- Current content/data versions and graph hash.

## UI and Accessibility Matrix

At minimum test:

- 1366x768 low-end laptop.
- 1920x1080 target baseline.
- 16:10 and approved ultrawide.
- Supported UI scaling values.
- Keyboard-only traversal of naval tab, fleet, construction, transport, and battle panels.
- Tooltips and rejection messages within bounds.
- Colour-vision profiles for danger/side/blockade/supply overlays.
- Reduced-motion behaviour when implemented.

## Compatibility and Export

- All naval definitions/content/icons/scenes/scripts appear in the export package.
- Clean Windows launch loads starting fleets and naval UI.
- D3D12/approved renderer paths do not lose the device under naval marker/battle load.
- Unsupported hardware follows the approved compatibility policy without changing authoritative state.
- Logs capture naval validation/rejection/invariant errors with IDs.
- Save policy and migration statement accompany milestone builds.

## Slice Exit Evidence

Every completed slice records:

- Test names and command/runner entry.
- Pass count and date.
- Deterministic checksum/seed fixture.
- Performance capture path.
- Save compatibility statement.
- Content/data version/hash.
- Rendered/manual checklist and hardware.
- Known issues and approved deferrals.

## G1 Release Gate

G1 passes only when all N1-N6 gates pass, the 100-seed Channel test has zero desync/stranding/invariant failures, full-world naval processing stays inside approved budgets, supported UI/hardware checks pass, and no P0 naval defect remains open.
