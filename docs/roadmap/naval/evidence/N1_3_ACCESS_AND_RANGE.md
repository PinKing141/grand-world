# N1.3 - Naval Access, Basing Rights, and Supply Range

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N1.3, and the N1B "central access and basing policy queries" work packet in [01 - N1 Maritime Graph Authority](../01_N1_MARITIME_GRAPH_AUTHORITY.md)

## What was built

- `scripts/simulation/maritime_graph.gd`: refactored `find_route()` onto two shared private helpers, `_dijkstra_from()` (single-source Dijkstra returning full `best_cost`/`came_from`) and `_reconstruct_path()`. Added a new public `nearest_matching(from_id, matches: Callable, speed_multiplier_bp)`: runs one Dijkstra from the origin and returns the lowest-cost node satisfying an arbitrary predicate, tie-broken by lowest stable ID - the same determinism guarantee `find_route` already has. This avoids recomputing a full route per candidate port for "nearest X" style queries.
- `scripts/simulation/naval_access_policy.gd`, `class_name NavalAccessPolicy`: the three access questions from [01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md#access-and-basing-rules), kept strictly separate per that document's instruction:
  - `can_sail(graph, zone_id)` - question 1. Trivial today: any zone `MaritimeGraph` already considers navigable (closed water is excluded at the graph level, from N1.1).
  - `can_dock(graph, world, country, port_id)` / `dock_failure_reason(...)` - question 2. Host is the port's controller if set, else its owner. Own/unclaimed ports always dock; otherwise alliance, subject/overlord relationship (either direction), or the existing `military_access` diplomatic relation (reused as the `naval_access` proxy - no dedicated relation type exists yet) grant docking.
  - `can_base(graph, world, country, port_id)` - question 3. Deliberately stricter and simpler than docking: only direct ownership/control grants basing rights today. No basing-rights grant/cost mechanism exists yet (00_SCOPE: "normally with diplomatic/economic cost later") - this is N2+ territory once fleets and commands exist to request it.
  - `supply_range_query(graph, world, country, zone_id, max_range_days, speed_multiplier_bp)` - the N1 supply range query from [01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md#supply-range-query): returns `supplied`, `nearest_port_id`, `range_cost`, `range_limit`, `route`, `failure_reason`. Built on `MaritimeGraph.nearest_matching` against `can_base`.
- `tests/naval_access_policy_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Deliberate design choice: war does not grant docking

`ProvincePathfinder.can_enter` (land) treats being at war with a province's host as sufficient to enter it - that is the invasion mechanic. `NavalAccessPolicy.can_dock` does **not** carry this over: sailing into a hostile harbour and peacefully docking is not the same act as marching an army into hostile territory to fight there. A captured port's *controller* becomes its host (checked ahead of owner), so occupation is already covered by the ordinary ownership check - no separate war branch was needed or added. Verified directly in the test: declaring an active war between Burgundy and England does not grant Burgundy docking at Calais.

## Why no cache/invalidation layer yet

Neither `MaritimeGraph` nor `NavalAccessPolicy` holds any state derived from ownership, diplomacy, or port data - `MaritimeGraph` is built once from static baked JSON (confirmed in [N1_2](N1_2_RUNTIME_TOPOLOGY.md)), and `NavalAccessPolicy` is a set of stateless static functions that read `CampaignWorldState`/`DiplomacySystem` fresh on every call. There is nothing to invalidate. [01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md#supply-range-query) anticipates caching "by country/access revision" once real usage patterns (N2 fleet AI calling this every AI tick, for example) make it a measured performance need - adding a cache now, before any caller exists, would be exactly the kind of premature abstraction this project's conventions avoid. Left as an explicit open item rather than silently dropped.

## Results (verified via `tests/naval_access_policy_test.gd`, exit 0, no errors)

- Own-port docking and basing: always allowed.
- Unrelated country: docking and basing both denied by default.
- Active war alone: does **not** grant docking (the deliberate asymmetry above).
- Alliance: grants docking but **not** basing (demonstrates the can_dock/can_base split holds even when the underlying host check would otherwise differ).
- Subject/overlord relationship (either direction): grants docking.
- Explicit `military_access` relation: grants and revokes docking correctly.
- A sea zone is never dockable or basable as if it were a port.
- `supply_range_query`: from the Straits of Dover, England's nearest basing port is Calais (tie-broken over Kent, both one port-leg away, by lowest stable ID); Burgundy's nearest is its own Picardie, not England's - confirms the query is genuinely per-country, not just "nearest port to a zone."
- A zero-day range limit still resolves and reports the nearest port, but `supplied = false` with a reason - matches the contract's "still return values, just mark unsupplied" shape rather than an all-or-nothing result.
- A `closed_water` zone query rejects immediately with a reason, for any country.
- No regression: re-ran `tests/maritime_graph_test.gd` and `tests/naval_definitions_test.gd` after the `find_route`/`nearest_matching` refactor - both still pass.

## Deferred to N2+

- A dedicated `naval_access` diplomatic relation distinct from land `military_access` (currently reused as a proxy).
- A real `fleet_basing_rights` grant/cost mechanism beyond raw ownership.
- Repair-specific permission (the roadmap groups "sail/dock/base/repair" together in the N1.3 checklist entry; repair eligibility is identical to basing eligibility today - `can_base` - since no separate repair-capacity concept exists until N2's ship/fleet registries do).
- Cache/invalidation, once a real caller and a measured cost exist.
