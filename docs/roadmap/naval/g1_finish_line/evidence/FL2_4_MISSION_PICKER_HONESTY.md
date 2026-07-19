# FL2.4 - Missions and Targets Follow-Through

**Status:** Closed for what FL2 itself owns. Real, honest mission-picker feedback now exists for every mission FL3.4/FL5.1 gave real behaviour to, and the one genuine load-boundary correctness gap the closure audit flagged is fixed. The target-picker bullet itself needed no new control - see "Why no new target picker was built" below.
**Satisfies:** the remaining open items from [FL2_CLOSURE_AUDIT.md](FL2_CLOSURE_AUDIT.md)'s FL2.4 section, now that [FL3_4_TACTICAL_MISSIONS.md](FL3_4_TACTICAL_MISSIONS.md) and [FL5_1_TRADE_PROTECTION.md](FL5_1_TRADE_PROTECTION.md) have built the simulation behaviour the audit said FL2.4 was blocked on.

## What changed since the audit

The audit found `patrol`/`intercept`/`protect_transport` "contribute only a flat combat-positioning bonus with no assignment logic, completion condition, or target concept," and `protect_coast`/`trade_protection` "fully inert." Since then: FL3.4 gave `patrol`, `intercept`, `protect_transport`, and `protect_coast` real AI assignment and completion logic; FL5.1 gave `trade_protection` a real, queryable derived output. This packet re-checked the mission dropdown against that new reality rather than assuming it needed to catch up wholesale.

## What was found on re-check (a real, non-obvious distinction)

The new FL3.4 behaviour is AI-only, not shared with player-controlled fleets, and this was not obvious from the roadmap text alone - confirmed by reading `naval_ai_system.gd:106`, which explicitly skips `tag == world.player_country` in `process_day()`. This means:

- `_consider_mission_completion()` - the function that automatically stands a fleet down once its `patrol`/`intercept`/`protect_transport`/`protect_coast` reason no longer holds - **never runs for a player-owned fleet**. A player who sets one of these missions keeps it until they manually change it; only an AI country's own fleets get automatic reassignment.
- `NavalCombatSystem`'s flat per-mission combat modifier (`naval_combat_system.gd:464`) **does apply regardless of who set the mission tag** - `patrol`/`intercept`/`protect_transport`/`blockade`/`repair`/`return_to_port` all have a real entry. `protect_coast` and `trade_protection` do not appear in that dictionary at all - setting `protect_coast` on a player fleet currently has **zero** mechanical effect beyond the label itself; only an AI-controlled fleet's own positioning decision (which zone to sail to) does anything with it.

An earlier draft of this packet's tooltip text claimed "stands down automatically" for all four tactical missions unconditionally - wrong, caught before shipping, and corrected to state the AI-only/player-manual distinction explicitly rather than overclaiming a behaviour the player will not actually observe.

## Why no new target picker was built

None of `patrol`, `intercept`, `protect_transport`, `protect_coast`, `blockade`, or `trade_protection` read `fleet.mission_target_ids` anywhere in the simulation (grepped: only `return_to_port`'s handler in `fleet_mission_system.gd` ever reads that field, confirmed already true and unchanged since [FL2_3_HOME_PORT_AND_TARGETED_MISSIONS.md](FL2_3_HOME_PORT_AND_TARGETED_MISSIONS.md)). Every one of these missions is inherently **positional** - the fleet acts wherever the player has already sailed it, not toward a separately chosen sea zone, port, coast, or transport operation ID. Building a target-picker control for a field nothing reads would be exactly the "half-finished implementation" this project's own conventions warn against. If a future packet wants `protect_coast` to accept a player-chosen coastal target distinct from the fleet's current position, that is a simulation-layer change to `fleet_mission_system.gd` first, not a UI gap.

## What was built

- **Fleet panel mission line**: now shows a live `· power N` for `trade_protection` (via `NavalTradeProtection.effective_power()`), matching the existing `blockade` pattern exactly - this fleet's own contribution, not the country-wide zone total `NavalTradeProtection.assess()` would return.
- **Mission dropdown tooltip** (`_refresh_mission_validation()`): every one of the 11 missions now has real, checked text instead of falling through to blank for anything but `return_to_port`/`repair`:
  - `blockade` - what it does and its eligibility-gated effect (previously undocumented in the tooltip, though already shown in the fleet panel).
  - `patrol`/`intercept`/`protect_transport` - the real combat bonus, plus the explicit AI-automatic-vs-player-manual distinction above.
  - `protect_coast` - explicitly states it currently has no combat bonus and no automatic reassignment for a player fleet, rather than implying parity with the other three tactical missions.
  - `trade_protection` - explicitly states it has no gameplay effect yet, matching FL5.1's own "zero behavioural effect until a real consumer exists" framing.
  - `transport` - explicitly states the mission label alone does nothing; actual troop transport goes through Embark/`CreateTransportOperationCommand`, a separate path this label does not trigger.

## A genuine correctness gap fixed alongside this (not UI - save validation)

The closure audit separately flagged: "`_validate_naval_data()` never structurally validates either field on load - unlike every other fleet field, a stale/out-of-range target would load silently." Confirmed true by reading the function - every other fleet field (`owner_country_id`, `home_port_id`, `location_id`, `admiral_id`, `ship_ids`) is checked; `mission` and `mission_target_ids` were not. Fixed:

- `CampaignWorldState.VALID_FLEET_MISSIONS` - a duplicate of `SetFleetMissionCommand.VALID_MISSIONS`, not a preload of it: `commands/simulation_command.gd` already preloads `campaign_world_state.gd`, so preloading a command script back from `campaign_world_state.gd` would be a cycle. This mirrors the existing `FLEET_LOCATION_*`/`ARMY_STATUS_*` duplicated-enum pattern already used in the same file for the identical reason.
- `_validate_naval_data()` now rejects an unknown `mission` string and a `mission_target_ids` entry that is not a real province ID, closing the gap with no change to `fleet_mission_system.gd`'s own already-graceful handling of an illegal target (that fallback logic is unaffected and still correct for the cases that do pass validation, e.g. a target that becomes illegal only after load).

## Verification

- `tests/naval_hud_integration_smoke.gd` (extended): selecting `patrol` confirms the tooltip states a player fleet keeps the mission until changed (not an overclaimed auto-stand-down); selecting `trade_protection` confirms the tooltip states no gameplay effect yet.
- `tests/naval_save_schema_migration_test.gd` (extended): a save with an unknown fleet `mission` is rejected on load; a save with a `mission_target_ids` entry referencing an unknown province is rejected on load. Both new cases pass against the file's existing populated fixture.
- Full-project headless parse-check (`--headless --editor --quit`) re-run clean after every UI/simulation edit in this packet, per this session's own hard-won "grep for hidden SCRIPT ERROR/Parse Error, don't just trust a printed pass line" standard.

## Deliberately out of scope for this packet

- **A player-usable equivalent of `_consider_mission_completion()`** - giving a player fleet the same automatic stand-down an AI fleet gets would be a real simulation-layer behaviour change (should idle-out be opt-in? silent? notified?), not a UI-only follow-through; left as an explicit, named open question rather than assumed either way.
- **A combat-modifier entry for `protect_coast`** - the tooltip now honestly states this gap rather than silently implying parity with `patrol`/`intercept`/`protect_transport`; whether `protect_coast` *should* carry a modifier is a balance question, not this packet's to decide.
- **FL2.3's still-open maintenance-posture control and FL2.2's resulting-fleet-stats preview** - both already tracked as open in their own evidence docs; unrelated to the mission-picker gap this packet closes.
