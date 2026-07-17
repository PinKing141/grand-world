# 10 - Delivery Sequence and Checklist

**Status:** Planning  
**Rule:** work one small packet to test-backed completion before opening the next dependency-heavy packet

## Milestone Board

| Milestone | Status | Entry | Exit evidence |
|---|---|---|---|
| N0 Scope/contracts | Complete (performance baseline tracked as an open, N6-gated item; see architecture lock exit-gate note) | This roadmap reviewed | Architecture checklist approved; budgets/fixture recorded |
| N1 Maritime graph | Validation (N1.1-N1.4 complete except the deferred cache/invalidation item; ready for N1 exit-gate review) | N0 approved | Graph/path/access/range tests and report |
| N2 Fleet logistics | Validation (N2.1-N2.5 complete except export evidence, which is blocked on Godot export templates not being installed in this environment; ready for N2 exit-gate review once that's unblocked) | N1 API stable | Construction/movement/repair/save loop passes |
| N3 Transport | Validation (N3.1-N3.4 complete except battle pause/fleet retreat/peace-extinction paths, all blocked on N4 combat or a pre-existing extinction-cleanup gap; ready for N3 exit-gate review once those close) | N2 fleet/capacity stable | No-stranding Channel transport tests pass |
| N4 Combat | In production (engagement/damage/sinking/forced-and-voluntary-retreat/reinforcement/war-score complete; positioning breakdown, morale, capture, peace/lifecycle interaction, and UX/gate all open) | N3 loss policy stable | Deterministic battle/interception/save tests pass |
| N5 Strategic effects | In production (blockade eligibility/power query, target resistance, contested zones, all N5 Events-and-Queries signals (blockade started/ended, port fully blockaded/unblocked, blockade level changed, coastal siege support changed), economy ledger penalty, war blockade score, coastal siege assist, and repair/construction port effects complete; peace lifecycle and trade-hook integration open) | N4 control/power stable | Blockade siege/economy/war-score loop passes |
| N6 AI/UX | Not started | N1-N5 player APIs stable | AI/UI/global/100-seed G1 evidence passes |

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
- [ ] Fleet retreat/destruction. *(blocked - there is no fleet "retreat" mechanic at all yet, combat-driven or otherwise; N4's job)*
- [x] Access/ownership changes. *(a fleet FleetMovementSystem has halted mid-route - the one channel through which access loss reaches a sailing operation without a retreat mechanic - triggers bounded recovery: reroute to the nearest port the country can still legally dock at, or explicit destruction if none exists)*
- [ ] Peace/extinction changes. *(deferred - matches a pre-existing, undocumented-until-now gap: `CountryDepthSystem._cleanup_extinct_country_references()` does not clean up armies/fleets/commanders on country extinction today either, so transport operations are consistent with existing (non-)behavior, not newly broken)*
- [x] Explicit recover-or-destroy terminal paths, for the reachable trigger. *(`_attempt_recovery()`/`_destroy_stranded_operation()` - an army is never left attached to a fleet going nowhere; it recovers to a real port or is explicitly removed with an event, for every trigger this slice can actually produce)*

Evidence: [N3_3_FAILURE_RECOVERY.md](evidence/N3_3_FAILURE_RECOVERY.md)

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
- [ ] Peace, commander, and country lifecycle interaction during battle. *(deferred - matches N3.3's already-documented pre-existing extinction-cleanup gap; peace disengagement is not implemented)*

### N4.4 UX/gate

- [ ] Battle marker/panel/report/retreat control. *(deferred to a follow-up round, mirroring how N2.5/N3.4 were their pillars' dedicated UX slices)*
- [x] Determinism evidence. *(identical fixture, identical campaign seed, resolves to an identical outcome and survivor hull)*
- [x] Mid-battle save evidence. *(a save/load round trip mid-fight reproduces an identical checksum; corruption rejection verified for a fleet referencing an unknown battle)*
- [ ] Balance/stress/performance evidence. *(deferred - no naval-battle-scale stress test yet, distinct from N2.5's fleet-logistics stress smoke)*

## N5 - Strategic Effects Work Board

### N5.1 Blockade authority

- [x] Eligibility, effective power. *(`BlockadeSystem.is_fleet_eligible()`/`effective_power()`: at-sea, blockade-mission, supplied, above a damage threshold; damaged fleets contribute proportionally less, reusing `NavalCombatSystem`'s own damage-scaling shape; new `SetFleetMissionCommand` lets a fleet actually be assigned the blockade mission the roadmap gates eligibility on)*
- [x] Target resistance (coastal development/port importance/harbour level). *(`BlockadeSystem._required_power()`: a base floor plus the province's raw `base_tax + base_production` plus `NavalDefinitions`' existing per-port `harbour_level`, reusing already-authored data rather than a new field; `province_blockade_bp()` now expresses attacker power as a bp fraction of this required power, clamped to [0, 10000], instead of returning raw power directly. Defending fleet presence is not attempted - that is the still-open Contested Zones item below, a distinct mechanic from a province's fixed defensive rating)*
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
- [ ] Peace lifecycle. *(deferred - matches the same pre-existing extinction/peace-cleanup gap already documented for N3.3/N4.3; a war's `blockade_score_attacker` simply stops updating once the war record leaves `status == "active"`, same as the other three score components)*
- [ ] Stable trade-protection hook without fabricated income.

Evidence: [N5_2_ECONOMY_LEDGER_AND_WAR_SCORE.md](evidence/N5_2_ECONOMY_LEDGER_AND_WAR_SCORE.md), [N5_2_COASTAL_SIEGE_ASSIST.md](evidence/N5_2_COASTAL_SIEGE_ASSIST.md), [N5_2_REPAIR_AND_CONSTRUCTION_EFFECTS.md](evidence/N5_2_REPAIR_AND_CONSTRUCTION_EFFECTS.md), [N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md](evidence/N5_2_COASTAL_SIEGE_SUPPORT_CHANGED_EVENT.md)

### N5.3 UX/gate

- [ ] Port/zone/coast feedback, war/economy explanation, alerts.
- [ ] Save/replay/accounting/global coast/performance evidence.

## N6 - AI and UX Work Board

### N6.1 Missions/AI

- [ ] Mission state/command.
- [ ] Strategic posture and force construction.
- [ ] Fleet organisation and operational allocation.
- [ ] Threat map and tactical risk/retreat/repair/blockade decisions.
- [ ] Atomic transport-objective planning and land-AI handoff.
- [ ] Explainable traces and staggered schedules.

### N6.2 Final functional UX

- [ ] Naval campaign tab and sailor resource.
- [ ] Fleet marker layer/clustering/selection/routes.
- [ ] Fleet/port/construction/transport/battle panels.
- [ ] Outliner, alerts, notifications, map overlays.
- [ ] Accessibility, focus, supported resolution/UI-scale matrix.

### N6.3 Global and export gate

- [ ] Generic maritime AI fallback.
- [ ] Full-world fleet/ship/transport/battle/blockade stress.
- [ ] 100-seed Channel acceptance report.
- [ ] Save migration and corruption suite.
- [ ] Performance budgets pass.
- [ ] Supported hardware/rendered checks pass.
- [ ] Export manifest/startup/action flow passes.
- [ ] Milestone build/version, known issues, save policy, and evidence report recorded.

## Change Control

Any change after N0 that alters stable IDs, port identity, ship/fleet ownership, transport authority, scheduler order, save references, or trade/colonisation interfaces must:

1. Name the affected contract and slices.
2. Update this roadmap before implementation.
3. Add or change migration/validation tests.
4. Re-run downstream completed slice gates.
5. Record the decision and reason in the milestone evidence.

## Immediate Next Work After Approval

The first coding batch should be **N1.1 only**: audit the existing maritime records, define the versioned port/sea classification format, identify the Channel fixture IDs, and generate a validator report. Runtime fleets should not be added until that data authority passes review.
