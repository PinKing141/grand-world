# N2.5 - Minimal UX/Gate

**Status:** Recorded, except export evidence, which is blocked (not deferred by choice) on Godot export templates not being installed in this environment  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N2.5, and the N2F work packet in [02 - N2 Fleet Logistics](../02_N2_FLEET_LOGISTICS.md)  
**Scope:** a debug-functional naval UI (fleet panel, port construction, admiral assignment), outliner/alert entries, and save/accounting/determinism/stress/performance evidence. Export evidence is confirmed blocked, not attempted-and-skipped - see below.

## Two rounds, and why

02_N2's checklist bundles six different kinds of evidence into one line ("Save, accounting, determinism, stress, performance, and export"). The first round of this slice built the UI itself plus save and accounting evidence (accounting was already proven in N2.2, so only save needed new coverage). Determinism, stress, and performance each needed their own verification pass with a different shape - extending the existing frame-rate-variance harness, building a many-fleet stress fixture, and capturing timing at that scale - so they were done as a second round rather than bundled into the UI-building session, honouring the roadmap's own rule ("work one small packet to test-backed completion before opening the next dependency-heavy packet"). Export was attempted in that second round and found to be genuinely blocked, not merely unattempted.

## Architectural choices

**NavalHUD is self-contained, not wired into the shared top navigation bar.** `EconomyHUD`'s `NavigationRow` (Gov/Eco/Mil/Dip/Rel buttons) is already the "final campaign tab" surface reserved for N6 styling. Rather than crowd a new button into that row prematurely, `NavalHUD` gets its own small always-visible toggle button (`%NavalToggleButton`) and manages its own panel, matching the roadmap's explicit instruction that "final styling waits for N6, but every action must be operable and testable" - operable now, without pre-committing to N6's actual tab layout. `CampaignInterfaceShell` still gained a `naval_hud` export and an `_open_naval()`/`_focus_fleet()` pair so outliner entries and future alert-driven navigation can reach it, the same indirection `_open_military()` already uses for the army panel.

**Every panel action reuses `Command.validate()` for enable/disable, never a parallel rule.** `NavalHUD._refresh_move_validation()`, `_refresh_admiral_validation()`, and `_refresh_construction_validation()` each construct the real command (`MoveFleetCommand`, `AssignAdmiralCommand`, `ConstructShipCommand`) and call `.validate(world)` to decide whether the button is enabled and what its tooltip says - identical to `EconomyHUD._refresh_action_validation()`. This guarantees the UI can never offer an action the backend would then reject for a reason the player never saw.

**The admiral dropdown pre-filters using the same exclusivity rules `AssignAdmiralCommand` enforces**, so every listed candidate is guaranteed assignable - the dropdown is a subset of "would validate," not a superset the player has to discover by trial and error.

**Twelve new `simulation_controller.gd` wrapper methods**, one per naval command (`construct_ship`, `cancel_ship_construction`, `create_fleet`, `split_fleet`, `transfer_ships`, `merge_fleets`, `set_fleet_home_port`, `order_fleet_move`, `cancel_fleet_movement`, `assign_admiral`), follow the exact `submit_command(XCommandScript.new(...))` one-liner pattern every existing wrapper (`construct_building`, `recruit_unit`, etc.) already uses. `NavalHUD` only exercises `construct_ship`, `order_fleet_move`, `cancel_fleet_movement`, and `assign_admiral` directly (the fleet-organisation commands have no UI yet - see deferred below), but all twelve exist so a future organisation UI, save-file tool, or test can call them without adding more controller surface.

## What was built

- `scenes/ui/naval_hud.tscn` + `scripts/ui/naval_hud.gd` (new): toggle button, fleet list/detail/move/cancel-movement/admiral-assignment, and port ship-construction/cancel, following `economy_hud.tscn`/`.gd`'s structure and `draggable_panel.gd` reuse exactly.
- `scenes/main.tscn`: `NavalHUD` instanced and wired (`simulation_controller`, `province_selector`, `notification_hud`), alongside the existing `EconomyHUD`/`WarHUD` instances; `CampaignInterfaceShell`'s `naval_hud` export wired to the same node.
- `scripts/simulation/simulation_controller.gd`: twelve naval command wrapper methods and their `const ...CommandScript` preloads.
- `scripts/ui/campaign_interface_shell.gd`: new FLEETS outliner section (status text includes "unsupplied"/"damaged" when applicable, click-to-focus via a new `_focus_fleet()`), a new "Unsupplied fleets (N)" alert routed to `_open_naval()`, and the `naval_hud` export/`_open_naval()` plumbing those both depend on.
- `tests/naval_hud_integration_smoke.gd` (new), registered in `tools/testing/run_all_tests.py`: instantiates the real `main.tscn`, drives `NavalHUD`'s own handler methods (not synthetic input events, matching every other phase's integration smoke), and includes a save/load round trip.

## Results (verified via `naval_hud_integration_smoke.gd`, exit 0, no errors, using the real 1444 scenario)

- Choosing England reveals the naval toggle; opening the panel shows "Fleets 0" (a fresh country has none).
- Selecting Calais (England's real, owned, enabled home port in the actual 1444 scenario data - not a synthetic fixture) exposes port construction; the ship option list populates from `ShipDefinitions`; pressing Build reaches `WorldState.naval_construction_registry` through the exact same command path a save file or another system would use.
- Fast-forwarding past the construction's completion day produces exactly one England fleet, and the fleet panel correctly reports "Ships 1" for it.
- A save/load round trip after all of the above reproduces an identical world checksum and the same fleet survives, with the panel correctly reflecting the reloaded state after `_refresh_all()`.
- No regression: re-ran all 37 Godot phase/core/naval tests (`country_registry_test` through this slice's new smoke/stress tests) after both rounds of `campaign_interface_shell.gd`/`simulation_controller.gd`/`main.tscn`/`simulation_frame_rate_determinism_test.gd` changes - 36/37 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake already recorded in [N2_3_ORGANISATION_AND_MOVEMENT.md](N2_3_ORGANISATION_AND_MOVEMENT.md) and [N2_4_LOGISTICS.md](N2_4_LOGISTICS.md). `campaign_interface_shell_smoke.gd` in particular still passes, confirming the outliner/alert changes didn't disturb the existing ARMIES/WARS/CONSTRUCTION/SUBJECTS sections.

## Determinism, stress, and performance (second round)

- **Determinism.** `naval_fleet_movement_test.gd` (N2.3) already proved fleet movement resolves identically given an identical order in a fresh world. What was still missing: `simulation_frame_rate_determinism_test.gd`, the *general* cross-frame-rate harness every other system is checked against, predates naval and its fixture scenario had never contained a fleet - so `FleetMovementSystem`/`FleetLogisticsSystem` had literally never been ticked by that specific harness before. Fixed by adding a fleet (owner "SWE", `war_galley`, Calais → Kent) to `_make_controller()` and asserting its final location/status match, on top of the existing whole-world checksum comparison, between a 30 FPS and a 120 FPS run. Both now match exactly.
- **Stress.** `tests/naval_fleet_stress_smoke.gd` (new): 290 fleets / 870 ships across 10 synthetic countries at 29 real N0.3 fixture ports (grouping ports by owner so move orders target a friendly, dockable destination - exactly what `MoveFleetCommand.validate()` requires), half the fleets started pre-damaged so repair is genuinely exercised, 116 fleets given cross-port move orders so `FleetMovementSystem`'s per-leg revalidation runs too. Ran through the real scheduler (`daily_systems`/`start_of_day_systems`/`monthly_systems`, the same registration `simulation_controller.gd` uses in production) for 30 days. After the run: no ship is lost, duplicated, or disagreeing with its fleet's own `ship_ids` list - correctness at scale, not just a timing number.
- **Performance.** The same stress smoke doubles as the performance capture, following N1.4's own precedent of a smoke-level timing guard rather than a certified budget: 30 days over 870 ships completed in ~3.7 seconds, comfortably inside a conservative 15-second guard. Not an approved N0 numerical target - that item remains open for N6, exactly as N1.4 already recorded for graph/pathfinding performance.

## Export evidence: confirmed blocked

Ran `godot --headless --path . --export-debug "Windows Desktop" <exe>` directly (the same command `run_all_tests.py`'s `export_and_start()` uses). It fails immediately with:

```
ERROR: Cannot export project with preset "Windows Desktop" due to configuration errors:
No export template found at the expected path:
C:/Users/franc/AppData/Roaming/Godot/export_templates/4.7.1.stable/windows_debug_x86_64.exe
No export template found at the expected path:
C:/Users/franc/AppData/Roaming/Godot/export_templates/4.7.1.stable/windows_release_x86_64.exe
```

`~/AppData/Roaming/Godot/export_templates/` exists but has no `4.7.1.stable/` subfolder - the export templates were never installed in this environment. Installing them means downloading Godot's export template package (several hundred MB) from the internet, which is outside this slice's scope to do unilaterally. What *was* done: `run_all_tests.py`'s `export_and_start()` required-file manifest (the list of paths the export log must contain, used to catch a file silently failing to package) gained the naval entries it was missing (`naval_hud.tscn`, `ship_definitions.json`, `naval_definitions.json`, `fleet_movement_system.gd`, `fleet_logistics_system.gd`) - so the moment export templates exist, this check is ready to run and will actually verify naval assets survive packaging, rather than needing yet another fix-up pass discovered after the fact.

## Deliberately simple / deferred

- **No fleet-organisation UI** (create/split/merge/transfer/set-home-port) - those commands and their `simulation_controller.gd` wrappers exist, but no button drives them yet. N2.3's own tests already prove the commands work; this slice prioritized the construction → fleet → move → save loop, which is the one the roadmap's exit gate actually names.
- Map/3D presentation for fleets (ship icons on the map, route previews, blockade visuals) is untouched - `NavalHUD` is a 2D debug panel only, matching "final styling waits for N6."
- Export evidence itself remains open, blocked on an environment change (installing export templates) outside this slice.
