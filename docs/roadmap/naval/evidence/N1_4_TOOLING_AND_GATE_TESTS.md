# N1.4 - Tooling and Gate Tests

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N1.4, and the N1D/N1E work packets in [01 - N1 Maritime Graph Authority](../01_N1_MARITIME_GRAPH_AUTHORITY.md)

## What was built

- `MaritimeGraph.describe_node(id)` / `explain_route(from_id, to_id, speed_multiplier_bp)`: human-readable trace naming each leg, its province name, classification, and per-leg cost — the console/test-trace form of "debug overlay and route/access explanation" that 01_N1 explicitly says is sufficient for N1 ("these are development tools; final art is not required").
- `NavalAccessPolicy.explain_dock(graph, world, country, port_id)`: names the *exact* relationship that decided a docking result (ownership, alliance, subject/overlord, explicit access, or denial), not just allow/deny.
- `tests/naval_graph_malformed_data_smoke.py`: exercises `build_naval_graph_data.py`'s override-rejection paths directly against synthetic temp CSVs (unknown province ID, land-as-sea-zone, invalid classification enum, water-as-port, primary_exit outside a port's own sea exits) and asserts each row is rejected with a specific reason **and never mutates the baked data**. Required threading an `overrides_path` parameter through `apply_sea_zone_overrides`/`apply_port_overrides` (default unchanged) so the test doesn't have to touch the real production CSVs.
- `tests/maritime_graph_stress_smoke.gd`: representative long-haul fixture paths (Portugal→Channel, Gibraltar→Mediterranean, a long Atlantic-to-Mediterranean haul), full reciprocity check at the *runtime* `MaritimeGraph` API surface (not just the raw JSON, which N1.1 already checked), "every enabled port reaches a navigable zone," and an 812-pair stress batch across all 29 fixture ports.
- Registered all three in `tools/testing/run_all_tests.py`.

## Two real bugs this gate testing caught

Writing these tests surfaced defects that N1.1-N1.3's narrower tests didn't exercise - exactly what a gate-test pass is for.

### 1. 210 port candidates had no real naval exit

The stress smoke's "every enabled port reaches a navigable sea zone" assertion failed for a batch of low-numbered province IDs. Root cause: N1.1's `candidate_ports()` accepted any coastal land province with *any* `sea_neighbors` entry, without checking whether those neighbours were actually navigable. 210 of the original 1,351 candidates touched *only* `closed_water` (lake) zones - they were lake-shore towns, not naval ports. Fixed in `tools/naval/build_naval_graph_data.py`: `candidate_ports()` now takes the already-classified `zones` and filters `sea_exits` down to navigable zones, dropping the candidate entirely if none remain. Re-baked: 1,141 port candidates (down from 1,351); see the revised [N1_1_DATA_AUDIT.md](N1_1_DATA_AUDIT.md) and `docs/data/naval_graph_validation.md`'s new "Coastal land excluded as port candidates" line (210).

### 2. A "performance optimization" silently broke the port/zone reverse index

While chasing a genuine performance regression (see below), an attempted optimization changed `MaritimeGraph`'s internal `_zone_ports` reverse index from plain `Array` values to `PackedInt32Array` values, keeping the same "read a Dictionary value, call `.append()` on it in place" pattern that worked for `Array`. It silently failed for `PackedInt32Array`: retrieving a `PackedInt32Array` from a `Dictionary` yields a **copy** in this Godot build (value semantics), so every `.append()` mutated a throwaway copy and the dictionary's stored value stayed empty forever. The result: every sea zone reported zero adjacent ports, breaking every route that needed to arrive at or depart from a port via a zone (i.e. almost every real route). Caught immediately because `maritime_graph_test.gd` (from N1.2) failed outright rather than just running slow. Fixed by building the reverse index with plain `Array`s (reference-typed, safe to mutate via a retrieved reference) and converting to `PackedInt32Array` only via a final direct assignment per key, never an in-place mutation of a value pulled from the dictionary. Documented as a comment at the fix site so this specific footgun doesn't get reintroduced.

## The actual performance regression (and fix)

The N1.3 refactor that let `find_route` and `nearest_matching` share one Dijkstra core (`_dijkstra_from`) dropped `find_route`'s early-exit-at-target optimization, and `nearest_matching`'s post-hoc "collect all reachable candidates, then sort" approach never had one. The result: every `find_route` call ran a **full, un-early-exited traversal of the entire ~1,833-node navigable graph** regardless of how close the destination was. Measured: 812 fixture-port route queries took **78.5 seconds**.

Fixed properly rather than just raising the test's budget:

1. `_dijkstra_from` now accepts an optional `target_id` (for `find_route`) or `matches: Callable` (for `nearest_matching`) and breaks out of the pop loop the instant either condition is satisfied. This is correct, not just faster: Dijkstra only finalizes a node's cost when it is *popped* (not merely relaxed), and the packed-heap ordering already guarantees nodes pop in non-decreasing cost with lowest-ID tie-breaking - so the first popped node matching either condition is provably the correct, deterministic answer. `nearest_matching` no longer needs its own post-hoc `sort_custom` pass at all.
2. `_neighbors_of(id)` - called on every node a Dijkstra run visits - now memoizes its result per graph instance instead of rebuilding and re-sorting a combined neighbour array on every single call.

After both fixes: the same 812-query batch dropped to roughly 5-6 seconds (measured 5,082ms / 5,877ms across repeated runs) - about a 13-15x improvement over the broken full-traversal version, and orders of magnitude faster than the pre-fix state once the reverse-index bug above is also accounted for. The stress test's budget constant (`ALL_ROUTE_BATCH_BUDGET_MS = 20000`) is deliberately generous and documented as a smoke-test guard against a gross regression (e.g. an accidental return to full-graph traversal), **not** a tuned or approved N0 performance budget - that number remains an open item (see [N0_BASELINE_INVENTORY.md](N0_BASELINE_INVENTORY.md)).

## Results (all headless tests, exit 0, no errors)

- `naval_definitions_test.gd`: sea_zones=566 ports=1141 closed_water=84
- `maritime_graph_test.gd`: sea_zones=482 ports=1141 calais_kent_days=2
- `naval_access_policy_test.gd`: calais_range=1 (plus explanation-string assertions)
- `maritime_graph_stress_smoke.gd`: routes=812 elapsed_ms≈5000-6000 zone_edges_checked=2168
- `naval_graph_malformed_data_smoke.py`: sea_zone_issues=3 port_issues=3, all rejected without mutating baked data
- No regression: `tests/phase_3_movement_test.gd` (land pathfinding) still passes after all `MaritimeGraph`/`ProvinceGraph` changes.

## Export-content check

Not independently re-run this session (the full Windows export test, `tools/testing/run_all_tests.py`'s `export_and_start`, packages the entire project and takes significant time). Reasoned instead: `assets/naval_definitions.json` is an ordinary file under `assets/`, following the exact same pattern as `economy_definitions.json` and the other already-exported definition files, and all new naval `.gd` scripts live under the normally-exported `scripts/simulation/` tree. There is nothing naval-specific about the export path that the existing whole-project export test wouldn't already cover on its next full run. Flagged here rather than silently assumed.

## Deferred

- Cache/invalidation for access queries - still not needed; see [N1_3](N1_3_ACCESS_AND_RANGE.md).
- A real numeric performance budget - remains N6-gated per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#performance-principles), tracked as an open item since N0.
- A visual (Node-based) debug overlay - deliberately not built; no naval marker/camera layer exists yet to host one (that's N6 UX), and the console/test-trace form is explicitly accepted for N1.
