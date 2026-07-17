# N1.2 - Runtime Maritime Graph Topology

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N1.2, and the N1B "Runtime graph API" work packet in [01 - N1 Maritime Graph Authority](../01_N1_MARITIME_GRAPH_AUTHORITY.md)  
**Scope:** topology exposure, movement costs, and deterministic route finding only. No access/basing permission checks, no supply range, no fleet/command integration - those are N1.3 and N2.

## What was built

- `scripts/simulation/province_graph.gd`: added `sea_neighbors(province_id)` (sorted, mirrors the existing `land_neighbors()`) and `is_water(province_id)`. `ProvinceGraph` remains the single raw-topology authority per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#geography); it previously only exposed land adjacency.
- `scripts/simulation/maritime_graph.gd`, `class_name MaritimeGraph`: built once from `ProvinceGraph` + `NavalDefinitions`. Provides:
  - Sorted accessors: `is_sea_zone`, `sea_zone_ids`, `sea_zone_classification`, `sea_neighbor_ids` (navigable-only), `is_port_province`, `port_province_ids`, `is_port_enabled`, `port_exits`, `sea_zone_ports` (reverse index), `is_coastal_land`, `anchor`, `is_strait`.
  - `leg_cost_days(from_id, to_id, speed_multiplier_bp)`: integer days per direct leg, `-1` if not connected. Sea-zone-to-sea-zone cost is keyed by destination classification (`coastal_sea`/`inland_sea` = 3 days, `open_ocean` = 5 days); port-to-zone and zone-to-port legs cost 1 day. `speed_multiplier_bp` (basis points, 10000 = baseline) lets N2 scale by a fleet's slowest-ship speed **without changing this graph**, per [01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md#movement-costs).
  - `find_route(from_id, to_id, speed_multiplier_bp)`: Dijkstra over the combined port/sea-zone graph, returning `{exists, path, total_days, origin_kind, destination_kind, uses_port_exit, uses_port_entry, blocked_reason_code, failure_reason}`. Origin/destination may each be a port ID or a sea-zone ID.
- `tests/maritime_graph_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Determinism

Reused the exact tie-break mechanism `ProvincePathfinder` already relies on for land movement, rather than inventing a second one: heap entries pack `(cost << 13) | province_id`, and the relaxation step additionally prefers the lower predecessor ID on cost ties (`new_cost == known and current < came_from[neighbor]`). Verified in the test: two consecutive `find_route(CALAIS, KENT)` calls return an identical path and cost. The 13-bit ID packing assumes province IDs stay under 8192; confirmed true for the current dataset (3,924 total records, highest observed ID in the 4900s) - this is the same assumption `ProvincePathfinder` already makes, not a new risk.

## Deliberately incomplete Route Result Contract

[01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md#route-result-contract) specifies a fuller result shape including `supplied_at_destination`, `range_cost`, and `range_limit`. Those fields depend on access/basing and supply-range logic that doesn't exist yet (N1.3). Rather than stub them with placeholder values that would look meaningful but aren't, `find_route()` omits them entirely; N1.3 will extend the same Dictionary shape once that logic lands. `uses_port_exit`/`uses_port_entry` and `blocked_reason_code`/`failure_reason` are implemented now since they're pure topology/reachability facts.

## Results (verified via `tests/maritime_graph_test.gd`, exit 0)

- 482 navigable sea zones exposed (566 total water records minus the 84 `closed_water` zones from N1.1 - confirms closed water is fully excluded from the routable graph, satisfying the N1E requirement "closed water never appears in a normal route").
- 1,141 ports exposed (revised down from N1.1's original 1,351 during N1.4 gate testing - see [N1_4_TOOLING_AND_GATE_TESTS.md](N1_4_TOOLING_AND_GATE_TESTS.md)); every `port_exits` entry has a reciprocal `sea_zone_ports` entry (asserted directly, not just assumed from N1.1's reciprocity check on the raw graph).
- Calais (87) → Kent (235): resolves via Straits of Dover (1271) in 2 days (1-day port-exit leg + 1-day port-entry leg), `uses_port_exit`/`uses_port_entry` both true.
- Algarve (230) → Cadiz (1749): resolves via the Straits of Gibraltar (1293) fixture crossing.
- Repeated calls return identical path and cost (determinism requirement).
- Unknown province IDs and `closed_water` zones both reject with a specific `blocked_reason_code` rather than crashing or silently returning a route.
- Speed-multiplier scaling verified: halving speed doubles leg cost, doubling speed roughly halves it (integer-truncated).
- No regression: re-ran `tests/naval_definitions_test.gd` (still passing) and `tests/phase_3_movement_test.gd` (land pathfinding, still passing) after adding `sea_neighbors()`/`is_water()` to the shared `ProvinceGraph`.

## GDScript pitfalls hit (added to the running list from N1.1)

- `var x := (a * b) / max(1, c)` fails to compile ("Cannot infer the type... doesn't have a set type") because `max()` returns an untyped `Variant` in this Godot build, so `:=` type inference fails even though both arguments are `int`. Fix: declare the explicit type (`var x: int = ...`) or avoid `max()`/`min()` in an inferred (`:=`) assignment entirely. Same applies to `min()`.

## Deferred to N1.3+

- Access/basing-right permission checks (`naval_access`, `fleet_basing_rights`).
- Supply range and "legal" nearest-port queries.
- Cache revisions/invalidation tied to ownership/diplomacy changes (not yet relevant - `MaritimeGraph` currently has no dependency on mutable campaign state at all, only static baked data).
- Debug overlay / route preview (N1.4).
