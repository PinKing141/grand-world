# N5.1 - Province Blockade Level Changed (Meaningful Thresholds)

**Status:** Recorded. This closes out every item in 05_N5's "Events and Queries" minimum-signals list except the trade-protection output, which is its own separate, unbuilt work packet.
**Satisfies:** the "meaningful thresholds" portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N5.1's threshold-events item, and the last remaining "Events and Queries" line in [05 - N5 Strategic Effects](../05_N5_STRATEGIC_EFFECTS.md)
**Scope:** `BlockadeSystem.blockade_tier()` (a pure bucketing function) and one new event, `blockade_level_changed`, emitted by `process_day()` when a province's tier changes. No new persisted field, no schema bump - this reuses the exact bp values `blockaded_provinces` already stores.

## Why this needed no new state at all, unlike the two rounds before it

The blockade started/ended round needed a brand-new persisted field. The port-fully-blockaded round reused that field but needed the values to become integers instead of booleans. This round needs neither - `blockaded_provinces` already stores each blockaded province's *exact* bp value from the previous round's change. A "tier" is just a bucketing function applied to that already-stored number, computed fresh for both yesterday's stored value and today's freshly-computed value, compared once. No additional persistence, no schema implications: the third and final "Events and Queries" round in this arc costs strictly less new code than either of the two before it, because each round has been deliberately building the minimum next increment on top of what the previous round already established.

## Architectural choices

**Five buckets (light/moderate/heavy/severe/full) at 2500-bp intervals, not the fewer/more coarse or fine buckets 05_N5 leaves unspecified.** 05_N5 only says "meaningful thresholds," without naming a count or boundary. Five roughly-even buckets across the 0-10000 bp range is the simplest scheme that is still coarse enough to "avoid daily notification spam" (05_N5's own stated goal) for a blockade that fluctuates by a few hundred bp day to day near a boundary, while still being fine-grained enough to be informative. Not approved balance, matching every other placeholder magnitude this session has introduced.

**`blockade_tier()` is a pure function taking a bp integer, not a query that re-derives bp itself.** This keeps it trivially testable and reusable - `process_day()` calls it twice per candidate province (once for the stored previous value, once for the freshly computed current value) without needing to re-run `province_blockade_bp()` a third time. A future UI/AI consumer wanting "what tier is province X in right now" can call `blockade_tier(BlockadeSystem.province_blockade_bp(world, x))` directly, composing the two functions rather than needing a third dedicated query.

**A large jump (e.g., a fleet growing from a token presence to an overwhelming one in a single day) fires exactly one event carrying the *final* tier, not one event per skipped intermediate tier.** `process_day()` only ever compares "yesterday's tier" against "today's tier" - it has no memory of tiers that were never actually observed on any given day, so a province cannot have "passed through" a tier it was never in on a settled day. This is a deliberate consequence of the daily-comparison design, not an oversight, and is exactly what "avoid daily notification spam" implies: a presentation layer listening for tier changes should see the settled state, not a synthetic history of levels that were never separately true.

**`blockade_level_changed` fires for any blockaded coastal province, not gated to registered ports the way `port_fully_blockaded`/`port_unblocked` are.** This matches "blockade started/ended"'s own broader scope (both apply to whatever `blockaded_provinces_for_fleet()` can target, port or not), while the port-specific pair remains the one signal 05_N5 explicitly narrows to ports.

## What was built

- `scripts/simulation/blockade_system.gd`: `BLOCKADE_TIER_NONE`/`LIGHT`/`MODERATE`/`HEAVY`/`SEVERE`/`FULL` constants; `blockade_tier(bp: int) -> int`; `process_day()` gained one more comparison per candidate province using the same `previous`/`current` dictionaries the started/ended and full/unblocked checks already read.
- `scripts/simulation/simulation_event_bus.gd`: `blockade_level_changed(province_id: int, tier: int)`.
- `tests/naval_blockade_test.gd`: extended (no new file) with a section proving a newly-formed light blockade fires exactly one tier-change event, an unchanged tier on a following day fires nothing, a fleet reinforcement that jumps the blockade straight to full fires exactly one event carrying the full tier (not one per skipped intermediate tier), and releasing the blockade entirely fires exactly one event carrying the "none" tier.

## Results (verified via `naval_blockade_test.gd`, exit 0, no errors)

- A single-ship fleet's newly-formed blockade lands in the light tier and fires exactly one `blockade_level_changed(Picardie, LIGHT)`.
- An unchanged tier on a following day fires no additional event.
- Adding enough additional power to jump straight from light to a full (10000 bp) blockade in one day fires exactly one event carrying the full tier - not four events for the skipped moderate/heavy/severe tiers.
- Releasing the blockade entirely fires exactly one event carrying the "none" tier.
- No regression: re-ran all 42 Godot phase/core/naval tests after this round's changes - 41/42 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4/N5 evidence doc so far.

## Deliberately simple / deferred

- **Tier boundaries (2500/5000/7500/10000) are placeholder magnitudes, not approved balance**, same as every other threshold constant introduced this session.
- **No hysteresis/dead-zone around a boundary.** A blockade oscillating exactly at a boundary (e.g., 4999 <-> 5001 bp day to day) would still fire an event each time it crosses - 05_N5's "avoid daily notification spam" is satisfied by having few, coarse buckets, not by an explicit anti-flicker mechanism. A future round could add one if this proves noisy in practice.
- **No naval-blockade-scale stress/performance test.** This change adds no new queries of its own (it reuses already-stored/already-computed values) - the underlying deferred performance item remains open regardless, unchanged from every prior round in this arc.
