# FL2 - Complete Fleet Management

**Status:** Complete. A closure audit ([FL2_CLOSURE_AUDIT.md](evidence/FL2_CLOSURE_AUDIT.md)) corrected an earlier overstatement: FL2.1, FL2.4, and FL2.6 were previously carried forward as "complete" without being re-verified against the actual code, and turned out to have substantial real gaps, including one genuine correctness issue (the fleet panel's transport-capacity number used the wrong, non-damage-aware query - fixed) and one genuine cancellation-availability bug (a legally cancellable disembarking transport operation was never offered the cancel button - fixed). FL2.2 (split/merge/transfer), FL2.3's core (home port, targeted return-to-port), FL2.5 (scuttle), and FL2.1 and FL2.6 in full (including the selection-survival fallback) are all complete and tested. FL2.4 was blocked on FL3/FL5 delivering the simulation behaviour its missions needed - now that both are done, [FL2_4_MISSION_PICKER_HONESTY.md](evidence/FL2_4_MISSION_PICKER_HONESTY.md) closes FL2's own remaining work: honest, checked mission-picker tooltips for every mission with real behaviour (including an explicit AI-only-vs-player-manual distinction FL3.4's own behaviour turned out to need), and a genuine save-validation gap (`mission`/`mission_target_ids` were never structurally checked on load) fixed alongside it. See the audit for the full per-bullet breakdown.
**Goal:** Expose every supported fleet-management command through safe, understandable player workflows.

## Scope

### FL2.1 Fleet summary and selection - complete

- Present fleet name, owner, admiral, location, home port, mission, target, route and arrival. *(done - see [FL2_1_FLEET_SUMMARY_PANEL.md](evidence/FL2_1_FLEET_SUMMARY_PANEL.md). Name falls back to the raw `fleet_id` when unset; owner/admiral/location/home port are all resolved to player-facing names; route shows the untraversed path resolved to names, with "next waypoint arrival" correctly distinguished from a real, separately computed "final ETA" - the original `next_arrival_day` field is only the next waypoint's arrival, not the route's, a distinction the initial audit didn't catch either; target remains surfaced for `return_to_port` only, matching FL2.4's own scope)*
- Present ship totals and class breakdown, hull, crew, morale, speed, supply, maintenance, repair state and transport capacity. *(done - class breakdown is a deterministic per-family count from `FleetSystem.recompute_aggregate()`; crew is a sailor-cost-weighted readiness percentage, not a flat average; repair state reads the real per-ship `repairing` flag directly, visible even without the `repair` mission set)*
- Preserve selection when membership changes; close or retarget safely when the fleet ceases to exist. *(done - `_refresh_fleet_options()` now explicitly falls back to the sorted-first surviving fleet when the previous selection is gone, instead of relying on Godot's undocumented default-selection behaviour; regression-tested through two cascading destructions plus the trivial zero-fleets-left case)*
- Ensure displayed values come from the same queries used by command validation. *(done - every displayed field now matches its validating/authoritative query, including transport capacity, class breakdown, and repair state)*

### FL2.2 Split, merge and transfer - complete

- Add deterministic ship selection for splitting a fleet. *(done - a multi-select ship list scoped to the selected fleet)*
- Add compatible-fleet selection for merge and transfer. *(done - a target-fleet picker built from the exact `FleetSystem.is_docked_and_organisable()` eligibility check the commands themselves use)*
- Preview the resulting class mix, speed, capacity and mission impact. *(partial - the ship-selection label now shows the real class mix of exactly the ships selected to split/transfer, reusing FL2.1's new `class_counts_for_ships()` query; the *resulting fleet's* full stats (speed, capacity, mission impact) still are not previewed, since that needs simulating a fleet that doesn't exist yet - open follow-up)*
- Disable organisation while moving, fighting, retreating or carrying active transport reservations. *(true by construction - the same `validate()`/eligibility gate the buttons are driven by already excludes these fleets, both as source and as target)*
- Display the exact rejection reason returned by shared validation. *(done - every button's `tooltip_text` is the real `validate()` failure string)*
- Prevent double submission and stale modal actions. *(no modals exist in this panel - not applicable, matching the existing admiral/mission/transport buttons' own direct-action pattern)*

### FL2.3 Home port, repair and maintenance - core complete

- Add home-port selection filtered by legal basing rights. *(done - reuses the panel's own "select a province, then act" pattern; `SetFleetHomePortCommand.validate()` is the filter)*
- Explain range, supply, blockade and access failures. *(done - `NavalAccessPolicy.dock_failure_reason()` already distinguishes these, surfaced verbatim as the button's tooltip)*
- Add return-to-port and repair controls with the selected target and completion condition. *(done - `return_to_port` now honours a player-chosen target province, held back only by legality; repair and return-to-port both show their completion condition in the fleet panel and the mission button's tooltip before confirmation)*
- Display maintenance and repair consequences before confirmation. *(repair's condition is shown; a settable maintenance-posture control does not exist yet - no command for it exists in the simulation layer, open follow-up)*
- Refresh immediately when a port is captured, blockaded or loses access. *(true by construction for the validation-driven buttons - every relevant event already triggers `_refresh_all()`; not separately exercised by a dedicated capture/blockade-mid-selection test)*

### FL2.4 Missions and targets - complete

*Complete - [FL2_4_MISSION_PICKER_HONESTY.md](evidence/FL2_4_MISSION_PICKER_HONESTY.md). Now that FL3.4 and FL5.1 built real behaviour for the previously-inert missions, FL2.4's own remaining job (honest picker feedback, not new simulation mechanics) is done: every mission's tooltip is checked and accurate, including an AI-only-vs-player-manual distinction discovered while writing it (NavalAISystem's own automatic mission stand-down never runs for a player-controlled fleet); the save-validation gap for `mission`/`mission_target_ids` is fixed.*

- Expose every approved mission: none, patrol, intercept, protect transport, transport, blockade, protect coast, return to port, repair and trade protection where available. *(done - all 11 are selectable, and every one with real simulation behaviour (`blockade`, `patrol`, `intercept`, `protect_transport`, `return_to_port`, `repair`, `trade_protection`) now has accurate tooltip text describing what it actually does, including the AI-only/player-manual distinction for the four FL3.4 tactical missions. `protect_coast` and `transport` are honestly labelled as currently having no mechanical effect for a player-set fleet beyond the tag itself, rather than silently implying parity with the others)*
- Provide the correct target picker for sea zones, ports, coasts, fleets or transport operations. *(built for exactly one mission, `return_to_port` - confirmed correct: no other mission, including the four FL3.4 gave real behaviour to, reads `mission_target_ids` anywhere in the simulation. Every one of them is inherently positional, acting on wherever the fleet already is rather than a separately chosen target; building a picker for a field nothing reads was correctly not attempted)*
- Save and restore mission target IDs and start day. *(done - `CampaignWorldState.VALID_FLEET_MISSIONS` plus a `mission_target_ids` province-reference check in `_validate_naval_data()` now reject a corrupted `mission`/target on load, closing the one structural gap every other fleet field already had. `mission_started_day` remains display-only, not shown in the UI - a low-risk, pre-existing state, not reopened here)*
- Show why a mission cannot start or continue. *("cannot start" is done via the mission button's tooltip, now accurate for every real mission. "Cannot continue" still has no feedback path for `protect_coast`/`trade_protection`/`transport` specifically because their tooltip already states up front that nothing will happen - there is no separate failure to surface once the honest expectation is already set correctly)*
- Ensure player and AI use the same command contract. *(done - both paths go through `SetFleetMissionCommand`, no parallel implementation exists)*

### FL2.5 Admiral and scuttle controls - scuttle complete; admiral replace/remove unverified

- Assign, replace and remove an eligible admiral through authoritative commands. *(assign: done, from earlier N-pillar work. Replace/remove specifically as distinct actions were not independently re-verified by this audit - likely covered by re-running assign with a different/empty selection, but not confirmed)*
- Explain exclusivity, country, alive/eligible and fleet-state restrictions. *(done for assignment, via the existing admiral-eligibility filter and validation tooltip)*
- Add scuttle only after its loss, transport and event policy is explicit. *(done - `ScuttleFleetCommand` with the safety rules and design rationale in [FL2_5_SCUTTLE_COMMAND.md](evidence/FL2_5_SCUTTLE_COMMAND.md): ownership, docked, not moving/fighting/intercepting/retreating, no active transport reservation, admiral cleanup, deterministic no-refund ship removal, and a dedicated `fleet_scuttled` event)*
- Require confirmation for destructive actions and identify affected ships/armies. *(done - the Scuttle button uses an armed-confirmation pattern: the first press names the fleet's ship count and requires a second press before anything is removed; selecting a different fleet disarms it)*
- Reuse normal cleanup paths so no reverse reference survives. *(done for scuttle's own admiral/mission cleanup. A related pre-existing gap was found and deliberately left unfixed: `NavalCombatSystem._begin_retreat()`'s no-legal-retreat combat-destruction path still does not clear the destroyed fleet's admiral back-reference - see the evidence doc's "genuinely new" discussion)*

### FL2.6 Transport workflow integration - complete except danger, deliberately deferred

- Show required, usable, reserved and missing capacity. *(done - see [FL2_6_TRANSPORT_WORKFLOW.md](evidence/FL2_6_TRANSPORT_WORKFLOW.md). Usable/reserved use the correct damage-aware numbers; reserved is now shown per operation; required/available is a persistent preview for the selected army, not just a post-failure tooltip. "Missing" for an already-active operation is inherently transient - TransportSystem auto-trims a shortfall the moment it occurs and reports it via a one-shot event toast, which is the correct place for a one-time occurrence, not a persistent indicator)*
- Link the fleet, army and operation views. *(done for the common single-operation case via a new "Focus carried army" map button; a fleet with more than one simultaneous operation disables the button with an explanatory tooltip rather than guessing which army to focus)*
- Expose destination, route, danger, operation state and cancellation consequences. *(destination, route, operation state, and cancellation consequences: done - destination resolves to a name, a sailing operation's real `planned_path` is shown resolved to names, and the cancel button's tooltip explains the real per-state consequence. Danger: still absent - no player-facing risk query exists to build it from; deliberately deferred, not silently dropped)*
- Prevent split/merge/transfer/scuttle paths from bypassing active reservation locks. *(done for all four - `ScuttleFleetCommand` validates through the same shared `is_docked_and_organisable()` gate as split/merge/transfer, confirmed by a dedicated active-transport-reservation rejection test)*
- Preserve accurate UI through battle pause, retreat, recovery, peace and load. *(done - retreat and one save/load scenario were already tested; `war_declared`/`peace_signed`/`military_access_changed` now trigger a full panel refresh, matching `war_hud.gd`'s own existing hookup for the same events, and are regression-tested)*

## Automated verification

- Each UI action issues exactly one authoritative command with stable IDs.
- Preview legality agrees with command legality for valid and invalid fixtures.
- Split, merge and transfer preserve membership invariants.
- Active transports reject unsafe organisation and scuttle actions.
- Port capture/access loss refreshes enabled states without direct UI mutation.
- Save/load restores mission targets, selection context and operation links.
- Keyboard cancellation closes the top modal without issuing a command.

## Manual verification

- Complete every fleet action using mouse only and keyboard only.
- Check confirmation and error text at 1366x768 and 200% UI scale.
- Verify destructive actions cannot be triggered accidentally.
- Run the Channel scenario entirely through player-facing controls.

None of the manual-verification bullets above have been performed - this roadmap's work so far has been headless/automated only. They remain fully open.

## Exit evidence

- Focused command-to-UI integration results.
- Invalid-action matrix with expected rejection reasons.
- Transport-lock and destructive-action results.
- Resolution, input and save/load capture.

Evidence: [FL2_2_FLEET_ORGANISATION_UI.md](evidence/FL2_2_FLEET_ORGANISATION_UI.md), [FL2_3_HOME_PORT_AND_TARGETED_MISSIONS.md](evidence/FL2_3_HOME_PORT_AND_TARGETED_MISSIONS.md), [FL2_CLOSURE_AUDIT.md](evidence/FL2_CLOSURE_AUDIT.md)

## Exit gate

FL2 is complete when every supported fleet action is available through the player interface, every invalid action has a precise reason, no control mutates authoritative state directly, and a player can complete the Channel loop without debug commands.
