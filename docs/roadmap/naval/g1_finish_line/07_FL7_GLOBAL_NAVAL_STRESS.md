# FL7 - Global Naval Stress and Performance

**Status:** Validation. FL7 now owns a real 120-fleet dense-zone presentation fixture and a combined eight-country simultaneous simulation covering transport capacity loss, concurrent battles/blockades, global AI, construction completion, peace, extinction, admiral replacement, repeated reloads and uninterrupted-versus-reloaded checksums - see [FL7_HEADLESS_SIMULTANEOUS_FIXTURES.md](evidence/FL7_HEADLESS_SIMULTANEOUS_FIXTURES.md). Existing scale/soak/100-seed coverage was also revalidated after FL3 - see [FL7_REVALIDATION_AFTER_FL3_AI.md](evidence/FL7_REVALIDATION_AFTER_FL3_AI.md). Status remains `Validation` because rendered-mode evidence and approved low-end/target-hardware budgets are still required by the exit gate.
**Goal:** Verify the complete naval loop under simultaneous world-scale load, including presentation and AI.

## Stress fixtures

### FL7.1 Dense-zone presentation

- Many friendly, allied, neutral and hostile fleets in one sea zone and adjacent ports.
- Marker clustering, stable selection, route updates and battle markers active.
- Measure marker count, update time, frame time, memory and selection correctness.

### FL7.2 Simultaneous operations

- Multiple fleets moving through intersecting routes.
- Multiple armies embarking, sailing, battle-paused, retreating and disembarking.
- Partial capacity loss and carrier destruction included.
- Saves occur during transport, battle and retreat.

### FL7.3 Large battles and reinforcements

- Several concurrent naval battles with multiple fleets per side.
- Reinforcement, morale collapse, capture, sinking, pursuit and no-port retreat paths.
- AI and player orders compete for at least one zone.

### FL7.4 Multi-coast blockades

- Many ports across several coasts and shared sea zones.
- Contested and uncontested blockades change economy, siege, repair, construction and war score.
- Peace, port capture and annexation remove effects correctly.

### FL7.5 Global AI and construction

- Generic maritime AI enabled for all eligible countries.
- Construction, basing, organisation, repair, transport, escort, interception, blockade and retreat decisions active.
- Planning schedules are staggered and bounded.

### FL7.6 Long-running lifecycle

- Run long enough to include construction completion, wars starting/ending, access changes, country extinction, admiral death/replacement and repeated save/load.
- Audit naval invariants at fixed checkpoints.
- Compare uninterrupted and save/reload continuation checksums.

## Measurements

- Daily and monthly time by naval subsystem.
- AI planning P50, P95 and maximum.
- Marker/render frame-time P50, P95 and maximum.
- Path-query/cache counts.
- Maximum simultaneous fleets, ships, operations, battles, blockades and markers.
- Peak process memory and save size/load time.
- Invariant audit time.

Budgets must be measured and approved before the gate. A timeout or budget may not be raised solely to turn a failure green.

## Required outcomes

- No desync or frame-rate-dependent authoritative result.
- No invalid or duplicate registry reference.
- No leaked reservation, battle lock, route, marker or blockade effect.
- No stranded or duplicated army.
- No unbounded AI candidate, trace, marker or event growth.
- All measured work remains within approved low-end and target-hardware budgets.

## Exit evidence

- Fixture sizes, seeds and commands.
- Raw measurement summary and approved budgets.
- Determinism/checksum comparison.
- Invariant results at every checkpoint.
- Headless and rendered test results.

Headless evidence: [FL7_HEADLESS_SIMULTANEOUS_FIXTURES.md](evidence/FL7_HEADLESS_SIMULTANEOUS_FIXTURES.md). Rendered/target-hardware evidence remains open.

## Exit gate

FL7 is complete when the full simultaneous fixture passes deterministically in headless and rendered modes, stays within approved CPU, memory, save and frame budgets, and leaves no lifecycle residue.
