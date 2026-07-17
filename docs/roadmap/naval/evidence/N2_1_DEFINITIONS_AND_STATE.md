# N2.1 - Ship Definitions and Fleet/Ship State

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N2.1, and the N2A/N2B work packets in [02 - N2 Fleet Logistics](../02_N2_FLEET_LOGISTICS.md)  
**Scope:** definitions and save-state plumbing only. No construction commands, no naval economy, no movement, no UI - those are N2.2 onward. Records are constructed directly in tests via the new static factories, the same way `army_registry` was exercised before Phase 3's movement commands existed.

## What was built

- `assets/ship_definitions.json` + `scripts/simulation/ship_definitions.gd` (`class_name ShipDefinitions`): a definitions loader in the `character_definitions.gd` validation-heavy style (not the coarser `economy_definitions.gd` style), because [02 - N2](../02_N2_FLEET_LOGISTICS.md) explicitly demands rejecting "negative values, missing successors, invalid technology tracks, circular upgrades, unknown family names, and impossible date ranges" - all of which are tested directly against synthetic malformed data via `from_data()`.
- Five representative ship records covering all four required families (`heavy`, `light`, `galley`, `transport`): `war_galley`, `light_caravel`, `heavy_galleon` → `heavy_ship_of_the_line` (a dated successor pair demonstrating the upgrade/retirement mechanic - the galleon's `end_date` is 1650, the ship of the line unlocks 1600), `transport_cog`. Every numeric value is placeholder/representative, not final balance content - each carries `provenance.confidence: "placeholder"`.
- `CampaignWorldState` gained `fleet_registry`, `ship_registry`, `naval_construction_registry`, wired through the full existing state-contract surface: `initialize()` clears them, `SAVE_SCHEMA_VERSION` bumped 5→6 with a migration step producing empty registries for pre-naval saves, `checksum()` includes all three, `to_save_dict()`/`apply_save_dict()` round-trip them with dedicated validation (`_validate_naval_data`), and static factories `make_fleet_record()`/`make_ship_record()`/`make_naval_construction_record()` mirror the existing `make_army_record()` pattern exactly.
- Fleet records encode the one-authoritative-location-state machine from [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#location) up front (`location_status` ∈ `docked`/`at_sea`/`moving`/`battle`/`retreating`, plus the movement/battle/retreat fields each state needs) even though nothing populates anything but `docked` yet - establishing the shape now is exactly what "approved state contracts" means, matching how `army_registry`'s movement fields existed before Phase 3 movement logic did.
- Accessor helpers `get_fleet`/`get_ship`/`country_fleets`/`fleet_ships`, matching the existing `get_army`/`country_armies`/`armies_in_province` convention (on-demand sorted filtering, not a maintained cache - consistent with how every other registry in this codebase works today).
- `tests/ship_definitions_test.gd` and `tests/naval_fleet_state_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Save-integrity invariants enforced (not just assumed)

`_validate_naval_data()` rejects, with a specific reason, rather than silently accepting corrupt state:

- A fleet or ship owned by an unknown country.
- A fleet whose `home_port_id`/`location_id` is not a known province.
- A ship whose `fleet_id` points to a fleet that doesn't exist.
- **Non-reciprocal membership**: a ship claiming fleet membership the fleet itself doesn't list, or vice versa - directly enforcing [02 - N2](../02_N2_FLEET_LOGISTICS.md)'s "no authoritative aggregate may disagree with the underlying ships" and "a ship cannot appear in two membership lists."
- A ship listed twice within one fleet's `ship_ids`.
- Naval construction referencing an unknown country or port.

All six rejection paths are exercised directly in `naval_fleet_state_test.gd` by corrupting a known-good save and asserting `apply_save_dict()` returns a non-empty error - not just trusting the validation code reads correctly.

## Results (both tests, exit 0, no errors)

- `ship_definitions_test.gd`: 4 families, 5 ships; 1444-era unlock set includes the baseline four, excludes the 1600 successor; the successor becomes available from 1600 and the galleon retires after 1650; all malformed-data cases (negative value, unknown family, invalid tech track, missing successor, circular successor, inverted date range) rejected.
- `naval_fleet_state_test.gd`: fleet/ship creation, accessor correctness, save/load round-trip with **identical checksum** before and after, all six corruption cases rejected, and a genuine schema-5→6 migration test (erasing the naval keys entirely, as a real pre-naval save would never have had them) producing empty, valid registries.
- No regression: re-ran the full existing phase suite (`simulation_core_test`, `simulation_frame_rate_determinism_test`, `phase_2` through `phase_8`) after the schema bump - all still pass, none had a hardcoded schema-version assumption that broke.

## Deliberately not built yet

- Mission definitions - `SetFleetMissionCommand` and real mission behaviour don't exist until N2D, so a missions schema now would be speculative. `fleet_registry`'s `mission` field defaults to `"idle"` as a placeholder string, not a validated enum yet.
- Any command that actually creates a fleet or ship (`ConstructShipCommand` etc.) - that is N2.2/N2C. `take_counter()` (the existing generic ID-allocation helper) is ready to be called by those commands but nothing calls it for naval IDs yet.
- Naval economy (sailors, maintenance ledger lines) - N2.2.
- Cross-validation against `ShipDefinitions`/`NavalDefinitions` inside `CampaignWorldState` itself - deliberately avoided, matching the existing layering where `CampaignWorldState` never imports `EconomyDefinitions` or `CharacterDefinitions` either; definition-level legality checks belong in commands/systems, save-level checks only confirm internal state consistency (owners exist, provinces exist, membership is reciprocal).
