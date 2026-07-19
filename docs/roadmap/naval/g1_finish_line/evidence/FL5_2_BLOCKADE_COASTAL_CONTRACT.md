# FL5.2 - Blockade and Coastal Query Contract

**Status:** Complete. Targeted tests pass (see Verification).
**Satisfies:** [05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md](../05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md)'s FL5.2 scope bullets - document blockade strength/tier/attacker/contested/affected-port-or-coast queries; confirm consumers cannot mutate blockade state; define event ordering for start, level change, full blockade, release, peace and annexation; confirm economy, repair, construction, siege and war-score consumers reconcile from the same authoritative result.

`BlockadeSystem` (`scripts/simulation/blockade_system.gd`) is already on the roadmap README's "what is already trusted" list. This packet is primarily an audit and a documentation lock, not new behaviour - the two gaps the audit did find (below) were closed with a small, focused test rather than left as an unverified claim, matching this roadmap's own rule 1 ("reproduce or record the missing behavior before implementation").

## The query contract

Every public `BlockadeSystem` function is a pure, static, `world`-in/value-out query - nothing here is a persistent registry a consumer subscribes to, nothing here is written by any command, and no function takes a mutable reference to anything it doesn't return:

| Query | Returns |
|---|---|
| `is_fleet_eligible(world, fleet_id)` | Whether a fleet may currently contribute (at sea, `blockade` mission, supplied, uncontested). |
| `zone_is_contested(world, fleet_id)` | Whether an at-war opposing at-sea fleet shares the fleet's zone. Public since this packet's sibling, [FL5_1_TRADE_PROTECTION.md](FL5_1_TRADE_PROTECTION.md), reuses it directly rather than duplicating the check. |
| `effective_power(world, fleet_id)` | Blockade power after the damage-threshold cutoff (`DAMAGED_EFFECTIVENESS_THRESHOLD_BP`). |
| `blockaded_provinces_for_fleet(world, fleet_id)` | Which hostile coastal provinces one fleet's zone reaches, war-gated. |
| `required_power(world, province_id, naval_definitions)` | The target-resistance floor a province demands before it can be fully choked. |
| `province_blockade_bp(world, province_id)` | The authoritative 0-10000 blockade strength for one province - every other strength query ultimately reduces to this one. |
| `blockade_bp_by_side(world, contributing_countries, province_id)` | The same strength calculation, restricted to one coalition's own contribution. |
| `siege_assist_bp(world, besieging_side_countries, province_id)` | Whether the besieging side's own blockade clears the coastal-siege-assist threshold. |
| `all_blockaded_provinces(world)` | Every currently (bp > 0) blockaded province, world-wide. |
| `blockade_tier(bp)` | Buckets a raw bp value into `NONE`..`FULL` for threshold-change detection. |
| `update_war_blockade_score(world, war)` | The next `blockade_score_attacker` value for one war record, given both sides' current blockade state. |

`process_day(world, events)` is the one function that writes anything, and it writes exactly one field: `world.blockaded_provinces`, a same-day snapshot of "which provinces were genuinely blockaded as of the last daily check," used only so the next tick's start/end/tier-change detection has something to diff against. Every strength/tier/eligibility *query* above ignores this stored snapshot entirely and recomputes live from `fleet_registry`/`war_registry`/`province_states` - so `world.blockaded_provinces` being one tick stale (which it always is, by definition, between two `process_day()` calls) can never make a query return a stale answer. This is the same guarantee [FL3_1_THREAT_OPPORTUNITY_MAP.md](FL3_1_THREAT_OPPORTUNITY_MAP.md) established for `NavalThreatMap`, reconfirmed here for the older system it was modelled on.

## Consumers cannot mutate blockade state

Grepped every `BlockadeSystemScript.`/`BlockadeSystem.` reference outside the file itself: `naval_ai_system.gd`, `naval_trade_protection.gd`, `fleet_logistics_system.gd`, `economy_system.gd`, `warfare_system.gd`, and `scripts/ui/conflict_marker_layer.gd`. Every single call site reads a return value from one of the pure query functions above; none assigns into `blockaded_provinces`, `fleet_registry`, `province_states`, or any other registry `BlockadeSystem` reads. The only writer of blockade-relevant fleet state is `SetFleetMissionCommand` (already command-gated, already tested), and the only writer of `world.blockaded_provinces` itself is `BlockadeSystem.process_day()`. No UI, AI, or downstream system has - or needs - any other path in.

## Event ordering

Within one `process_day()` call, for each province touched (sorted by ID, so the ordering is itself deterministic across provinces): `blockade_started`/`blockade_ended` fires first, then `port_fully_blockaded`/`port_unblocked` (registered ports only), then `blockade_level_changed` if the bucketed tier moved - all three compare against the one `world.blockaded_provinces` snapshot written at the end of the same call, so a province can legitimately fire all three in the same tick (e.g. a fresh fleet arrival that immediately reaches full blockade power).

Across the day's own scheduler order (`simulation_controller.gd`): `WarfareSystem.advance_day()` (which reads `siege_assist_bp()`/`update_war_blockade_score()` live) runs *before* `BlockadeSystem.process_day()` that same day. This is safe specifically because both of those are live pure-recompute queries, not readers of the not-yet-updated `world.blockaded_provinces` snapshot - `coastal_siege_support_changed` and the war's `blockade_score_attacker` both already reflect the day's real, current fleet positions even though `process_day()`'s own start/end/tier events for that identical transition fire slightly later in the same tick.

**Peace and annexation** were the two named transitions with no prior test coverage - confirmed as a real gap, not assumed to already work, and closed with `tests/naval_blockade_peace_annexation_test.gd`:
- **Peace**: a war record's `status` field is the single source of truth `active_war_between()` checks. The moment `peace_system.gd` sets `war["status"] = "ended"` (a command-driven change, landing before that day's `daily_systems` per the scheduler order [FL3_1_THREAT_OPPORTUNITY_MAP.md](FL3_1_THREAT_OPPORTUNITY_MAP.md) already established), `province_blockade_bp()` drops to zero immediately - proven, not asserted, by the test calling it directly between the mutation and the next scheduler tick. The very next `process_day()` fires `blockade_ended` with no one-day lag.
- **Annexation**: a province's `owner` field changing to the blockading country makes `blockaded_provinces_for_fleet()`'s own `target_owner == owner` self-exclusion apply immediately - a country cannot blockade its own newly annexed territory. Same same-day release proven the same way.

## Consumer reconciliation

Every consumer that derives a real gameplay effect from blockade strength calls `province_blockade_bp()` (or `all_blockaded_provinces()` to enumerate targets first) directly, live, every time it needs the value - none of them read a cached or precomputed field:

| Consumer | Call site | Effect |
|---|---|---|
| `EconomySystem.recalculate_all`/`recalculate_country` | `economy_system.gd:203,221` | `blockade_loss` ledger deduction, proven equal to the formula in `naval_blockade_test.gd`'s own economy-integration case. |
| `EconomySystem._complete_naval_construction` | `economy_system.gd:501` | Delays a port's naval construction completion by one day while blockaded above threshold. |
| `FleetLogisticsSystem.process_day` | `fleet_logistics_system.gd:137` | Reduces in-port repair rate while the port is blockaded above threshold. |
| `WarfareSystem.advance_day` | `warfare_system.gd:351,441` | Coastal siege-assist bonus and `blockade_score_attacker` war-score accumulation. |
| `NavalTradeProtection` | `naval_trade_protection.gd` | Reuses `zone_is_contested`/`DAMAGED_EFFECTIVENESS_THRESHOLD_BP` for its own, mission-gated eligibility - see [FL5_1_TRADE_PROTECTION.md](FL5_1_TRADE_PROTECTION.md). |
| `conflict_marker_layer.gd` (UI) | `conflict_marker_layer.gd:234-244` | Renders blockade markers/tiers on the map. |

Since every one of these calls the same authoritative function rather than a private copy, they reconcile by construction - there is no second formula anywhere in the codebase that could drift out of sync with `province_blockade_bp()`.

## Verification

- `tests/naval_blockade_test.gd` (pre-existing, re-run clean): eligibility, effective power, damage scaling, target resistance, multi-fleet combination, contested zones, economy ledger integration, coastal siege assist, all four blockade/port events, tier-change events, save/load round trip.
- `tests/naval_blockade_peace_annexation_test.gd` (new): the two previously-untested transitions above - same-day blockade release on peace concluding and on the blockaded province being annexed by the blockading side, each proven both as an immediate query-level effect and as a same-tick `blockade_ended` event with no persisted-state lag.
- Registered in `tools/testing/run_all_tests.py`.

## Deliberately out of scope for this packet

- **Any change to `BlockadeSystem` itself.** Both transitions above already worked correctly by construction (a pure, live-recomputing query layer has no special-case surface for "war ended" or "ownership changed" to slip through); this packet only proved and documented that, per the roadmap's own framing of FL5.2 as closing the *contract*, not reopening the *implementation*.
- **A versioned schema document for the contract table above** - FL5.3 (downstream boundary lock) is the packet that formally versions what future pillars may consume; this packet establishes what the contract *is* so FL5.3 has something concrete to lock.
