# Phase 4 Economy Data Baker

Run from the project root after changing province histories, the province graph, or Phase 4 economic definitions:

~~~powershell
python tools/economy/build_economy_data.py
~~~

The baker reads the undated 1444 values from `assets/provinces/*.txt` and the geographic classification from `assets/province_graph.json`. It writes:

- `assets/economy_definitions.json` — compact runtime province, trade-good, building, and unit definitions.
- `docs/data/economy_validation.md` — totals and validation findings for content review.

Runtime simulation loads only the baked JSON. Stable province, building, unit, and trade-good IDs are save-compatible content identifiers and must not be renamed casually after public saves exist.

Authoritative values use thousandths of a ducat and integer basis points. Display formatting must never be fed back into simulation state.
