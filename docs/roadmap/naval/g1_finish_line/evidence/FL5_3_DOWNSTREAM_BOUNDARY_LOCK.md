# FL5.3 - Downstream Boundary Lock

**Status:** Complete (documentation packet - no code change).
**Satisfies:** [05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md](../05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md)'s FL5.3 scope bullets - which naval IDs/queries future trade, exploration and colonisation may consume; an explicit prohibition on downstream pillars changing fleet identity, transport ownership, sea-zone identity or port identity without schema review; versioning/compatibility expectations for the consumer API; deferred mechanics recorded separately from G1 blockers.

No trade, exploration or colonisation pillar exists in this codebase yet (grepped: no file under `scripts/` references "trade route", "trade node", "colonis(z)e", or "exploration" as a system name). This packet locks the boundary in writing *before* such a pillar exists, per the roadmap's own instruction not to implement any of those systems as part of G1.

## Naval IDs a downstream pillar may read

All naval identifiers are opaque `String` (or `int` for map-native IDs) keys into `CampaignWorldState` registries. A downstream consumer may **read** any of the following by key, and must treat every one of them as **immutable once assigned** - it may compare, store, and log them, but never construct, parse, or reassign one itself:

| ID | Format | Source of truth | Lifetime |
|---|---|---|---|
| `fleet_id` | `"f_<n>"`, monotonic `world.take_counter("next_fleet_id")` | `world.fleet_registry` | Until the fleet is destroyed/merged away; never reused within a save. |
| `ship_id` | `"s_<country_tag>_<n>"`, monotonic `world.take_counter("next_ship_id")` | `world.ship_registry` | Until the ship sinks/decommissions; never reused. |
| `transport_operation_id` | `"transport_<n>"`, monotonic counter | `world.transport_operation_registry` | Until the operation completes or is cancelled; never reused. |
| `naval_construction_id` | `"naval_construction_<n>"`, monotonic counter | `world.naval_construction_registry` | Until construction completes or is cancelled; never reused. |
| `naval_battle_id` | `"naval_battle_<n>"`, monotonic counter | `world.naval_battle_registry` | Until the battle resolves; never reused. |
| Sea zone ID | `int`, static map data | `MaritimeGraph` | Fixed for the life of the map; not simulation-generated, never changes. |
| Province/port ID | `int`, static map data | `ProvinceGraph` / `NavalDefinitions.is_port()` | Fixed for the life of the map; not simulation-generated, never changes. |
| `war_id` | `"war_<n>"`, monotonic counter | `world.war_registry` | Until the war resolves; never reused. |

All monotonic counters live in `world.global_counters` (or a dedicated counter namespace `take_counter()` reads), are part of `checksum()`, and are therefore already deterministic and replay-safe by the same guarantee every other checksummed counter in this project has - a downstream pillar gets that guarantee for free by only ever reading, never minting, one of these IDs.

## Naval queries a downstream pillar may consume

Only the pure, static, already-tested query functions documented for this finish-line slice - nothing else, and specifically not any private (`_`-prefixed) helper, regardless of how stable it looks:

- **`NavalTradeProtection.assess(world, tag, location_id)`** and its two component queries (`is_fleet_eligible`, `effective_power`) - [FL5_1_TRADE_PROTECTION.md](FL5_1_TRADE_PROTECTION.md). The intended entry point for a future trade system's own protection/risk modelling.
- **`BlockadeSystem`'s full query set** - [FL5_2_BLOCKADE_COASTAL_CONTRACT.md](FL5_2_BLOCKADE_COASTAL_CONTRACT.md). The intended entry point for a future trade system's own route-risk modelling (a blockaded port is a bad place to trade) or a future colonisation system's own "is this coast contested" check.
- **`CampaignWorldState.get_fleet`/`get_ship`/`country_fleets`/`fleet_ships`/`get_province_owner`** - already-public read accessors, safe for any consumer.

**Explicitly not part of this contract**: `NavalThreatMap.assess()` (FL3.1) is naval-AI-internal decision support, not a stable downstream output - its `threat_score`/`opportunity_score` combination is documented in its own file as "not an approved N3/N6 budget," i.e. a first-slice heuristic expected to change as FL3 continues. A downstream pillar that reads it today would silently get different answers the next time naval AI balance changes, with no version bump to warn it. If a future pillar genuinely needs threat/danger data, it should get its own stable query built for that purpose (mirroring how FL5.1 built its own eligibility/power model rather than reusing `NavalThreatMap` directly), not a direct dependency on an AI-tuning internal.

## What downstream pillars may never do without schema review

None of the following may be done by any code outside `scripts/simulation/*.gd`'s existing naval files and their own commands, regardless of which future pillar wants it:

- **Change fleet identity** - reassign, alias, or reuse a `fleet_id`; merge two fleets' identities outside `MergeFleetsCommand`; construct a synthetic `fleet_id` string by hand instead of reading one out of `fleet_registry`.
- **Change transport ownership** - reassign a `transport_operation_id`'s `owner_country_id`, or move cargo between operations, outside `CreateTransportOperationCommand`/`CancelTransportOperationCommand`.
- **Change sea-zone identity** - redefine, split, merge, or renumber a `MaritimeGraph` zone. Sea zones are static map data, not simulation state; no runtime system may mutate the map graph itself.
- **Change port identity** - redefine which province `NavalDefinitions.is_port()` recognises, or its `harbour_level`, outside the authored `NavalDefinitions` data file.

Any of the above, if a future pillar genuinely needs it, requires a design review against this document (and likely a new roadmap slice of its own), not a direct edit landing alongside unrelated trade/exploration/colonisation work.

## Versioning and compatibility expectations

This contract has no version number yet because it has no consumer yet - versioning a zero-consumer API would be premature ceremony. The rule going forward: **the first real downstream pillar to consume `NavalTradeProtection` or `BlockadeSystem`'s query set is what starts versioning.** At that point:

- Any change to a query function's **signature or return-dictionary shape** (adding/removing/renaming a key, changing a key's type) is a breaking change and must be called out explicitly in that change's own commit/evidence, with the consuming pillar's own code updated in the same change - not silently landed and discovered later.
- Any change to a query function's **numeric formula** (e.g. `BlockadeSystem`'s damage-scaling curve, or `NavalTradeProtection`'s effective-power calculation) that does not change the shape above is not a breaking change to the *contract*, but must still be flagged to whoever owns the consuming pillar, since it changes what their derived output means. This mirrors how `BlockadeSystem`'s own header already documents its formulas as "not approved balance."
- ID formats (the table above) are considered stable and are not expected to need a version bump - they are opaque keys by design, and no consumer should ever have parsed their internal structure (e.g. splitting `"f_3"` on `"_"`) in the first place.

## Deferred mechanics (explicitly not G1 blockers)

Recorded here, separately from anything tracked as a G1 gap elsewhere in this roadmap, so a future trade/exploration/colonisation design pass has a starting list rather than rediscovering these from scratch:

- Actual trade income, trade routes, trade nodes, and market goods - the mechanic `NavalTradeProtection` was explicitly built to leave untouched (FL5.1).
- Naval exploration (unexplored sea zones, discovery, cartography) - no such concept exists anywhere in this codebase today; not scoped by G1 at all.
- Naval colonisation (overseas settlement founded via a fleet/transport) - `TransportSystem` already moves armies overseas for conquest; founding a new settlement rather than attacking an existing province is a distinct, unbuilt mechanic.
- A dedicated visibility/fog-of-war layer that would let a future pillar's queries be filtered by what a country can actually observe, rather than omniscient - noted as a known, deliberate absence in [FL3_1_THREAT_OPPORTUNITY_MAP.md](FL3_1_THREAT_OPPORTUNITY_MAP.md) and reconfirmed here as equally absent for every query this document names.

None of the above block FL5, or G1: FL5's own exit gate only requires the *existing* trade-protection and blockade/coastal outputs to be stable, test-backed, and safe for a future consumer - which this document and its two sibling packets now establish.
