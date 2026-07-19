# N3.3 / N4.3 / N5.2 - Peace and Country-Extinction Naval Cleanup

**Status:** Country-extinction cleanup for every naval registry is complete and covered by a save-round-trip regression test. Peace-treaty disengagement of an in-progress naval battle remains open - see "Deliberately out of scope" below.
**Satisfies:** the extinction-cleanup portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N3.3, N4.3, and N5.2.
**Scope:** `CountryDepthSystem._reconcile_country_status()` already hard-erases an extinct country's armies directly from `army_registry`, with no equivalent sweep of the naval registries. This closes that gap for fleets, ships, transport operations, naval battles, and naval construction, plus two pre-existing save-validator bugs discovered while proving the fix with a real round trip.

## Why this was a real bug, not just untidy state

Every other N3/N4/N5 evidence doc flagged this the same way: "matches a pre-existing, undocumented-until-now gap... not a regression introduced by this slice, but also not fixed by it." Writing a test that actually forced a save round trip through this exact scenario showed the framing undersold it. Three of `CampaignWorldState`'s own structural validators already assume naval registries stay internally consistent after extinction, and none of them tolerated what extinction was actually leaving behind:

- `_validate_transport_data` rejects a transport operation whose `army_id` no longer resolves. `_reconcile_country_status` already erases the extinct country's armies directly (pre-existing behaviour, untouched by this slice) - so any army mid-transport at the moment its country died left a transport operation record pointing at nothing. **The very next save load would have failed outright.**
- `_validate_naval_battle_data` rejects an *active* battle whose `attacker_fleets`/`defender_fleets` names an unknown fleet. A fleet belonging to the extinct country, still marked as fighting, would dangle the same way if never removed from its battle's side.
- A fleet's admiral is a live character with `admiral_fleet_id` pointing at the fleet. Left uncleared after the fleet is erased, this doesn't fail validation (nothing walks that reference forward-only), but it does leave a real character permanently unable to be reassigned as an admiral anywhere, since `AssignAdmiralCommand` treats a non-empty `admiral_fleet_id` as "already commanding."

So an England-France Channel scenario where the loser is fully annexed mid-war, with even one fleet still at sea or one army still embarking, was already unsaveable before this change - not hypothetical, reachable by the existing N0-N5 systems today.

## What was built

`CountryDepthSystem._cleanup_extinct_country_references()` (`scripts/simulation/country_depth_system.gd`) now takes an `events: SimulationEventBus` parameter and, for the extinct tag:

1. **Transport operations** - every `transport_operation_registry` entry whose `country_tag` matches is closed with `events.transport_operation_army_lost.emit(operation_id, army_id, "country_extinct")` and erased. (`CreateTransportOperationCommand.validate()` already requires the army's owner, the fleet's owner, and `country_tag` to all agree, so filtering by `country_tag` alone is exhaustive - there is no cross-country transport case to miss.)
2. **Fleets and their ships** - for every fleet `country_fleets(extinct_tag)` returns: if it's the fleet's own battle and that battle is still `active`, the fleet is removed from whichever side lists it; if it has a living admiral, that character's `admiral_fleet_id` is cleared (mirroring the existing pattern `CharacterSystem.kill_character()` already uses for the reverse direction); every one of its ships is erased from `ship_registry`; then the fleet itself is erased, and `fleet_destroyed(fleet_id, "country_extinct")` fires - reusing the same signal (and the same "second parameter is really a reason string" precedent `NavalCombatSystem._begin_retreat`'s `"no_legal_retreat"` already established) other fleet-loss paths already use.
3. **Naval battles left one-sided by step 2** - status becomes `"completed"`, `end_day` is set, `winner_side` is whichever side still has fleets, and `naval_battle_ended` fires. This mirrors exactly how the pre-existing war-registry cleanup in the same function already ends a war outright when extinction empties one side, rather than routing through `NavalCombatSystem._finish_battle()` (which also touches war battle-score - deliberately not done here, matching the war-ending code's own choice not to touch battle-score either).
4. **Naval construction** - every `naval_construction_registry` entry whose `country_tag` matches the extinct tag is erased outright; an extinct country has no treasury or ports left to ever complete or refund it.

Two small validator fixes in `CampaignWorldState`, both needed to actually prove step 3 above round-trips:

- `apply_save_dict`'s war-participants check (`"War %s is missing participants."`) now only applies to `status == "active"` wars, matching the same "a completed record is a history snapshot, not a live index" reasoning `_validate_naval_battle_data`'s doc-comment already stated for battles - an ended war can legitimately have had one side emptied by extinction.
- `_validate_naval_battle_data`'s "must have at least one fleet on each side" check was firing unconditionally, *before* the `status != "active": continue` line - contradicting its own doc-comment ("only *active* battles require live reciprocity") and rejecting exactly the one-sided completed battle this cleanup now legitimately produces. Moved the empty-side check after the active-status guard so the code matches what the comment already promised.

## What was deliberately left alone

- **Land-side extinction cleanup (armies/commanders) is untouched.** `army_registry.erase()` still happens with no siege/commander-side cleanup, exactly as before - that's the land pillar's own pre-existing gap, out of scope for a naval slice. This change only guarantees naval registries stay consistent with land's *existing* (imperfect) behaviour, the same "don't make it worse, don't have to make it perfect" bar N3.3/N4.3/N5.2's own evidence docs already set.
- **Peace-treaty disengagement of an in-progress naval battle** - a war reaching `status == "ended"` via a normal peace treaty (not extinction) does not stop an already-active naval battle; `NavalCombatSystem._resolve_battles()` has no war-status check at all, only a battle-status one. This is a distinct, real gap from the extinction one just closed, and is out of scope here - it needs a decision about what "the war ended mid-battle" should even mean (does the battle finish anyway? forced mutual withdrawal?) that this slice did not make.

## Results (verified via `naval_country_extinction_test.gd`, exit 0, no errors)

A fixture with ENG owning Calais and an active war against FRA: an ENG army mid-embark (referenced by a live transport operation), an ENG fleet with an assigned admiral simultaneously carrying that operation *and* locked in an active naval battle against an FRA fleet. After `world.set_province_owner(CALAIS, "FRA")` (ENG loses its only province) and a direct call to `CountryDepthSystem._reconcile_country_status()`:

- ENG's `country_status` becomes `"extinct"` and its army is gone (pre-existing behaviour, confirmed still working).
- The transport operation is gone; `transport_operation_army_lost` fired once with reason `"country_extinct"`.
- The fleet and its ship are gone; `fleet_destroyed` fired once for the fleet.
- The admiral's `admiral_fleet_id` is cleared.
- The naval battle is `"completed"`, `winner_side == "defender"` (FRA, the side that still had a fleet); `naval_battle_ended` fired once.
- The naval construction record for ENG is gone.
- **`world.to_save_dict()` → `CampaignWorldState.new().apply_save_dict()` round-trips with an empty error string** - the actual regression this slice exists to prevent; before the fix this failed with "Transport operation ... references an unknown army," then (after just the transport/fleet/battle fix, before the two validator fixes) with "War war_1 is missing participants," then "Naval battle ... must have at least one fleet on each side."
- Re-ran the full naval/warfare/character/core regression set (`naval_admiral_test`, `naval_combat_test`, `naval_blockade_test`, `naval_transport_operation_test`, `naval_transport_recovery_test`, `naval_transport_gate_test`, `naval_fleet_state_test`, `naval_fleet_organisation_test`, `naval_fleet_movement_test`, `naval_fleet_logistics_test`, `naval_hud_integration_smoke`, `phase_5_warfare_test`, `phase_7_character_test`, `phase_8_country_depth_test`, `simulation_core_test`) after both validator changes - all still pass, confirming the relaxed checks didn't hide anything the active-war/active-battle cases still need.

## Files touched

- `scripts/simulation/country_depth_system.gd` - the cleanup sweep itself.
- `scripts/simulation/campaign_world_state.gd` - the two validator fixes.
- `tests/naval_country_extinction_test.gd` (new), registered in `tools/testing/run_all_tests.py`.
