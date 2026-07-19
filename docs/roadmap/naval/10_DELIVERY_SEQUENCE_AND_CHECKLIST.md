# 10 - Delivery Sequence and Checklist

**Status:** G1 finish-line validation active; C1 remains blocked until FL1-FL9 pass.
**Rule:** work one small packet to test-backed completion before opening the next dependency-heavy packet

> Use the [G1 Finish-Line Roadmap](g1_finish_line/README.md) as the authoritative FL1-FL9 remaining-work board. Historical unchecked N0-N6 entries below remain useful design context but are not, by themselves, proof of the current gate state.

## Milestone Board

| Milestone | Status | Entry | Exit evidence |
|---|---|---|---|
| N0 Scope/contracts | Complete (performance baseline tracked as an open, N6-gated item; see architecture lock exit-gate note) | This roadmap reviewed | Architecture checklist approved; budgets/fixture recorded |
| N1 Maritime graph | Validation (N1.1-N1.4 complete except the deferred cache/invalidation item; ready for N1 exit-gate review) | N0 approved | Graph/path/access/range tests and report |
| N2 Fleet logistics | Validation (N2.1-N2.5 complete except export evidence, which is blocked on Godot export templates not being installed in this environment; ready for N2 exit-gate review once that's unblocked) | N1 API stable | Construction/movement/repair/save loop passes |
| N3 Transport | Validation - normal, battle-paused, destructive, peace, extinction, cancellation, recovery, save/load and no-stranding paths pass. | N2 fleet/capacity stable | No-stranding Channel and destructive lifecycle gates pass |
| N4 Combat | Validation - positioning, targeting, hull/crew/morale, collapse, sinking, capture, pursuit, reinforcement, retreat, transport integration, peace/extinction, reports, save/load and stress checks pass. | N3 loss policy stable | Deterministic combat, lifecycle and presentation tests pass |
| N5 Strategic effects | Validation - blockade authority, economy, siege, repair/construction, war score, lifecycle, HUD/map feedback and coast stress pass; trade-protection output now shipped (see FL5.1). | N4 control/power stable | Strategic-effects tests and downstream contract pass |
| N6 AI/UX | Validation / P1 open - deterministic AI, threat, organisation, basing, transport handoff, feedback, generic fallback, stress, 100-seed acceptance and Windows export/startup pass; complete fleet/map UX, accessibility, rendered hardware, budgets and sign-off remain open. | N1-N5 player APIs stable | FL1-FL9 evidence passes |

## N0 - Architecture and Fixture Lock

### N0.1 Baseline inventory

- [x] Record current water/coast/sea-neighbour/strait counts and graph hash. *(counts recorded; no content hash exists yet in `province_graph.json` — flagged as an N1 gap, not a blocker for N0)*
- [x] Identify Channel/Iberian sea-zone and port IDs.
- [x] Record current save schema, scheduler order, economy ledger categories, war fields, character commander rules, and test runner coverage.
- [ ] Capture non-naval performance baseline before new systems alter it. *(no existing profiling harness found — open item, see evidence doc)*

Evidence: [N0_BASELINE_INVENTORY.md](evidence/N0_BASELINE_INVENTORY.md)

### N0.2 Decision lock

- [x] Approve existing water IDs as sea-zone authority.
- [x] Approve land province IDs as port IDs.
- [x] Approve individual data-only ship records.
- [x] Approve transport capacity and casualty/recovery abstraction.
- [x] Approve naval access versus basing rights.
- [x] Approve class roles, positioning-level combat, and no manual tactics.
- [x] Approve blockade economy/siege boundaries.
- [x] Approve next save schema/migration policy.
- [x] Approve downstream exploration/trade interfaces.

Approved 2026-07-17. See [00_SCOPE_AND_ARCHITECTURE_LOCK.md](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#architecture-lock-checklist) Exit Gate note. Performance baseline remains open but is N6-gated, not N1-gated, per that document's own text.

### N0.3 Test/content fixture

- [x] Record England/France fixture countries, armies, ports, fleets, zones, war, and expected capabilities. *(ports/zones recorded; armies/fleets/war state do not exist yet — will be filled in as N2/N3 fixtures once those registries exist)*
- [x] Record Portugal/Castile/Aragon secondary fixture.
- [x] Establish provenance/review template. *(recommended reuse of the ownership-manifest column shape; not yet applied to a real override file — that happens in N1.1)*
- [ ] Define numerical performance budgets from baseline captures. *(blocked on the N0.1 performance-baseline open item)*

Evidence: [N0_TEST_FIXTURES.md](evidence/N0_TEST_FIXTURES.md)

## N1 - Maritime Graph Work Board

### N1.1 Audit and data format

- [x] Inventory/classify navigable, inland, ocean, closed, and isolated water. *(84 closed_water / 335 coastal_sea / 147 open_ocean via connected-component analysis; `inland_sea` is override-only, none authored yet)*
- [x] Define versioned port/classification/override data. *(`assets/naval_definitions.json` + `tools/naval/sea_zone_overrides.csv` / `port_overrides.csv`, loaded by `scripts/simulation/naval_definitions.gd`)*
- [x] Add Channel/Iberian reviewed overrides. *(29 fixture ports, 10 fixture sea zones; placeholder capability values, reviewed provenance)*
- [x] Generate validation report. *(`docs/data/naval_graph_validation.md`, produced by `tools/naval/build_naval_graph_data.py --check`, wired into `tools/testing/run_all_tests.py`)*

Evidence: [N1_1_DATA_AUDIT.md](evidence/N1_1_DATA_AUDIT.md)

### N1.2 Runtime topology

- [x] Expose sorted sea zones/neighbours/ports/exits/anchors. *(`scripts/simulation/maritime_graph.gd`, `MaritimeGraph`)*
- [x] Implement stable movement costs and tie-breaking. *(classification-keyed integer leg costs; Dijkstra with packed-heap + lowest-predecessor-ID tie-break, mirroring `ProvincePathfinder`)*
- [x] Implement structured route result. *(`find_route()`; access/supply-range fields intentionally deferred to N1.3, not stubbed)*

Evidence: [N1_2_RUNTIME_TOPOLOGY.md](evidence/N1_2_RUNTIME_TOPOLOGY.md)

### N1.3 Access and range

- [x] Centralise sail/dock/base/repair permission queries. *(`scripts/simulation/naval_access_policy.gd`, `NavalAccessPolicy`: `can_sail`/`can_dock`/`can_base`, mirroring `ProvincePathfinder.can_enter`'s split for land)*
- [x] Add supply range and nearest legal port query. *(`NavalAccessPolicy.supply_range_query`, backed by `MaritimeGraph.nearest_matching` - one Dijkstra run, not one per candidate port)*
- [ ] Add cache revisions/invalidation. *(not yet needed - see evidence doc: neither class holds any ownership/diplomacy-derived cache today, so there is nothing to invalidate until N2 introduces one)*

Evidence: [N1_3_ACCESS_AND_RANGE.md](evidence/N1_3_ACCESS_AND_RANGE.md)

### N1.4 Tools/tests

- [x] Debug overlay and route/access explanation. *(`MaritimeGraph.explain_route`/`describe_node`, `NavalAccessPolicy.explain_dock` - console/test-trace form, per 01_N1's "final art is not required for N1")*
- [x] Graph malformed-data tests. *(`tests/naval_graph_malformed_data_smoke.py`, direct unit coverage of the override-rejection paths)*
- [x] Determinism, stress, export, and performance capture. *(`tests/maritime_graph_stress_smoke.gd`: representative long-haul fixture paths, runtime-level reciprocity, 812-pair stress batch; export coverage reasoned from the existing whole-project Windows export test, not independently re-run this session; performance capture remains a smoke guard, not an approved N0 budget)*

Evidence: [N1_4_TOOLING_AND_GATE_TESTS.md](evidence/N1_4_TOOLING_AND_GATE_TESTS.md)

- [x] Record N1 evidence and known issues. *(four evidence docs: [N1_1](evidence/N1_1_DATA_AUDIT.md), [N1_2](evidence/N1_2_RUNTIME_TOPOLOGY.md), [N1_3](evidence/N1_3_ACCESS_AND_RANGE.md), [N1_4](evidence/N1_4_TOOLING_AND_GATE_TESTS.md); known issues: province-name encoding defect (N1_1), deferred cache/invalidation (N1_3), deferred numeric performance budget (N0/N1_4))*

## N2 - Fleet Logistics Work Board

### N2.1 Definitions/state

- [x] Ship/mission/port definition loader and validator. *(`assets/ship_definitions.json` + `scripts/simulation/ship_definitions.gd`; port definitions already exist from N1.1 - mission definitions deferred until N2D's mission commands actually consume them, to avoid speculative schema)*
- [x] Fleet/ship/construction registries, IDs, indexes, checksum, migration. *(`CampaignWorldState.fleet_registry`/`ship_registry`/`naval_construction_registry`; `SAVE_SCHEMA_VERSION` 5→6; `take_counter()` reused for stable IDs, not yet called by any command)*
- [x] Representative four-family ship definitions. *(war_galley, light_caravel, heavy_galleon→heavy_ship_of_the_line, transport_cog - placeholder balance values, not final content)*

Evidence: [N2_1_DEFINITIONS_AND_STATE.md](evidence/N2_1_DEFINITIONS_AND_STATE.md)

### N2.2 Economy/construction

- [x] Sailor resource and recovery. *(`sailors`/`maximum_sailors` on country runtime; 200 per owned+enabled port, placeholder first-slice formula; recovers monthly like manpower via `SAILOR_RECOVERY_MONTHS`)*
- [x] Naval maintenance/ledger. *(`navy_maintenance` ledger line integrated directly into `EconomySystem`'s existing ledger - same function, same `total_expenses` sum as `army_maintenance`, not a parallel ledger)*
- [x] Ship construction/cancellation/completion and ownership edge cases. *(`ConstructShipCommand`, `CancelShipConstructionCommand`, `EconomySystem._complete_naval_construction`; ownership/control loss pauses rather than deletes, mirroring the existing building/recruitment pattern)*

Evidence: [N2_2_ECONOMY_AND_CONSTRUCTION.md](evidence/N2_2_ECONOMY_AND_CONSTRUCTION.md)

### N2.3 Organisation/movement

- [x] Create/merge/split/transfer/home-port commands. *(`CreateFleetCommand`, `SplitFleetCommand`, `TransferShipsCommand`, `MergeFleetsCommand`, `SetFleetHomePortCommand`; all share `FleetSystem.shared_organisable_port()`/`move_ships()` as their validation/mutation primitives, first slice scoped to fleets fully docked at the same port)*
- [x] Fleet aggregates and validation. *(`FleetSystem.recompute_aggregate()` called from every membership-changing path - the 4 organisation commands and `EconomySystem._complete_naval_construction()` - so the aggregate can never disagree with the underlying ships)*
- [x] Movement/cancel/block/access-change loop. *(`MoveFleetCommand`/`CancelFleetMovementCommand`/`FleetMovementSystem`, mirroring `ArmyMovementSystem`'s arrival-day model exactly, including revalidating each leg's access at entry time so a mid-route capture halts the fleet in place rather than teleporting or deleting it)*

Evidence: [N2_3_ORGANISATION_AND_MOVEMENT.md](evidence/N2_3_ORGANISATION_AND_MOVEMENT.md)

### N2.4 Logistics

- [x] Basing/supply status. *(`FleetLogisticsSystem.recompute_supply()`, run daily; a docked fleet at a basing-right port is trivially supplied, otherwise `NavalAccessPolicy.supply_range_query` answers from the fleet's exact current node - port or sea zone, mid-route or not)*
- [x] Attrition. *(`FleetLogisticsSystem.process_month()`; unsupplied fleets only, deterministic (no RNG - none approved yet), floored at `MIN_HULL_BP`/`MIN_CREW_BP` so a ship is never destroyed by attrition alone)*
- [x] Repair/reinforcement. *(`FleetLogisticsSystem.process_day()`; requires a legal repair port (`can_base`, stricter than "supplied") and a docked fleet; uses each ship definition's own `repair_rate_bp` - already-authored N2.1 data this was the first system to consume - and spends both treasury and sailors, gated and allocated in stable ship-ID order)*
- [x] Admiral assignment/lifecycle. *(`AssignAdmiralCommand`/`CharacterSystem.assign_admiral()`, mirroring `AssignCommanderCommand`/`assign_commander()` exactly; mutual exclusivity with army command enforced in both assignment directions; death clears the assignment on both sides; save validation rejects an unknown or dead admiral reference)*

Evidence: [N2_4_LOGISTICS.md](evidence/N2_4_LOGISTICS.md)

### N2.5 Minimal UX/gate

- [x] Fleet/port/construction debug-functional panels. *(`NavalHUD` - `scenes/ui/naval_hud.tscn` + `scripts/ui/naval_hud.gd` - fleet list/detail/move/cancel/admiral-assign, and port ship-construction/cancel; wired into `main.tscn` and driven through new `simulation_controller.gd` command wrappers, following the existing `EconomyHUD`/`WarHUD` pattern exactly)*
- [x] Outliner/alerts needed to test loop. *(`campaign_interface_shell.gd` gained a FLEETS outliner section (idle/damaged/unsupplied status per fleet, click-to-focus) and an "Unsupplied fleets" alert, mirroring the existing ARMIES section/alert pattern)*
- [x] Save evidence. *(`naval_hud_integration_smoke.gd` drives construction and fleet creation through the real UI, then a quick-save/quick-load round trip and checksum-stability check, mirroring every other phase's integration smoke)*
- [x] Accounting evidence. *(already covered by N2.2's `naval_economy_test.gd` - ledger reconciliation was verified there, not repeated here)*
- [x] Determinism evidence. *(N2.3's `naval_fleet_movement_test.gd` already proved movement resolves identically given an identical order; `simulation_frame_rate_determinism_test.gd` - the general cross-frame-rate harness every other system is checked against - was extended with a moving fleet, since its fixture predated naval and had never actually exercised `FleetMovementSystem`/`FleetLogisticsSystem`; 30 FPS and 120 FPS runs now produce an identical fleet outcome and an identical checksum)*
- [x] Stress evidence. *(`naval_fleet_stress_smoke.gd`: 290 fleets/870 ships across 10 synthetic countries and 29 real fixture ports, 116 cross-port move orders, 30 days of `FleetMovementSystem`/`FleetLogisticsSystem` ticking with no ship lost, duplicated, or disagreeing with its fleet's membership - a conservative smoke-test guard, not a certified N0 budget, mirroring N1.4's own framing)*
- [x] Performance evidence. *(same stress smoke: 30 days over 870 ships completed in ~3.7s, comfortably inside a 15s conservative guard - a smoke-level capture only; a certified N0 performance budget remains deferred to N6, same as N1.4)*
- [ ] Export evidence. *(blocked, not deferred by choice: attempted `--export-debug "Windows Desktop"` and it fails - no Godot export templates are installed for 4.7.1.stable in this environment. Naval files were added to `run_all_tests.py`'s required-export-log manifest so the check is ready the moment templates are installed; actually running it needs an export-template install, an environment change outside this slice's scope)*

Evidence: [N2_5_MINIMAL_UX_AND_GATE.md](evidence/N2_5_MINIMAL_UX_AND_GATE.md)

## N3 - Transport Work Board

### N3.1 Authority/reservation

- [x] Transport operation schema, IDs, reverse indexes, invariant audit. *(`transport_operation_registry`, `CampaignWorldState.make_transport_operation_record()`; army gains `transport_operation_id`, fleet gains `transport_operation_ids` array (multiple armies per fleet via distinct reservations, per 03_N3 "Capacity Model"); `_validate_transport_data()` checks every reverse reference agrees, mirroring `_validate_naval_data()`'s existing style; `SAVE_SCHEMA_VERSION` 6→7)*
- [x] Capacity calculation/reservation/release. *(`TransportSystem.usable_capacity()`/`reserved_capacity()`/`available_capacity()`; a ship at or below 50% hull contributes zero capacity - "damaged transport capacity follows an explicit threshold rule," a placeholder first-slice threshold, not an approved N0 budget)*
- [x] Create/cancel validation and command. *(`CreateTransportOperationCommand`, `CancelTransportOperationCommand`; embarkation is instantaneous in this slice - no embark-timing formula yet, that is N3.2)*

Evidence: [N3_1_AUTHORITY_AND_RESERVATION.md](evidence/N3_1_AUTHORITY_AND_RESERVATION.md)

### N3.2 State machine

- [x] Embark timing/lock/land-presence removal. *(`ARMY_STATUS_EMBARKING` - locked and still land-present - vs `ARMY_STATUS_EMBARKED` - aboard, absent; `TransportSystem.embark_days()` bounded-integer formula: base + regiment-count tier - commander bonus + damaged-fleet penalty, floored at 1 day)*
- [x] Carrier sailing. *(embark completion issues the fleet's own `MoveFleetCommand.apply()` toward the destination port; `FleetMovementSystem` remains the single authority for fleet position, `TransportSystem` only watches for arrival; a fleet carrying any transport operation now rejects independent `MoveFleetCommand` orders)*
- [ ] Battle pause. *(deferred - depends on interception/combat concepts N4 has not built yet; N3.3's job once they exist)*
- [x] Destination revalidation/disembark/land handoff. *(destination re-validated as a legal route at the embark→sailing transition, and as a still-usable port at the sailing→disembarking transition; a fixed one-day disembark delay, then the army lands with its full land presence restored)*

Evidence: [N3_2_STATE_MACHINE.md](evidence/N3_2_STATE_MACHINE.md)

### N3.3 Failure recovery

- [x] Partial/total transport loss. *(`TransportSystem._resolve_capacity_shortfalls()`, run daily for every fleet carrying an operation - a real, already-reachable trigger via `FleetLogisticsSystem` attrition, not a synthetic one; deterministic regiment/strength loss in stable operation-ID order, an army reduced to zero regiments is destroyed outright)*
- [x] Fleet retreat/destruction. *(a carrier fleet retreating elsewhere needed no new code - `_advance_sailing()`'s existing "settled somewhere other than the destination" recovery check already catches it once `FleetMovementSystem` finishes driving the retreat, since retreat is just another path through the same movement system this check already watches. A carrier fleet naval combat destroys outright (sunk, or no legal retreat) was a real gap: `process_day()` now checks fleet existence before dispatching an operation's state, closing a save-corruption bug where the operation kept naming a fleet that no longer existed. `NavalCombatSystem._begin_retreat()`'s "no legal retreat" branch also gained a fix of its own while proving this - it erased the fleet record but left its surviving ships orphaned in `ship_registry`)*
- [x] Access/ownership changes. *(a fleet FleetMovementSystem has halted mid-route - the one channel through which access loss reaches a sailing operation without a retreat mechanic - triggers bounded recovery: reroute to the nearest port the country can still legally dock at, or explicit destruction if none exists)*
- [x] Peace/extinction changes. *(`CountryDepthSystem._cleanup_extinct_country_references()` now sweeps every naval registry for the extinct tag: a dangling mid-transport operation is closed with `transport_operation_army_lost` - the carried army was already hard-erased by the pre-existing land cleanup this same function runs, so leaving the operation record behind was a real save-corruption bug (`_validate_transport_data` rejects a transport operation referencing an unknown army), not merely a hygiene gap)*
- [x] Explicit recover-or-destroy terminal paths, for the reachable trigger. *(`_attempt_recovery()`/`_destroy_stranded_operation()` - an army is never left attached to a fleet going nowhere; it recovers to a real port or is explicitly removed with an event, for every trigger this slice can actually produce)*

Evidence: [N3_3_FAILURE_RECOVERY.md](evidence/N3_3_FAILURE_RECOVERY.md), [N3_N4_N5_PEACE_EXTINCTION_CLEANUP.md](evidence/N3_N4_N5_PEACE_EXTINCTION_CLEANUP.md)

### N3.4 UX/gate

- [x] Capacity assignment, route, danger, operation state, alerts. *(`NavalHUD` transport section - eligible-army embark list, destination via province selection, active-operation state display, cancel; outliner FLEETS entries now show "carrying N", and a "Transport operations (N)" alert routes to the naval panel; every failure/reroute/loss event surfaces as a toast notification)*
- [x] Save each state/boundary and corruption tests. *(embarking was already covered by N3.1's test; `naval_transport_gate_test.gd` adds sailing, disembarking, and post-completion save/load, each reproducing an identical checksum)*
- [x] Channel repetitions with zero orphan/duplicate/stranded state. *(`naval_transport_gate_test.gd`: 5 repeated fresh-world Calais-to-Kent crossings, each checked for no lost/duplicated army, no dangling operation/fleet references, and no leftover reserved capacity; `simulation_frame_rate_determinism_test.gd` extended with a full embark-sail-disembark operation proving identical outcome and checksum at 30 FPS vs 120 FPS - seed-determinism is trivial here since embark timing and capacity math use no RNG)*

Evidence: [N3_4_UX_AND_GATE.md](evidence/N3_4_UX_AND_GATE.md)

## N4 - Combat Work Board

### N4.1 Engagement authority

- [x] Detection/interception, flat first-slice rule. *(co-located hostile fleets always detect each other - 04_N4's own "first abstraction is strategic," the same "simple explainable formula first" precedent as every N2/N3 first slice; scored detection is a later refinement)*
- [x] One-battle-per-fleet/zone rules. *(`_start_battles()` skips any fleet already carrying a `battle_id`; `_validate_naval_battle_data()` rejects a fleet claimed by two active battles on save load)*
- [x] Battle registry, reverse indexes. *(`naval_battle_registry`, `make_naval_battle_record()`, `fleet.battle_id` - already present in the N2.1 schema, unused until now)*
- [x] Reinforcement. *(`_join_reinforcements()`, mirroring `WarfareSystem` exactly: a friendly fleet arriving at an active battle's location joins the correct side before that day's round resolves, rather than starting an overlapping second battle)*

Evidence: [N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md](evidence/N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md), [N4_REINFORCEMENT_AND_VOLUNTARY_RETREAT.md](evidence/N4_REINFORCEMENT_AND_VOLUNTARY_RETREAT.md)

### N4.2 Resolution

- [x] Active ship selection (whole-fleet, not per-ship targeting). *(a deliberate first-slice simplification - see evidence doc)*
- [x] Integer damage. *(mirrors `WarfareSystem`'s land-combat formula exactly in shape: power, a zone modifier, a named-stream d6 roll, divided by a fixed constant; damaged ships contribute proportionally less to combat power)*
- [ ] Positioning breakdown, morale, targeting by class/priority. *(deferred - see evidence doc)*
- [x] Sinking. *(hull-point damage distributed across ships in stable ID order, clamped, ships at zero hull removed from the ship and fleet registries)*
- [ ] Disable/capture. *(deferred - ships only survive or sink in this slice)*

### N4.3 Retreat/integration

- [x] Forced retreat and destination. *(the losing side's survivors retreat to the nearest port their country can legally dock at, reusing `NavalAccessPolicy.can_dock`/`MaritimeGraph.nearest_matching`, the same pattern N3.3's `TransportSystem._attempt_recovery` already established; a fleet with no legal retreat is destroyed outright)*
- [x] Voluntary retreat (player/AI-requested mid-battle). *(`RequestFleetRetreatCommand`/`NavalCombatSystem.withdraw_fleet()`; rejected before a minimum round count unless the roadmap's own "unless a side is destroyed/collapsed" exception applies implicitly - forced retreat already handles that case separately; withdrawing the last fleet on a side ends the battle in the opponent's favour, exactly as a combat defeat would)*
- [x] Transport casualty handoff. *(no new integration code needed - `TransportSystem._resolve_capacity_shortfalls()`, built in N3.3, already re-evaluates any fleet's capacity daily regardless of cause, so combat-sunk transport ships are already covered by the existing daily sweep)*
- [x] War score. *(naval battles feed the same `war["battle_score_attacker"]` field land combat already uses - one unified war score, not a parallel naval one)*
- [ ] Peace, commander, and country lifecycle interaction during battle. *(country-extinction interaction is now handled - `CountryDepthSystem._cleanup_extinct_country_references()` removes the extinct country's fleets from any active battle's side, ends the battle outright if that empties one side, and clears the admiral's `admiral_fleet_id` before erasing the fleet; commander/admiral death mid-battle was already handled by the pre-existing `CharacterSystem.kill_character()`. Peace-treaty disengagement mid-battle remains open - a live war simply reaching "ended" status does not currently stop its in-progress naval battles)*

### N4.4 UX/gate

- [x] Battle marker/panel/report/retreat control. *(`ConflictMarkerLayer` gained a third marker family - `naval_battle`, rendered at the sea-zone anchor with the atlas's existing "navy" icon, reusing the exact same anchor/clustering/fade/click machinery land battles and sieges already share, kept in structurally separate multimeshes/registries/debug counters so land marker tests' exact-value assertions stay untouched. `NavalHUD` gained a battle panel - active-battle list scoped to the player's own fleets, round/hull-lost/ships-sunk detail for the selected battle, and a "final report" reading the most recently completed battle either side of a war the player belongs to fought (completed battle records are a permanent history snapshot, so this needed no new persisted state). Retreat control reuses the existing `RequestFleetRetreatCommand` directly - the button is only enabled once `validate()` actually accepts, so its tooltip doubles as the roadmap's "earliest legal date" explanation. Positioning, morale, commanders, and captures are not surfaced, since none of those mechanics exist in the simulation yet to have anything to show)*
- [x] Determinism evidence. *(identical fixture, identical campaign seed, resolves to an identical outcome and survivor hull)*
- [x] Mid-battle save evidence. *(a save/load round trip mid-fight reproduces an identical checksum; corruption rejection verified for a fleet referencing an unknown battle)*
- [x] Balance/stress/performance evidence. *(`tests/naval_battle_blockade_stress_smoke.gd`: 29 real N0.3 fixture ports across several coastlines, each with a co-located hostile pair (naval battle) and a separate hostile blockading fleet at that port's own real sea exit, ticked through 20 days of concurrent combat/blockade processing; a full save/load round trip afterward proves every structural validator this pillar's own work touches - `_validate_naval_data`, `_validate_naval_battle_data`, the war-participants check, `_validate_transport_data` - still accepts the result at this scale. A smoke-level capture only, same "not a certified N0 budget" framing as every other stress smoke in this suite)*

Evidence: [N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md](evidence/N4_ENGAGEMENT_DAMAGE_AND_RETREAT.md), [N4_4_N5_3_UX_AND_GATE.md](evidence/N4_4_N5_3_UX_AND_GATE.md)

## N5 - Strategic Effects Work Board

### N5.1 Blockade authority

- [x] Eligibility, effective power. *(`BlockadeSystem.is_fleet_eligible()`/`effective_power()`: at-sea, blockade-mission, supplied, above a damage threshold; damaged fleets contribute proportionally less, reusing `NavalCombatSystem`'s own damage-scaling shape; new `SetFleetMissionCommand` lets a fleet actually be assigned the blockade mission the roadmap gates eligibility on)*
- [x] Target resistance (coastal development/port importance/harbour level). *(`BlockadeSystem.required_power()` - made public during the N5.3 UX slice so the naval panel could show it directly, previously `_required_power()`: a base floor plus the province's raw `base_tax + base_production` plus `NavalDefinitions`' existing per-port `harbour_level`, reusing already-authored data rather than a new field; `province_blockade_bp()` now expresses attacker power as a bp fraction of this required power, clamped to [0, 10000], instead of returning raw power directly. Defending fleet presence is not attempted - that is the still-open Contested Zones item below, a distinct mechanic from a province's fixed defensive rating)*
- [x] Contested zones. *(`BlockadeSystem._zone_is_contested()`: an opposing at-sea fleet sharing the blockading fleet's own zone eliminates its eligibility, closing the one-tick lag between an enemy fleet arriving and `NavalCombatSystem` starting a battle the following day - together with the pre-existing "in active battle = ineligible" rule, this is 05_N5's "opposing eligible fleets reduce or eliminate blockade contribution," using the elimination reading rather than a proportional/diminishing-return contest)*
- [ ] Reverse indexes. *(deliberately not built - a pure scan-and-filter query layer instead, matching `armies_in_province()`'s existing pattern; see evidence doc)*
- [x] Blockade started/ended events. *(`CampaignWorldState.blockaded_provinces` - the one small piece of persisted state a pure query layer needed to detect a transition at all; `BlockadeSystem.process_day()`, a new daily system, diffs today's resistance-adjusted blockade set against yesterday's and emits `blockade_started`/`blockade_ended`. `SAVE_SCHEMA_VERSION` 8->9)*
- [x] Port fully blockaded/unblocked events. *(`blockaded_provinces` stores each blockaded province's actual bp value, not just a boolean, so `process_day()` can also detect the bp==10000 boundary for registered ports specifically and emit `port_fully_blockaded`/`port_unblocked` - reusing the same infrastructure the started/ended signal just built, per that evidence doc's own "natural near-term follow-on" note)*
- [x] Province blockade level changed across meaningful thresholds. *(`BlockadeSystem.blockade_tier()`: five placeholder quartile-ish buckets (light/moderate/heavy/severe/full) bucketing a raw bp value; `process_day()` compares today's and yesterday's tier for the same stored bp values `blockaded_provinces` already holds - no new persisted field, no schema bump - and emits `blockade_level_changed` only on a tier boundary crossing, "avoiding daily notification spam" per 05_N5's own requirement. Closes out every remaining item in 05_N5's "Events and Queries" minimum-signals list except the trade-protection output, which is its own separate work packet)*

Evidence: [N5_1_BLOCKADE_ELIGIBILITY_AND_POWER.md](evidence/N5_1_BLOCKADE_ELIGIBILITY_AND_POWER.md), [N5_1_TARGET_RESISTANCE.md](evidence/N5_1_TARGET_RESISTANCE.md), [N5_1_CONTESTED_ZONES.md](evidence/N5_1_CONTESTED_ZONES.md), [N5_1_BLOCKADE_STARTED_ENDED_EVENTS.md](evidence/N5_1_BLOCKADE_STARTED_ENDED_EVENTS.md), [N5_1_PORT_FULLY_BLOCKADED_EVENTS.md](evidence/N5_1_PORT_FULLY_BLOCKADED_EVENTS.md), [N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md](evidence/N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md)

### N5.2 Wider systems

- [x] Coastal siege contribution. *(`BlockadeSystem.blockade_bp_by_side()`/`siege_assist_bp()`: a side-scoped, resistance-adjusted blockade query gated on the target being a registered port and the blockade exceeding a configured threshold; `WarfareSystem._advance_sieges_and_occupations()` applies a flat daily-progress bonus when the besieging side's own blockade clears that gate. Naval only publishes the query - land warfare remains siege authority, exactly as 05_N5 requires. "Removal/reduction of a coastal resupply penalty" and "garrison recovery reduction" are not attempted - neither underlying mechanic exists anywhere in land warfare today, so there is nothing for a blockade to modify)*
- [x] Economy ledger penalty. *(`EconomySystem.recalculate_all()`/`recalculate_country()` gain a `blockade_loss` ledger line - `province_blockade_bp()` applied to each blockaded province's raw tax+production, subtracted from `total_income`; extends the existing ledger functions rather than paralleling them, the same N2.2 precedent `navy_maintenance` established)*
- [x] Repair/construction/port effects. *(`FleetLogisticsSystem._process_repair()`: a docked fleet at a port blockaded above threshold repairs at a reduced daily rate; `EconomySystem._complete_naval_construction()`: a blockaded port's construction pauses one day at a time, reusing the exact mechanism already used for ownership loss. "Optional sailor recovery reduction" is not attempted - sailor recovery is a country-wide monthly aggregate, not attributable to a single port without a larger redesign)*
- [x] War blockade score. *(`BlockadeSystem.update_war_blockade_score()`, folded into `WarfareSystem._update_war_scores()`'s existing daily pass alongside battle/occupation/ticking score; a bounded ±25 accumulator, not a fresh-recompute like occupation score - grows one point/day only while one side holds an uncontested blockade advantage, decays one point/day toward zero once released, per 05_N5's "cannot grow without an active eligible blockade" / "decay policy" requirements)*
- [x] Coastal siege support changed event. *(each siege record gains a `blockade_assisted` flag; `WarfareSystem._advance_sieges_and_occupations()` compares today's computed assist state against it and emits `coastal_siege_support_changed(war_id, province_id, assisted)` on a transition, mirroring the `blockaded_provinces`-diff pattern the blockade started/ended events already established - no schema bump needed since this is an additive field on the already-existing, already-backward-compatible `war["sieges"]` nested dict)*
- [x] Peace lifecycle. *(a war's `blockade_score_attacker` already stops updating once the war record leaves `status == "active"` - `WarfareSystem._update_war_scores()` skips non-active wars entirely, same as the other three score components; extinction specifically is now also clean, since `CountryDepthSystem._cleanup_extinct_country_references()` erases the extinct country's fleets outright, so a dead country can no longer hold `BlockadeSystem.is_fleet_eligible()` open. A live peace treaty signed mid-war needs no further blockade-specific work beyond that existing active-status gate)*
- [x] Stable trade-protection hook without fabricated income. *(built under the G1 finish-line board, not this legacy N5.2 slice - `NavalTradeProtection.assess()` mirrors `BlockadeSystem`'s own eligibility/effective-power/contested-zone shape, gated on a `trade_protection` mission; a pure, currently-unconsumed query that writes nothing and fabricates no income/route/market concept. See [FL5_1_TRADE_PROTECTION.md](g1_finish_line/evidence/FL5_1_TRADE_PROTECTION.md))*

Evidence: [N5_2_ECONOMY_LEDGER_AND_WAR_SCORE.md](evidence/N5_2_ECONOMY_LEDGER_AND_WAR_SCORE.md), [N5_2_COASTAL_SIEGE_ASSIST.md](evidence/N5_2_COASTAL_SIEGE_ASSIST.md), [N5_2_REPAIR_AND_CONSTRUCTION_EFFECTS.md](evidence/N5_2_REPAIR_AND_CONSTRUCTION_EFFECTS.md), [N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md](evidence/N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md), [N3_N4_N5_PEACE_EXTINCTION_CLEANUP.md](evidence/N3_N4_N5_PEACE_EXTINCTION_CLEANUP.md)

### N5.3 UX/gate

- [x] Port/zone/coast feedback, war/economy explanation, alerts. *(`NavalHUD` gained a blockade label for the selected province - tier name, bp percentage, and `BlockadeSystem.required_power()` breakdown, for any coastal province, not only the player's own - plus a fleet mission control (`SetFleetMissionCommand`, idle/blockade) showing `effective_power()` once a fleet is on blockade duty, and a "show blockade map" coastal overlay (yellow-to-red by bp) reusing `MapHUD.set_strategy_map_overlay()` exactly as `WarHUD`'s war/relations/access maps already do. `WarHUD`'s war summary gained a blockade-score readout alongside the existing total war score. `EconomyHUD`'s ledger gained `navy_maintenance` and `blockade_loss` line items - both were already folded into the totals since N2.2/N5.2, just never broken out; the roadmap's own "Economy ledger blockade-loss line" ask exposed that the ledger display itself had never caught up. `CampaignInterfaceShell` gained a BLOCKADES outliner section (player-owned blockaded coasts, click-to-focus) and two alerts - "Naval battles (N)" and "Blockaded ports (N)" - mirroring the existing FLEETS/transport alert pattern exactly. Toast notifications fire for battle start/end, retreat, ship loss, and every blockade threshold event (`blockade_started`/`ended`, `port_fully_blockaded`/`unblocked`) scoped to the player's own provinces, so a foreign blockade elsewhere on the map doesn't spam the player. War/economy *explanation* is the bp/tier/required-power breakdown itself, not a separate prose panel - positioning/morale-level detail has nothing underlying to explain yet)*
- [x] Save/replay/accounting/global coast/performance evidence. *(save/replay/accounting: covered by the same `naval_hud_integration_smoke.gd` save/load round trip N2.5/N3.4 already established, now also exercising an active naval battle and a blockade-mission fleet through the panel end-to-end - construct, embark, fight, retreat, read the final report, all through real UI-to-command wiring, not mocked. Global coast/performance: `tests/naval_battle_blockade_stress_smoke.gd` (shared with N4.4 above) also times `BlockadeSystem.all_blockaded_provinces()` - the exact query this UX slice's map overlay/outliner/economy hooks all call - across 29 real ports spanning several coastlines, not one Channel hotspot, and requires it find genuine contributions at that scale, not just stay fast on an empty world)*

Evidence: [N4_4_N5_3_UX_AND_GATE.md](evidence/N4_4_N5_3_UX_AND_GATE.md)

## N6 - AI and UX Work Board

### N6.1 Missions/AI

- [x] Mission state/command. *(`SetFleetMissionCommand.VALID_MISSIONS` extended with `return_to_port` and `repair` - both self-completing, driven by the new `FleetMissionSystem.process_day()` state machine (return_to_port routes home via the same bounded-recovery pattern N3.3/N4.3 already established, then clears; repair watches for full hull and clears). `blockade`/`idle` already existed. `patrol`/`intercept`/`protect_transport`/`protect_coast`/`transport` need the threat map and transport-planning layers this packet doesn't build; `trade_protection` has no underlying system to protect anything yet - none of those five are modeled, and 06_N6's own mission list is left as the record of what remains)*
- [x] Strategic posture and force construction. *(`NavalAISystem._review_posture()`/`_plan_construction()`: peace/wartime posture (not the fuller threatened/invasion/recovery/expansion spectrum) and a flat port-scaled desired ship count (not a heavy/light/galley/transport mix - every ship built is a war_galley, the same "not final balance" caveat N2.1's own ship data already carries), gated on treasury reserve exactly like `StrategicAISystem._plan_economy()`'s land equivalent)*
- [x] Fleet organisation and operational allocation. *(`NavalAISystem._plan_organisation()` assigns a free admiral to an unled multi-ship fleet and now also consolidates separate idle fleets sharing a port into one task fleet (`_consider_fleet_merge()`, reusing `MergeFleetsCommand`, excluding any fleet carrying a transport operation since merging would strand that operation's own fleet reference); `_consider_blockade_or_evade()` assigns blockade duty to an idle fleet already safely at sea near a war target. Splitting a fleet for a smaller mission, and mission assignment driven by ports/war goals rather than just the fleet's current zone, are not attempted)*
- [x] Threat map and tactical risk/retreat/repair/blockade decisions. *(`NavalAISystem._zone_threat()`: a coarse, on-demand (not persisted/cached) query - direct-zone hostile fleet power at full weight, adjacent-zone at half weight, summed from live `fleet_registry` state the same way `BlockadeSystem`'s own query layer already avoids a parallel index. Backs two tactical decisions beyond the pre-existing in-battle retreat/repair/return rules: evade a zone this country's own fleet cannot safely cover (`return_to_port`), and take up blockade duty in a zone that's safe and has a reachable war target (`_zone_has_blockade_target()`, the same land_neighbors() reciprocal relationship `BlockadeSystem.blockaded_provinces_for_fleet()` already uses, minus its eligibility gate). "Recent battles/sightings" and "friendly support arrival time" are not modelled - both need persisted history or a broader search this slice does not build; reinforcement is not attempted)*
- [x] Atomic transport-objective planning and land-AI handoff. *(`NavalAISystem._plan_transport()` reads land AI's own existing `target_province_id` - no new "objective" concept invented, "confirm strategic value" is inherited for free - and, when land movement genuinely cannot reach it, ferries an idle army there via a real `CreateTransportOperationCommand`. Discovered while building this, not assumed: `NavalAccessPolicy.can_dock()` never grants docking rights merely from being at war, so a hostile-held port is never itself a legal landing site - `_find_legal_landing()` lands at the country's own nearest port with a genuine land route onward to the objective instead (a beachhead) when the objective itself isn't legally dockable. "Land-AI handoff" needed no new code at all: a disembarked army is just `ARMY_STATUS_IDLE` again, and `StrategicAISystem._issue_army_orders()` already scans every idle army generically. Escort assignment and "acceptable threat" routing beyond legality are not attempted)*
- [x] Explainable traces and staggered schedules. *(`NavalAISystem` built to `StrategicAISystem`'s own established shape exactly - deterministic utility scoring, per-country schedules staggered off the same `AIDefinitions` "slot" land AI already uses, persistent decision state in `country_runtime(tag)["naval_ai"]`, bounded decision history/counts/rejected-candidates, and a `debug_snapshot()` explainability view. Proven against the real, already-reviewed Iberian AI fixture `phase_6_ai_test.gd` itself uses, not a bespoke one - Castile/Aragon/Portugal each own a real reviewed port and build ships; Granada owns only harbour-too-small ports and takes real, explained rejections; landlocked Navarre takes zero naval decisions)*

Evidence: [N6_1_MISSION_STATE_AND_FIRST_AI_LAYERS.md](evidence/N6_1_MISSION_STATE_AND_FIRST_AI_LAYERS.md)

### N6.2 Final functional UX

- [x] Naval campaign tab and sailor resource. *(`CampaignInterfaceShell` gained a "Naval" entry in the country tab strip alongside Government/Economy/Military/Diplomacy/Religion/Court, opening the same naval panel N2.5 already built, plus a "Sailors" entry on the top-bar resource row - `country_runtime(tag)["sailors"]`/`["maximum_sailors"]` had existed since N2.2 but were never actually surfaced there)*
- [x] Fleet marker layer/clustering/selection/routes. *(built in the N4.4/N5.3 UX/gate slice - see [N4_4_N5_3_UX_AND_GATE.md](evidence/N4_4_N5_3_UX_AND_GATE.md); naval battle markers share land battles' clustering/anchor/fade pipeline. A live route-preview overlay for a fleet's planned path is not attempted)*
- [x] Fleet/port/construction/transport/battle panels. *(built across N2.5, N3.4, and the N4.4/N5.3 slice; the battle panel covers round/hull/sunk/retreat/final-report - see 04_N4_NAVAL_COMBAT.md's own note that positioning/morale/commander/capture detail has nothing underlying to show yet)*
- [x] Outliner, alerts, notifications, map overlays. *(FLEETS/BLOCKADES outliner sections, naval-battle/blockade/transport alerts, event toasts, and the blockade coastal map overlay all built in N2.5/N3.4/N4.4/N5.3 - see their evidence docs)*
- [ ] Accessibility, focus, supported resolution/UI-scale matrix. *(not specifically tested against 06_N6's own resolution/accessibility requirements - open)*

### N6.3 Global and export gate

- [x] Generic maritime AI fallback. *(`NavalAISystem.process_day()` iterates the same `AIDefinitions.country_tags()` roster land AI uses - there is no naval-specific curated country list anywhere in the pillar. The only gate is `_is_maritime_capable()` (the country owns at least one structurally real port), so any AI-enabled country that owns a port automatically receives full posture/construction/organisation/tactical/transport AI the day it qualifies, exactly as 06_N6's rollout step 4 "Generic maritime fallback for all countries with eligible ports" describes. Worldwide tuning/balance (rollout step 5) is explicitly out of scope for this item)*
- [x] Full-world fleet/ship/transport/battle/blockade stress. *(`tests/naval_battle_blockade_stress_smoke.gd` extended: alongside its existing 18-29 real N0.3 fixture ports' worth of concurrent naval battles and blockades, one real `CreateTransportOperationCommand` transport operation now runs per multi-port country too, so all five mechanisms - fleet, ship, transport, battle, blockade - tick concurrently across the same fixture in one run. The transport's origin/destination ports are reserved out of the battle-fleet setup: a hostile fleet co-located with the transport fleet would correctly sweep it into that battle the moment one forms (the 100-seed test below hit the identical interaction), which would stall embarking and defeat the point of proving transport progress rather than reveal a bug. Countries remain 10 synthetic tags rather than the real political map, the same scope this item already carried before the transport extension)*
- [x] 100-seed Channel acceptance report. *(`tests/naval_channel_100_seed_acceptance_test.gd`: 100 seeds (`BASE_SEED=14441111` + seed index), each run through three separate England/Burgundy Channel scenarios - an asymmetric 4-vs-3 `war_galley` battle at the Straits of Dover, a Kent-to-Calais transport operation, and a blockade-mission fleet - with structural-invariant and save/load-round-trip checks after every scenario. Verified result: `seeds=100 battles_resolved=100 distinct_hull_outcomes=10 transports_completed=100 blockades_formed=100`; 10 distinct hull-loss outcomes across 100 seeds is the proof of genuine dice variance, not a fixed script. The three scenarios run in separate `CampaignWorldState` instances per seed rather than one combined world, for the same co-location/reinforcement reason noted above - see the test's own doc comment)*
- [x] Save migration and corruption suite. *(corruption: every N-pillar test in this suite already asserts specific corruption is rejected at its own boundary - `_validate_naval_data`, `_validate_naval_battle_data`, `_validate_transport_data`, the war-participants check, the blockaded-provinces reference check - and every stress/soak test proves a save/load round trip stays clean at scale; nothing new was needed there. Migration: `tests/naval_save_schema_migration_test.gd` (new) closes the one genuine gap - every earlier per-phase test only proved `migrate_save_data()` upgrading from its own one adjacent schema, and nothing exercised this pillar's own two schema bumps (7: `naval_battle_registry`, N4A; 8: `blockaded_provinces`, N5.1) specifically, or the full schema-1-through-9 chain in a single call. Both are now proven against a real populated fixture - genuine fleets/ships/an active reciprocal naval battle/a blockaded province - not an empty placeholder, plus a from-scratch schema-1 ancient save migrating through all eight steps and loading cleanly onto a fresh world)*
- [ ] Performance budgets pass. *(blocked on N0.1's own deferred "capture non-naval performance baseline" item - there is no approved numerical budget to pass against yet, only this suite's own conservative smoke-test guards; see [N0_BASELINE_INVENTORY.md](evidence/N0_BASELINE_INVENTORY.md))*
- [ ] Supported hardware/rendered checks pass. *(not attempted - open)*
- [ ] Export manifest/startup/action flow passes. *(blocked - Godot export templates are still not installed in this environment, the same blocker N2.5's export evidence item already carries)*
- [ ] Milestone build/version, known issues, save policy, and evidence report recorded.

Evidence: [N6_1_MISSION_STATE_AND_FIRST_AI_LAYERS.md](evidence/N6_1_MISSION_STATE_AND_FIRST_AI_LAYERS.md), [N6_3_GLOBAL_FALLBACK_AND_ACCEPTANCE.md](evidence/N6_3_GLOBAL_FALLBACK_AND_ACCEPTANCE.md)

## Change Control

Any change after N0 that alters stable IDs, port identity, ship/fleet ownership, transport authority, scheduler order, save references, or trade/colonisation interfaces must:

1. Name the affected contract and slices.
2. Update this roadmap before implementation.
3. Add or change migration/validation tests.
4. Re-run downstream completed slice gates.
5. Record the decision and reason in the milestone evidence.

## Immediate Next Work

Follow the [G1 Finish-Line Roadmap](g1_finish_line/README.md). Begin with FL1 map presentation and FL2 fleet-management gaps, then complete rendered/accessibility acceptance and the remaining project gate. N1-N6 authority is already implemented far beyond the original first-coding-batch note; do not restart N1 work.
