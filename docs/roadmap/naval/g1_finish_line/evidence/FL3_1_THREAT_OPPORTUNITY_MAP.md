# FL3.1 - Threat and Opportunity Map

**Status:** Complete. Targeted tests pass (see Verification).
**Satisfies:** the FL3.1 findings recorded in [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md) - the cache, its revision/invalidation contract, three of the four still-missing raw inputs (friendly support, recent battles, transport stakes), and the FL3.6 counters the audit flagged as buildable alongside it (cache hits/rebuilds, countries planned).

## What shipped

A new `scripts/simulation/naval_threat_map.gd` (`class_name NavalThreatMap`), replacing `naval_ai_system.gd`'s old single-purpose `_zone_threat()` int query with a cached, seven-component assessment:

- `hostile_power` - unchanged from before this packet (direct-zone fleets weighted full, one-hop-neighbour fleets weighted half), moved verbatim rather than rewritten.
- `friendly_power` - **new**: this country's own and allied fleets physically present in the zone right now. "Friendly support" from the roadmap's FL3.1 input list.
- `recent_battle_bp` - **new**: a linear decay from full weight (a battle started in this zone today) to zero at `RECENT_BATTLE_WINDOW_DAYS` (30) ago, reusing `naval_battle_registry`'s own `zone_id`/`start_day` fields directly - no new persisted history was needed, N4's battle record already carried both. "Recent battles" from the roadmap's list.
- `has_blockade_target` - unchanged logic, moved verbatim from the old `_zone_has_blockade_target()`.
- `transport_stake` - **new**: the summed `reserved_capacity` of this country's own transport operations whose `current_location_id` is this zone right now - "transport stakes" from the roadmap's list, using a field `TransportSystem` already updates daily.
- `supply_days` - **new**: days to the nearest port this country may legally base at, via the existing `NavalAccessPolicy.supply_range_query()`, bounded by `FleetLogisticsSystem`'s own `SUPPLY_RANGE_DAYS` (5) rather than a new, uncalibrated distance scale. "Supply distance" from the roadmap's list - and deliberately absorbs the list's separate "ports" input too (a redundant second "is a port nearby" signal would add nothing `supply_days` doesn't already answer better).
- `threat_score`/`opportunity_score` - one reasonable first-slice combination of the above (documented in-code as "not an approved N3/N6 budget"), kept separate from the raw components so FL3.2's richer posture work or FL3.4's effective-power tactical scoring can recombine the same inputs differently without touching how any one of them is computed.

`_zone_threat()` and `_zone_has_blockade_target()` in `naval_ai_system.gd` are now thin adapters over `NavalThreatMap.assess()` - same signatures, same call sites, so `_consider_retreat()`, `_consider_blockade_or_evade()`, and every existing test that calls either function directly needed zero changes.

## Cache design

**Contract:** an assessment is valid for the exact game-day it was computed on, or until `NavalThreatMap.invalidate(world)` bumps `world.global_counters["naval_zone_revision"]` - whichever comes first. Cache entries are keyed by `"<country_tag>:<zone_id>"`, each storing `{day, revision, assessment}`; a lookup is a hit only if both the stored day and revision still match.

**Why day-boundary invalidation alone satisfies "invalidation for fleet, war, access, ownership and port changes"**: every command that could change one of those five categories applies through `SimulationScheduler.process_commands()` *before* any given day's AI tick runs (confirmed against `simulation_controller.gd`'s scheduler ordering). A cache that never survives past the day it was built can therefore never serve a value that predates a command's effect - it only ever gets populated fresh after that day's commands have already landed. This is the same "recompute from live state" trust `BlockadeSystem`'s own query layer established, now with an actual cache layered on top rather than recomputing from scratch on every single call within the day.

**What this does not cover**: true intra-day, event-triggered invalidation - a change the AI itself makes mid-tick that should invalidate a *different* zone's assessment before that same tick's later queries reach it. `NavalThreatMap.invalidate()` exists as the hook a future caller can use for this (nothing calls it yet, which is an honest statement of today's scope). This gap is the same one the closure audit already recorded under FL3.4 ("avoid daily full replanning... event-triggered invalidation... does not exist at all") - not re-opened here, tracked in one place.

## Counters (FL3.6, built alongside)

Three new deterministic, checksummed counters in `world.global_counters`, following the exact shape `naval_ai_commands_submitted`/`naval_ai_decisions` already established (plain integer tallies of simulation events, never wall-clock time - see below):

- `naval_zone_cache_hits` / `naval_zone_cache_rebuilds` - incremented inside `NavalThreatMap.assess()`, directly demonstrating the cache is doing real work, not just present.
- `naval_ai_countries_planned` - incremented once per country actually visited in `NavalAISystem.process_day()`'s loop (past the maritime-capable and nothing-due skips), distinct from `naval_ai_decisions` (which counts individual decisions, not countries).

**"Elapsed time" was deliberately not added as a counter.** `CampaignWorldState.checksum()` includes `global_counters` verbatim - any wall-clock-based value stored there would make two runs of the identical simulation at different real speeds produce different checksums, breaking the exact determinism guarantee `tests/naval_ai_test.gd`'s own two-instance replay check exists to prove. A timing/performance budget belongs at the test-harness level instead (the same pattern `naval_fleet_stress_smoke.gd` and `naval_battle_blockade_stress_smoke.gd` already use, measuring outside checksummed state) - noted as still open in the closure audit's recommended packet 6, not attempted here.

## Verification

- `tests/naval_threat_map_test.gd` (new): cache-hit-vs-rebuild counting (including that a different zone or country is correctly its own cache entry, not a false hit); day-boundary invalidation (a new day rebuilds every entry with no other world change); explicit `invalidate()` forcing a same-day rebuild; `hostile_power`/`friendly_power` correctness including an allied third country's fleet counting as friendly support; `recent_battle_bp`'s decay curve (a fresh battle at full weight, a battle older than the window at exactly zero); `transport_stake` correctness (an operation's stake counts only in its own current zone, not elsewhere); `supply_days` non-negative for two different countries each with a nearby owned port; and a genuine two-independent-instance determinism check against identically-constructed worlds.
- `tests/naval_ai_threat_test.gd` (pre-existing, unmodified): re-run clean - both tactical decisions (evade/blockade) it proves still work unchanged through the new adapter functions.
- `tests/naval_ai_test.gd` (pre-existing, unmodified): re-run clean, including its own genuine two-instance 215-day replay + checksum comparison against the real 29-port Iberian fixture - confirms the new cache and counters do not introduce any nondeterminism.
- `tests/naval_ai_organisation_test.gd`, `tests/naval_ai_transport_test.gd` (pre-existing, unmodified): both re-run clean, confirming no other naval-AI behaviour was disturbed.
- Registered in `tools/testing/run_all_tests.py`.
- Broader naval regression (`naval_combat_test`, `naval_blockade_test`, `naval_battle_blockade_stress_smoke`, `naval_destructive_edge_gate_test`, `naval_channel_release_gate_test` - the 100-seed Channel replay gate) re-run to confirm reading `naval_battle_registry`/`transport_operation_registry` from a new query location didn't disturb any existing battle, blockade, or transport behaviour.

## Deliberately out of scope for this packet

- **Event-triggered intra-day invalidation** - the cache's own `invalidate()` hook exists for this; nothing calls it yet. Tracked under FL3.4 in the closure audit, not duplicated here.
- **Naval visibility/fog-of-war filtering** - confirmed (again) that no such system exists anywhere in this codebase, for naval or land AI; not a naval-specific gap, not attempted.
- **Recombining `threat_score`/`opportunity_score` into FL3.2's richer posture classification or FL3.4's effective-power tactical scoring** - this packet provides the raw inputs and one first-slice combination; consuming them more richly is exactly the closure audit's recommended packets 2 and 3.
