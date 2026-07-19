# FL2.2 - Split, Merge and Transfer UI

**Status:** Complete and verified.
**Satisfies:** FL2.2 ("Split, merge and transfer") from [02 - FL2 Complete Fleet Management](../02_FL2_FLEET_MANAGEMENT.md).

## What was found before implementation

A survey of `scripts/ui/naval_hud.gd` (752 lines before this packet) against all six FL2 sub-scopes found FL2.1 (fleet summary), FL2.4 (mission control - `SetFleetMissionCommand.VALID_MISSIONS` was already the complete list the roadmap asks for), and FL2.6 (transport workflow) already built from earlier N-pillar work. FL2.2 was **entirely absent** - no split/merge/transfer controls existed anywhere in the scene, despite `SplitFleetCommand`, `MergeFleetsCommand`, and `TransferShipsCommand` all already existing at the simulation layer with working `validate()`/`apply()`, and `simulation_controller.gd` already exposing one-line wrapper methods (`split_fleet()`, `transfer_ships()`, `merge_fleets()`, L258-271) with zero UI callers. This made FL2.2 the cheapest, highest-value next packet: pure UI work reusing an already-proven, already-tested command surface, not new simulation logic.

(FL2.3's home-port picker and FL2.5's scuttle control were also found absent, but FL2.5's scuttle half is blocked on simulation work - no `ScuttleFleetCommand` exists in the repo at all - so it is out of scope for a UI-only packet. Both remain open.)

## What was built

`scenes/ui/naval_hud.tscn` gained a new organisation section (ship multi-select `ItemList`, a target-fleet `OptionButton`, and three buttons) inserted between the admiral and mission rows. `scripts/ui/naval_hud.gd` gained the handlers, built to the exact same validate-then-enable pattern every other fleet action in this panel already uses (`_refresh_admiral_validation()`/`_assign_selected_admiral()` was the direct template):

- **Ship list** (`_refresh_ship_transfer_list()`): shows the selected fleet's own ships (`definition_id`, hull % from `hull_bp`), multi-selectable. Selection survives a rebuild by ship ID, not list index, mirroring `_refresh_fleet_options()`'s own "keep previous selection" pattern - membership can change between refreshes (a ship leaving via a completed split, for instance).
- **Target-fleet list** (`_refresh_target_fleet_options()`): every other fleet the player owns that is docked, organisable, and at the *same port* as the selected fleet - built from `FleetSystem.is_docked_and_organisable()`, the exact eligibility check `MergeFleetsCommand`/`TransferShipsCommand` themselves apply, so the dropdown can never offer a choice `validate()` would go on to reject.
- **Split** (`_split_selected_ships()`): the selected ships, `SplitFleetCommand` via `simulation_controller.split_fleet()`.
- **Transfer** (`_transfer_selected_ships()`): the selected ships into the selected target fleet, `TransferShipsCommand`.
- **Merge** (`_merge_selected_fleets()`): the selected fleet and the selected target fleet, `MergeFleetsCommand`. (Discovered while testing, not assumed: the command keeps the *alphabetically-first* fleet ID as the survivor regardless of which fleet the player had selected as "source" - a real, pre-existing `MergeFleetsCommand.apply()`/`_sorted_fleet_ids()` behaviour this packet did not change, just had to test against correctly.)
- Each button is disabled with an explanatory `tooltip_text` (the real `validate()` rejection reason) whenever the current selection would fail - the same "preview legality agrees with command legality" contract FL2's own automated-verification section asks for, and the same UX FL2.2's own bullets ask for ("display the exact rejection reason returned by shared validation").

## Deliberately not built in this packet

- **Class-mix/speed/capacity preview** ("Preview the resulting class mix, speed, capacity and mission impact"): the ship list shows enough to make an informed choice (type, hull) but does not compute or display the *resulting* fleet's aggregate stats before confirming. A real gap, left for a follow-up rather than expanding this packet.
- **"Disable organisation while moving, fighting, retreating or carrying active transport reservations"**: true today only as a side effect of `FleetSystem.is_docked_and_organisable()` already being the exact gate `validate()` uses (a fleet that's moving/fighting/retreating/transport-locked simply never appears as a legal *target*, and a locked *source* fleet's own split/transfer buttons correctly disable via the same `validate()` call) - not a separately-tested UI-level lock, since none was needed on top of the existing validation-driven disable pattern.
- **Double-submission/stale-modal protection**: this panel has no modal dialogs (unlike, say, a confirmation popup) - every action is a direct button press against live-validated state, the same pattern the pre-existing admiral/mission/transport buttons already use without a separate guard.

## Verification

`tests/naval_fleet_organisation_hud_test.gd` (new): two fixture fleets at the same port (3 ships and 1 ship) driven entirely through the real HUD controls - selecting the fleet populates the ship list and target-fleet dropdown correctly; splitting one ship creates a genuinely new fleet and the source list updates; transferring a ship moves it into the target fleet; merging folds the remaining single-ship fleet into its target, correctly landing on the alphabetically-first surviving fleet ID. Every step reads real `world.fleet_registry`/`ship_registry` state after `scheduler.process_commands()`, not just UI-level assumptions. Registered in `run_all_tests.py`.

Full regression suite after the change: 71/72 (the sole remaining failure is the already-documented, unrelated FL8.2 hardware-blocked case). The pre-existing `naval_hud_integration_smoke.gd` and the full-scale G1 Channel/destructive-lifecycle release-gate tests all still pass unchanged.
