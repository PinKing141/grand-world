# N3.1 - Transport Authority and Reservation

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N3.1, and the N3A work packet in [03 - N3 Maritime Transport](../03_N3_MARITIME_TRANSPORT.md)  
**Scope:** the transport operation schema, capacity reservation/release, and create/cancel commands. No embark/disembark timing, carrier sailing, interception, or loss/recovery - those are N3.2/N3.3, and N3.3's loss/recovery in particular depends on N4 combat concepts (interception, transport losses in battle) that do not exist yet.

## Architectural choices

**Embarkation is instantaneous in this slice, not a scope oversight.** 03_N3's state machine has `planned -> embarking -> embarked -> sailing -> ... -> completed`. Building the exact embark-timing formula ("modified by port, army size, damage, and commander only through bounded integer rules") without first having the reservation/validation layer those bounds would sit on top of would have meant guessing at numbers with nothing to check them against. `CreateTransportOperationCommand.apply()` instead transitions straight to `embarked` - the record shape (`make_transport_operation_record`) already carries every field the later timing/sailing states will need (`planned_path`, `battle_pause_reference`, `accumulated_losses`, `completion_day`), so N3.2 fills in behavior, not schema - the same forward-design precedent N2.1's fleet `aggregate` sub-dict already established.

**Capacity damage threshold is binary, not scaled.** 03_N3 requires "damaged transport capacity follows an explicit threshold rule; it cannot fluctuate unpredictably from presentation values." A ship at or below 50% hull (`DAMAGED_CAPACITY_THRESHOLD_BP`) contributes zero capacity; above it, full capacity. A smoothly-scaled formula would arguably be more realistic, but "explicit" and "cannot fluctuate unpredictably" are best satisfied by the simplest rule that is unambiguous at every hull value - a placeholder pending balance review, like every other first-slice numeric constant in N2.

**An embarked army never gets a fake sea province.** 03_N3 explicitly forbids this ("Army does not own a fake sea province"). Rather than invent a sentinel location, the army's `current_province_id` is left untouched at its origin port for the entire embarked duration; only `status` becomes `embarked`. Land-presence queries (`armies_in_province()`) now skip embarked armies, and `MoveArmyCommand` rejects an embarked army with the exact reason 03_N3 names ("Ordinary army commands reject with an exact `army is embarked` reason") - checked before the pre-existing generic `movement_locked` check, so the two states remain distinguishable even though embarking also sets `movement_locked` for defense-in-depth with any other system that checks that flag independently.

**Cancellation deletes the operation record rather than transitioning it to a terminal state**, mirroring `CancelShipConstructionCommand`'s existing precedent for a transient in-progress record (as opposed to a persistent asset like a fleet, which stays around empty or gets erased only when genuinely empty). Because N3.1 never moves the army's `current_province_id`, cancellation is penalty-free and instantaneous: clear the reverse references, restore `status`/`movement_locked`, and the army is immediately land-present again. Cancelling any operation state beyond `embarked` (sailing, disembarking) is out of scope until those states exist in N3.2/N3.3.

## What was built

- `CampaignWorldState`: `transport_operation_registry` (new top-level registry), `ARMY_STATUS_EMBARKED`, `TRANSPORT_STATE_EMBARKED`, `make_transport_operation_record()`, `get_transport_operation()`; `army.transport_operation_id` and `fleet.transport_operation_ids` (array, supporting "one fleet may carry multiple armies only through distinct reservations"); `_validate_transport_data()` (structural/referential checks only - operation↔army↔fleet reverse references, known country/province references; capacity-vs-live-transports needs `ShipDefinitions` and is deliberately left to `TransportSystem`, not this structural validator); `armies_in_province()` now excludes embarked armies; `SAVE_SCHEMA_VERSION` 6→7 with a migration step for pre-transport saves. (While adding this migration step, found and fixed a latent bug: the existing schema-5→6 migration block never incremented its local `schema` variable, meaning a genuinely old schema-5 save would have skipped straight past any future `schema == 6` block. Fixed as part of adding N3.1's own 6→7 step, so the chain now advances correctly for saves at any prior schema.)
- `scripts/simulation/transport_system.gd` (new): `usable_capacity()`, `reserved_capacity()`, `available_capacity()`, `required_capacity()` (authoritative regiment count, per 03_N3 "Capacity Model" - "not displayed strength").
- `scripts/simulation/commands/create_transport_operation_command.gd` and `cancel_transport_operation_command.gd` (new).
- `MoveArmyCommand.validate()` extended with the embarked-army rejection.
- Two new `SimulationEventBus` signals: `transport_operation_created`, `transport_operation_cancelled`.
- `simulation_controller.gd`: `create_transport_operation()`/`cancel_transport_operation()` wrapper methods, following the existing `submit_command(XCommandScript.new(...))` pattern.
- `tests/naval_transport_operation_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Results (verified via `naval_transport_operation_test.gd`, exit 0, no errors)

- Rejections verified individually: unknown army, unknown fleet, wrong owning country, destination equal to origin, a non-coastal destination (found dynamically by scanning `ProvinceGraph` rather than assuming a fixture ID), a fleet not docked in the army's own province, and a fleet with zero transport capacity (an all-`war_galley` fleet - `war_galley`'s `transport_capacity` is 0 in `ship_definitions.json`).
- Happy path: embarking `army_1` (1 regiment) onto a `transport_cog`-carrying fleet at Calais bound for Kent reserves exactly 1 capacity unit, sets the army `embarked` and movement-locked, and the fleet correctly lists the reverse reference.
- The embarked army no longer appears in `armies_in_province(Calais)`.
- `MoveArmyCommand` against the embarked army returns exactly `"The army is embarked."`.
- Attempting to embark the same army again is rejected (already in a non-embarkable state).
- Cancelling the operation is penalty-free: the army returns to `idle`, un-locked, reappears in `armies_in_province`, the operation record is gone, and the fleet's available capacity is exactly restored to its pre-reservation value.
- Cancelling a since-cancelled (nonexistent) operation is rejected.
- Save/load round trip reproduces an identical checksum with the active operation intact; a corrupted save with a transport operation pointing at a nonexistent army is rejected, as is an army pointing at a nonexistent operation.
- Schema migration: a schema-6 save (missing `transport_operation_registry` entirely) migrates cleanly to schema 7 with an empty registry.
- No regression: re-ran all 38 Godot phase/core/naval tests (`country_registry_test` through this slice's new test) after this round of `campaign_world_state.gd`/`move_army_command.gd`/`simulation_controller.gd`/`simulation_event_bus.gd` changes - 37/38 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2 evidence doc since N2.3.

## Deliberately simple / deferred

- No embark/disembark timing formula - embarkation is instantaneous. N3.2's job.
- No carrier sailing integration - once embarked, an operation does not yet track or follow the fleet's movement. N3.2/N3.3's job.
- No battle pause, interception, transport losses, retreat, or destruction/recovery paths - all depend on combat concepts N4 has not built yet. N3.3's job once those exist.
- No hostile-landing penalty or land-battle handoff on disembark - there is no disembark step yet to attach it to. N3.2's job.
- No UI. `NavalHUD`/`campaign_interface_shell.gd` do not yet expose transport operations (assignment, route preview, alerts) - N3.4's job, mirroring how N2.5 was the UI slice for N2.
