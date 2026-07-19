# FL2.3 - Home Port, Repair and Maintenance

**Status:** Core complete and verified - this packet's own scope (home port, targeted return-to-port, completion-condition text) is accurately described below and remains correct. See [FL2_CLOSURE_AUDIT.md](FL2_CLOSURE_AUDIT.md) for the corrected, full picture of FL2 as a whole: several sub-scopes this packet was built alongside (FL2.1, FL2.4, FL2.6) were carried forward as "complete" without being re-verified and turned out to have real gaps this doc does not cover.
**Satisfies:** FL2.3 ("Home port, repair and maintenance") from [02 - FL2 Complete Fleet Management](../02_FL2_FLEET_MANAGEMENT.md).

## What was found before implementation

`SetFleetHomePortCommand` already existed at the simulation layer with a working `validate()`/`apply()`, and `simulation_controller.gd` already exposed a one-line `set_fleet_home_port()` wrapper - identical shape to FL2.2's own pre-existing, unused command surface. No home-port control existed anywhere in `naval_hud.tscn`/`naval_hud.gd`. Separately, `repair` and `return_to_port` were already selectable through the existing generic mission dropdown (`SetFleetMissionCommand.VALID_MISSIONS` already carried the full list, and `FleetMissionSystem` already drove both missions' actual daily behaviour) - so "return-to-port and repair controls" were functionally already in the player's hands before this packet. The real gap, matching the roadmap's own phrasing, was narrower than it first read: **"with the selected target and completion condition"** - no target-port choice existed for `return_to_port` (the system always auto-picked the nearest legal port, silently ignoring the `mission_target_ids` field `SetFleetMissionCommand` already accepted and persisted), and no completion condition was shown anywhere in the fleet panel for either mission.

## What was built

### Home port (new UI, no simulation change needed)

`_refresh_home_port_validation()`/`_set_selected_fleet_home_port()` reuse the exact same "select a province on the map, then act" pattern Move and Embark already established in this panel, rather than a separate port-picker dropdown - press "Set home port" with a province selected, and `SetFleetHomePortCommand` (whose `validate()` already routes through `NavalAccessPolicy.dock_failure_reason()`, distinguishing range/supply/blockade/access failures in its own returned text) either applies or explains why not via the button's tooltip. The fleet panel was also found to never display the fleet's current `home_port_id` at all despite FL2.1 (marked complete in an earlier packet) asking for it - fixed alongside this work as a one-line correction, not a separate packet.

### Targeted return-to-port (a small, backward-compatible simulation completion)

`fleet_mission_system.gd`'s `_process_return_to_port_mission()` now prefers `fleet.mission_target_ids[0]` over the auto-picked nearest port, but only when that target is itself a legal dock for the fleet's owner - an empty or illegal target falls through to the exact original auto-pick behaviour, so AI-assigned `return_to_port` (which never sets a target) is completely unaffected. This is not new scope invented for this packet: `SetFleetMissionCommand` already accepted and persisted `target_ids` for every mission (used by `blockade` already); `FleetMissionSystem` simply never consumed it for `return_to_port`. Completing that existing plumbing was the actual gap, not a new mechanic.

`naval_hud.gd`'s `_set_selected_fleet_mission()` now passes the currently-selected province as the mission target specifically when the chosen mission is `return_to_port` (no other mission in the list currently consumes a target, so this stays narrowly scoped rather than always attaching whatever happens to be selected).

### Completion condition text

The fleet panel's mission line now reads, for example, `Mission Repair · completes at full hull (74% now)` or `Mission Return to port · target Kent`/`· target nearest legal port` - and the "Set mission" button's own tooltip previews the same information (which port it will target, or that repair completes at full hull) before the player confirms, matching FL2's own "display consequences before confirmation" and "show why a mission cannot start or continue" bullets.

## Deliberately not built in this packet

- **A dedicated home-port picker dropdown** (as opposed to reusing map-province selection): the reused pattern is consistent with every other action in this panel and was judged clearer than adding a second, differently-shaped control for the same "pick a province" concept.
- **Maintenance posture control**: `maintenance_posture_bp` is still display-only (shown in the fleet panel, never settable) - no command to change it exists in the simulation layer yet. A real, separate gap, left open.
- **Repair or return-to-port target selection for AI**: unaffected by design - `NavalAISystem` never sets `mission_target_ids` for `return_to_port`, so this remains exactly as deterministic/auto-picking as before for every AI-controlled fleet.

## Verification

`tests/naval_fleet_home_port_hud_test.gd` (new): a fixture fleet at Calais proves - the home-port button is correctly disabled with no province selected; selecting a legally basable owned province (Kent) enables it and setting it updates `fleet.home_port_id`, reflected back in the panel text; setting a `return_to_port` mission with a province selected persists that exact province as `mission_target_ids` (not silently dropped) and the panel/tooltip both name it; `FleetMissionSystem.process_day()` actually completes the mission once the fleet reaches its *chosen* target specifically. Registered in `run_all_tests.py`.

`tests/fleet_mission_system_test.gd` (pre-existing, re-run unmodified) continues to pass, confirming the auto-pick-nearest path for AI-issued, targetless `return_to_port` missions is unaffected by the new target-preference branch.

Full regression suite after the change: 72/73 (the sole remaining failure is the already-documented, unrelated FL8.2 hardware-blocked case). `naval_hud_integration_smoke.gd` and the full-scale G1 Channel/destructive-lifecycle release-gate tests all still pass unchanged.
