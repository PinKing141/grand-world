# N2.2 - Naval Economy and Ship Construction

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N2.2, and the N2C work packet in [02 - N2 Fleet Logistics](../02_N2_FLEET_LOGISTICS.md)  
**Scope:** sailors, the navy_maintenance ledger line, and ship construction/cancellation/completion. No fleet organisation (create/merge/split/transfer), no movement, no admirals - those are N2.3/N2.4.

## Architectural choice: extend `EconomySystem`, don't parallel it

The naval economy could have been a separate `NavalEconomySystem` running its own pass. That was rejected: `EconomySystem.recalculate_all()`/`recalculate_country()` **replace** `runtime["ledger"]` wholesale every time they run, so a second system writing its own ledger keys on top would be silently wiped the next time `EconomySystem` recalculated - "naval expenses... reconcile with the economy ledger" ([00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md)) means *one* ledger, not two that need careful sequencing. Instead, `navy_maintenance` was added as a first-class ledger line directly inside `EconomySystem`, computed from `world.ship_registry` exactly the way `army_maintenance` is already computed from `world.army_registry` - army maintenance already crosses the "read a sibling registry" boundary, so this follows an existing precedent rather than inventing a new integration pattern. Same for `sailors`/`maximum_sailors`, added alongside `manpower`/`maximum_manpower` and recovering monthly via the identical `mini(maximum, current + maximum/RECOVERY_MONTHS)` formula (`SAILOR_RECOVERY_MONTHS`, a placeholder rate, not tuned).

`EconomySystem.initialize_world`/`process_day`/`process_month`/`recalculate_all`/`recalculate_country` all gained optional `ship_definitions`/`naval_definitions` parameters (default `null` → lazy `load_default()`, matching the existing `definitions` parameter convention) - every existing 2-argument call site in the codebase kept working unchanged; only naval code passes the new arguments explicitly.

## What was built

- Sailors: `SAILORS_PER_OWNED_PORT = 200` per enabled port a country owns (queried via `NavalDefinitions.enabled_port_ids()` + `world.get_province_owner()`) - "the first slice uses a simple explainable formula" per [02 - N2](../02_N2_FLEET_LOGISTICS.md), not final balance.
- `navy_maintenance` ledger line: sum of each owned ship's `monthly_maintenance` (from `ShipDefinitions`) scaled by the country's `navy_maintenance_bp` runtime modifier, included in `total_expenses` alongside `army_maintenance`.
- `ConstructShipCommand`: validates port existence/enabled status, ownership/control via `NavalAccessPolicy.can_base` (construction requires basing rights, not merely docking access - a stricter bar than transit), harbour-level and shipyard requirements against the port record, unlock date via `ShipDefinitions.unlocked_ship_ids()` and `SimulationDate.day_to_date()`, treasury and sailor sufficiency, and a placeholder one-project-per-port queue cap. Deducts cost and reserves sailors *upfront in full*, matching `ConstructBuildingCommand`'s existing pay-upfront policy rather than inventing an incremental-payment scheme.
- `CancelShipConstructionCommand`: refunds `cost * refund_bp / 10000` (mirrors `CancelConstructionCommand`) and fully releases the reserved sailors back to the pool.
- `EconomySystem._complete_naval_construction()`, called from `process_day()` alongside the existing `_complete_constructions`/`_complete_recruitments`: on completion the ship joins a **deterministic port reserve fleet** (`fleet_id = "reserve_<port>_<country>"`, not a counter - the same fleet is always found again for a given port/owner) via a new `_find_or_create_port_reserve_fleet()` helper. Ownership/control loss at the port pushes `completion_day` forward by one day at a time - the exact pattern `_complete_constructions` already uses for buildings - so an interrupted project never silently loses money, reserved sailors, or duplicates a ship.
- Three new `SimulationEventBus` signals: `naval_construction_started`/`cancelled`/`completed`.
- `ship_definitions.json` gained `refund_bp` (5000, i.e. 50%), `required_harbour_level` (1), `required_shipyard` (false) on all five representative ships, validated by `ShipDefinitions` alongside the existing fields.
- `tests/naval_economy_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Results (verified via `tests/naval_economy_test.gd`, exit 0, no errors)

- England (owns Calais + Kent, both enabled ports) starts with 400 maximum sailors, seeded at 200 (half), exactly mirroring the manpower seeding pattern.
- Rejections verified individually: foreign-owned port, ship not yet unlocked (`heavy_ship_of_the_line` before 1600), unknown ship ID, a sea zone passed as a port, insufficient treasury, insufficient sailors, and a full per-port queue.
- Happy path: constructing a `transport_cog` at Calais debits the full 5,000 cost and reserves 60 sailors immediately, at command-apply time (not at completion).
- Completion after the ship's 100 construction days: the naval construction entry is gone, exactly one new England fleet exists with ID `reserve_87_ENG`, it is `docked` at Calais, and contains exactly the one new ship with the correct definition and owner.
- After crossing a month boundary post-completion, `navy_maintenance` in the ledger equals exactly the transport cog's monthly maintenance (200), and `total_expenses` includes it.
- Cancellation refunds exactly 50% of the cost and fully restores the reserved sailors.
- Ownership change mid-construction (port captured by Burgundy) pauses the project indefinitely - it neither completes nor disappears - and resumes correctly once ownership is restored.
- No regression: re-ran the full existing phase suite (`simulation_core_test` through `phase_8_integration_smoke`, 14 tests) after modifying `economy_system.gd`'s core recalculation functions - all still pass. Checksums for tests that don't pin a golden hash shifted (expected: new `sailors`/`maximum_sailors`/`navy_maintenance_bp` fields are now part of country runtime state, which is checksummed), but no test asserts a fixed checksum value, only internal same-run consistency.

## Deliberately simple / deferred

- The 200-per-port sailor formula and the one-construction-per-port queue cap are explicitly flagged placeholders pending balance review, not approved content - consistent with N2.1's ship stats.
- `required_shipyard` is modeled and enforced in `ConstructShipCommand`, but no representative ship currently sets it `true` and no fixture port sets `shipyard: true` either, so that branch has no real-content exercise yet (only reachable via hand-built ship data, not tested here - N2.2 stayed focused on economy/construction, not port content authoring).
- No admiral, no fleet organisation commands (create/merge/split/transfer), no movement - a completed ship's fleet is *always* its port reserve fleet until N2.3 adds the commands to move it elsewhere.
- Repair, attrition, and basing-loss consequences for an idle fleet - N2.4.
