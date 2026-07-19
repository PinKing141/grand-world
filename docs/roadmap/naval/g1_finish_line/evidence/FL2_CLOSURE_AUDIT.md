# FL2 Closure Audit and Scope Reconciliation

**Status:** Audit complete. This document corrects an overstatement in earlier FL2 evidence: FL2.1, FL2.2, FL2.3, FL2.4, and FL2.6 were previously marked "complete" or "core complete" after building specific new controls (split/merge/transfer, home port, targeted return-to-port), without re-verifying the *pre-existing* claims those packets were layered on top of. This audit re-checked every bullet in [02 - FL2 Complete Fleet Management](../02_FL2_FLEET_MANAGEMENT.md) against the actual code, not against an earlier summary. It found substantially more open work than previously recorded, including one real correctness issue (not just a missing feature).
**Method:** `scripts/ui/naval_hud.gd` (942 lines) read in full; every FL2 bullet checked against actual function bodies and grep results across `scripts/simulation/`, not assumed from a prior pass.

## Correction to prior status claims

The previous status line read: *"FL2.1, FL2.4, and FL2.6 were already complete from earlier N-pillar work. FL2.2 (split/merge/transfer) and the core of FL2.3 ... are now complete."* This was wrong for FL2.1, FL2.4, and FL2.6 - none of those three were actually re-checked before being carried forward as "complete"; they were inherited from an earlier, shallower summary that only confirmed "the dropdown/list shows something," not that every named field/behaviour was present and correct. `02_FL2_FLEET_MANAGEMENT.md` and the README have been corrected to match this audit's findings, not the prior claim.

## One genuine correctness issue (not a missing feature) - fixed

**Transport capacity shown in the fleet panel used the wrong number.** `naval_hud.gd` displayed `aggregate.total_transport_capacity` (the *raw*, damage-inclusive total from `FleetSystem.recompute_aggregate()`) and a hand-rolled reserved-capacity sum, instead of calling the authoritative `TransportSystem.usable_capacity()` / `reserved_capacity()` functions `CreateTransportOperationCommand.validate()` (via `available_capacity()`) itself uses. A fleet with damaged carriers (below the 50% hull threshold `TransportSystem` excludes) could show a capacity number in the panel the fleet could not actually deliver - the display and the command's own legality check disagreed. **Fixed**: `_refresh_fleet_details()` in `scripts/ui/naval_hud.gd` now calls `TransportSystemScript.usable_capacity()`/`reserved_capacity()` directly instead of reading the cached aggregate field. Regression-tested in `tests/naval_hud_integration_smoke.gd`, which damages a fleet's only carrier below the threshold and confirms the panel now shows zero usable capacity, then confirms it recovers once hull is restored.

## Genuinely missing (FL2's own job, not blocked on another slice)

### FL2.1 Fleet summary and selection
- ~~Fleet **display name** is never read or shown anywhere~~ - fixed: the panel now shows `fleet.display_name`, falling back to the raw `fleet_id` when it's empty. See [FL2_1_FLEET_SUMMARY_PANEL.md](FL2_1_FLEET_SUMMARY_PANEL.md).
- ~~**Owner** is never shown as text~~ - fixed: resolved via `simulation_controller.country_registry.display_name()`, the same query `country_label_layer.gd` already uses.
- ~~**Admiral** is shown as a raw character ID~~ - fixed: resolved through a new `_admiral_display_name()` helper, matching the exact "name, falling back to the ID" convention `_populate_admiral_options()`'s own dropdown already used, so the summary and the picker never disagree.
- ~~**Location** and **home port** are shown as raw province IDs~~ - fixed: both now go through `_province_name()`, like every other province reference in this file.
- ~~**Route** (remaining path) and **arrival day** are never shown as panel text at all~~ - fixed, and corrected in the process: the panel now shows the untraversed route (`remaining_path[path_index:]`, resolved to names) plus two distinct days - "next waypoint arrival" (`next_arrival_day`, which is *not* the final ETA) and a real "final ETA" computed by a new `FleetSystem.route_completion_day()` query that sums the remaining known legs.
- ~~**Ship class breakdown** is absent at every layer~~ - fixed: `FleetSystem.recompute_aggregate()` now computes deterministic `family_counts` (one entry per `ShipDefinitions.ship_families()`, always present even at zero), shown in the panel and reused by a new `class_counts_for_ships()` query for the FL2.2 organisation preview.
- ~~**Crew** has no aggregate field to display at all~~ - fixed: `recompute_aggregate()` now computes `crew_readiness_bp`, a sailor-cost-weighted average of per-ship `crew_bp` (not a flat average - an undercrewed war galley should move the fleet number more than an equally undercrewed transport cog).
- ~~**Repair state** ... is never surfaced~~ - fixed: a new `FleetLogisticsSystem.repairing_ship_count()` query reads the same per-ship `repairing` flag `_repair_one_ship()`/`_apply_attrition()` already maintain, shown as "Repairing X/N ships" independent of the mission tag.
- ~~**Selection survival on fleet destruction**~~ - fixed: `_refresh_fleet_options()` now explicitly falls back to `fleet_ids[0]` (the sorted-first survivor) when the previous selection is gone, instead of leaving the outcome to an undocumented engine default. See [FL2_1_FLEET_SUMMARY_PANEL.md](FL2_1_FLEET_SUMMARY_PANEL.md)'s follow-up section.
- **Transport capacity reuse**: see the correctness issue above - fixed in the prior packet.

### FL2.4 Missions and targets
- **Target picker exists for exactly one mission** (`return_to_port`, built in the prior packet). No sea-zone/port/coast/fleet/transport-operation picker exists for any other mission.
- **Save validation gap**: `_validate_naval_data()` never checks `mission`, `mission_target_ids`, or `mission_started_day` at all - a save with a stale/out-of-range target province would load without complaint (not a crash risk today, since `FleetMissionSystem` re-validates the target's legality every time it's used, but it is untested and unvalidated at the structural level every other fleet field gets).
- **"Why a mission cannot continue"** has no feedback path for a mission that silently does nothing (see the inert-missions finding below) - there's no failure to report because the system never engages with the tag at all.

### FL2.6 Transport workflow integration
- ~~**Required and missing capacity are not shown proactively**~~ - fixed: reserved capacity is shown per operation, and a persistent required/available preview is shown for the selected army regardless of pass/fail. See [FL2_6_TRANSPORT_WORKFLOW.md](FL2_6_TRANSPORT_WORKFLOW.md).
- ~~**No fleet-army-operation cross-navigation**~~ - fixed for the common single-operation case via a new "Focus carried army" button; multi-operation fleets are explicitly out of scope (disabled with a tooltip, not guessed).
- ~~**Route ... absent**~~ - fixed: a sailing operation's real, already-authoritative `planned_path` is now shown resolved to names. **Danger remains absent** - no player-facing risk query exists to build it from; deliberately deferred, not silently dropped.
- ~~**No cancellation-consequence tooltip**~~ - fixed, and a real bug found in the process: the cancel button was never offered for a `disembarking` operation even though `CancelTransportOperationCommand.validate()` has always accepted that state - also fixed.
- ~~**Battle-pause, recovery, and peace UI preservation are unverified assumptions**~~ - fixed: `war_declared`/`peace_signed`/`military_access_changed` now trigger a full panel refresh, matching `war_hud.gd`'s own existing hookup for the same three events.

## Genuinely deferred to another slice (not FL2's job)

- **`patrol`, `intercept`, `protect_transport`, `protect_coast`, `trade_protection` have no real simulation behaviour** to build a target picker or completion condition for. `patrol`/`intercept`/`protect_transport` contribute a flat, static bonus to one combat-positioning formula and nothing else - no assignment logic, no completion condition, no target concept. `protect_coast` and `trade_protection` are fully inert: the dropdown accepts them, `SetFleetMissionCommand.apply()` tags the fleet, and nothing in the simulation ever reads the tag again. `none` is *worse* than inert - a fleet tagged `mission == "none"` (as opposed to `"idle"`) is invisible to both `FleetMissionSystem` and `NavalAISystem`'s reassignment triggers, effectively parking it in a state nothing will ever revisit.

  This is correctly out of FL2's scope: [03 - FL3 Naval AI Completion](../03_FL3_NAVAL_AI_COMPLETION.md) FL3.4 explicitly owns "Score patrol, interception, coast protection, blockade, escort, repair, retreat and idle-return candidates," and [05 - FL5 Strategic Contract Closeout](../05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md) FL5.1 explicitly owns the trade-protection *output* trade_protection would need to mean anything. FL2 (a UI-only slice) cannot sensibly build a target picker or completion condition for a mission mechanic that doesn't exist yet - that would be presenting a control that lies about doing something. **Recommendation: FL2.4's own exit bar should be read as "expose every mission that has real behaviour, with the correct target/completion feedback for each," not "invent simulation mechanics FL3/FL5 own."** The roadmap doc has been annotated to say this explicitly rather than silently mark FL2.4 "complete."

- **`ScuttleFleetCommand`** (FL2.5) - no such command exists anywhere in the simulation layer. Confirmed blocked on missing simulation work, not a UI gap. Addressed in a following packet (see [FL2_5_SCUTTLE_COMMAND.md](FL2_5_SCUTTLE_COMMAND.md) once written).

- **Maintenance-posture *control*** (FL2.3) - already correctly flagged as open in the FL2.3 evidence doc; no command exists to set it, only to display it. Confirmed still accurate by this audit.

- **FL2.2's aggregate-preview bullet** ("Preview the resulting class mix, speed, capacity and mission impact") - already correctly flagged as open in the FL2.2 evidence doc. Confirmed still accurate; also depends on the same class-breakdown data FL2.1 is missing, so these two gaps should likely be closed together in a future packet.

## What this means for FL2's status

Every genuinely-missing gap this audit found (FL2.1 in full, FL2.6 except "danger") has since been closed across the packets below, plus two real correctness bugs (transport capacity, disembark cancellation) found and fixed along the way. FL2.4's own remaining work - honest picker feedback for `patrol`/`intercept`/`protect_transport`/`protect_coast`/`trade_protection`, plus the save-validation gap - is now also closed, once FL3.4 and FL5.1 delivered the simulation behaviour those missions needed. See [FL2_4_MISSION_PICKER_HONESTY.md](FL2_4_MISSION_PICKER_HONESTY.md). FL2 is complete.

## Recommended next packets (in order)

1. ~~Fix the transport-capacity correctness issue~~ - done, see above.
2. ~~Build `ScuttleFleetCommand` per the safety rules defined for that packet (FL2.5)~~ - done, see [FL2_5_SCUTTLE_COMMAND.md](FL2_5_SCUTTLE_COMMAND.md).
3. ~~Fleet-panel display gaps (name, resolved location/home-port names, admiral name, route/arrival text, class breakdown, repair state)~~ - done, see [FL2_1_FLEET_SUMMARY_PANEL.md](FL2_1_FLEET_SUMMARY_PANEL.md). Note: owner and crew readiness were added in the same packet even though the original recommendation above omitted them, since FL2.1's own exit bar explicitly requires both.
4. ~~Transport-workflow gaps (required/missing capacity display, cross-navigation, cancellation tooltip)~~ - done, see [FL2_6_TRANSPORT_WORKFLOW.md](FL2_6_TRANSPORT_WORKFLOW.md). "Danger" remains explicitly deferred (no player-facing risk query exists to build it from).
5. ~~Selection-survives-destruction~~ - done, see [FL2_1_FLEET_SUMMARY_PANEL.md](FL2_1_FLEET_SUMMARY_PANEL.md)'s follow-up section.
6. ~~FL2.4's mission-picker follow-through, once FL3.4/FL5.1 shipped~~ - done, see [FL2_4_MISSION_PICKER_HONESTY.md](FL2_4_MISSION_PICKER_HONESTY.md).

FL2 has no open work of its own remaining.
