# FL5.1 - Trade-Protection Output

**Status:** Complete. Targeted tests pass (see Verification).
**Satisfies:** [05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md](../05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md)'s FL5.1 scope bullets - a stable, derived naval trade-protection result by country and zone/port; eligible fleet mission, effective power, supply and contested-zone rules; trade income kept outside the naval system; zero-with-explanation when no consumer exists; no fabricated income, routes, markets or trade nodes.

## What shipped

A new `scripts/simulation/naval_trade_protection.gd` (`class_name NavalTradeProtection`), a pure static query with no persisted state and no simulation-day hook - nothing calls it yet, matching the roadmap's explicit instruction not to implement trade gameplay in this slice:

- `is_fleet_eligible(world, fleet_id)` - at sea, `mission == "trade_protection"`, supplied, and not in a contested zone. Deliberately the same four rules `BlockadeSystem.is_fleet_eligible()` already enforces for `mission == "blockade"`, substituting only the mission string, rather than inventing a second eligibility model for what is structurally the same "is this fleet actually on station and able to project power here" question.
- `effective_power(world, fleet_id)` - the fleet aggregate's `total_attack`, scaled by hull-percentage basis points, dropping to zero below `BlockadeSystem.DAMAGED_EFFECTIVENESS_THRESHOLD_BP` - the same hard cutoff shape `BlockadeSystem.effective_power()` uses (reused via direct reference to the constant, not a second threshold). `total_attack` rather than `total_blockade_power` is the deliberate substitution: protecting shipping from raiders is a combat-capability question, not a siege-capability one, so the input differs even though the scaling shape does not.
- `assess(world, tag, location_id) -> Dictionary` - sums `effective_power()` across every one of the country's own fleets physically present at `location_id` and eligible, returning `{protection_score, eligible_fleet_ids, contested, reason}`. The four-way `reason` (protected / contested / present-but-ineligible / absent) makes "zero because nothing is here" and "zero because the zone is contested" distinguishable to a future consumer, matching the roadmap's "return zero with an explanation" requirement literally rather than just returning a bare int.

`BlockadeSystem._zone_is_contested()` was renamed to public `zone_is_contested()` (three call sites, one rename) so both systems share one contested-zone definition instead of a second copy of the same "an at-war opposing at-sea fleet is present in this zone" check - both cite the same 05_N5 "Contested Zones" source.

## Why this does not touch income, routes, markets or trade nodes

`assess()` only ever reads `fleet_registry`/`ship_registry`/`naval_definitions` and returns a plain `Dictionary` - it does not read or write `country_runtime`, `EconomySystem`, any ledger field, or any route/node concept, and nothing in the simulation scheduler calls it. The file's own header comment states this explicitly as a construction-level guarantee, not a promise to be checked later: until a real trade-system consumer is wired in, this slice has zero behavioural effect on the game. `_test_pure_query_no_side_effects()` proves the construction-level claim rather than just asserting it in prose: it snapshots `world.checksum()`, calls `assess()`/`effective_power()` several times, and requires the checksum to be byte-identical afterward.

## Verification

- `tests/naval_trade_protection_test.gd` (new): eligibility positive case plus all four negative cases (docked, wrong mission, unsupplied, contested); undamaged-vs-below-threshold effective-power scaling; `assess()`'s four distinct zero/non-zero reason cases (no fleet present, present-and-protected summed across two fleets, contested, present-but-unsupplied); a fleet at a different location never leaking into another zone's score; and the pure-query/no-side-effects checksum proof above.
- `tests/naval_blockade_test.gd` (pre-existing, unmodified apart from the `zone_is_contested` rename it depends on): re-run clean, confirming the rename introduced no regression to blockade eligibility, power, siege-assist, event, or save/load behaviour.
- Registered in `tools/testing/run_all_tests.py`.
- **Battle/peace/annexation transitions were not re-tested against `NavalTradeProtection` directly.** `is_fleet_eligible()`'s contested check calls `BlockadeSystem.zone_is_contested()` verbatim - the exact function [FL5_2_BLOCKADE_COASTAL_CONTRACT.md](FL5_2_BLOCKADE_COASTAL_CONTRACT.md)'s `naval_blockade_peace_annexation_test.gd` proves releases correctly, same-day, on both peace and annexation. This is claimed by shared implementation, not by a second, redundant test - matching this roadmap's own established "present, by inheritance not by design" pattern (see FL3_CLOSURE_AUDIT.md) rather than overclaiming untested coverage.
- No broader naval regression run beyond the above was judged necessary: this packet adds one new, currently-unconsumed file and renames one already-private method with a grepped-clean call-site count of three, so no other system's behaviour can change as a result.

## Deliberately out of scope for this packet

- **Any actual trade income, route, market or node model** - explicitly forbidden by the roadmap for this slice; `assess()`'s output has no consumer yet.
- **A `trade_protection` fleet-mission entry in whatever UI mission picker FL2.4 eventually builds** - FL2.4 is its own tracked packet; this slice only needed `SetFleetMissionCommand` to already accept an arbitrary mission string (confirmed by `naval_blockade_test.gd`'s own `"blockade"` usage), which it does.
- **A scheduler-level daily hook that calls `assess()` for every country** - premature with no consumer; adding one now would be dead code exercised only by its own test, not a real per-day cost anything currently depends on.
