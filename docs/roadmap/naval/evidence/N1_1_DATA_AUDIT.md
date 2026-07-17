# N1.1 - Maritime Graph Data Audit

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N1.1, and N1A in [01 - N1 Maritime Graph Authority](../01_N1_MARITIME_GRAPH_AUTHORITY.md)  
**Scope:** data audit and versioned format only. No runtime pathfinding, access policy, or fleet logic exists yet (that is N1B onward).

## What was built

- `tools/naval/build_naval_graph_data.py` — a baker (mirrors the existing `tools/economy/build_economy_data.py` pattern) that reads `assets/province_graph.json` and `docs/data/1444_ownership_manifest.csv`, classifies every water record, derives every port candidate, applies reviewed CSV overrides, and writes `assets/naval_definitions.json` plus `docs/data/naval_graph_validation.md`. Supports `--check` for CI staleness verification, matching the other data bakers wired into `tools/testing/run_all_tests.py`.
- `tools/naval/sea_zone_overrides.csv` / `tools/naval/port_overrides.csv` — the versioned override format, seeded with the N0.3 Channel/Iberian fixture region.
- `assets/naval_definitions.json` — the baked output: `version`, `graph_content_hash`, `sea_zones` (566 entries), `ports` (1,141 entries).
- `scripts/simulation/naval_definitions.gd` — `class_name NavalDefinitions`, a definitions loader (`load_default()`/`from_data()`/`is_valid()`/`error()`) following the same shape as `character_definitions.gd`, plus sorted `sea_zone_ids()`/`port_ids()`/`enabled_port_ids()` accessors. This is a data loader, not the N1B `MaritimeGraph` runtime API.
- `tests/naval_definitions_test.gd` — headless test asserting the baked definitions load, the Channel/Gibraltar fixture zones classify `coastal_sea`, the fixture ports (Calais, Kent, Picardie, Algarve, Cadiz, Barcelona) resolve correctly, and malformed data (unknown classification, dangling `primary_exit`) is rejected. Registered in `tools/testing/run_all_tests.py` `GODOT_TESTS`, with the baker registered in `PYTHON_TESTS` (`--check` mode).

## Classification method

Water records are grouped into connected components using their `sea_neighbors` graph (BFS/union over water-to-water edges only). The largest component is treated as the navigable "world ocean"; every water record inside it defaults to `coastal_sea` (has at least one land neighbour) or `open_ocean` (none); every water record outside it defaults to `closed_water` (a lake or otherwise non-navigable body). `inland_sea` is never assigned by the default heuristic — it is authored-override-only, per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#sea-zone-classification) ("must not be guessed each campaign from country ownership").

Port candidates are every `land` record with `coastal == true` and at least one `sea_neighbors` entry — the baseline eligibility rule from N1's "Port Derivation" section. Ownership eligibility ("valid owner/controller entry... when active") is a runtime concern for N1B+, not baked into the candidate set; the 1444 owner is recorded as provenance only (`owner_1444`).

## Results (see full report: [naval_graph_validation.md](../../data/naval_graph_validation.md))

| Metric | Value |
|---|---|
| Sea zones classified | 566 |
| `coastal_sea` | 335 |
| `open_ocean` | 147 |
| `closed_water` (candidate lakes) | 84 |
| `inland_sea` | 0 (override-only, none authored yet) |
| Port candidates derived | 1,141 |
| Ports without any sea exit | 0 |
| Asymmetric sea-neighbour edges | 0 |
| Channel/Iberian reviewed fixture ports | 29 |
| Reviewed sea-zone overrides | 10 |

The reciprocity check initially reported 1,957 "asymmetric" edges on the first run; this was a bug in the audit tool, not the graph — a water record's own `sea_neighbors` lists water-to-water adjacency, while a land record's `sea_neighbors` (its sea exits) are reciprocated on the water record's `land_neighbors`, not its `sea_neighbors`. Fixed the check to compare the correct field pairs per the N1A "Every enabled port reaches at least one navigable sea zone" / "No asymmetric navigable edge" requirements; re-run confirms **0** genuine asymmetric edges — `province_graph.json`'s adjacency is fully reciprocal.

**Revised during N1.4 gate testing:** the original 1,351 port-candidate figure included 210 lake-shore provinces whose *only* sea neighbours are `closed_water` zones (non-navigable lakes) — they had no real naval exit at all. `candidate_ports()` now filters `sea_exits` down to navigable zones and drops a candidate entirely if none remain, bringing the count to 1,141 (see `docs/data/naval_graph_validation.md`'s "Coastal land excluded as port candidates" line). This was caught by [N1_4](N1_4_TOOLING_AND_GATE_TESTS.md)'s "every enabled port reaches at least one navigable sea zone" gate test, not by N1.1 itself — recorded here since it changes an N1.1 output.

## Known issue found (not fixed in this pass)

`assets/province_graph.json` contains 79 province `name` fields with a baked-in Unicode replacement character (`�`) in place of an accented letter — e.g. `"Val�ncia"` (should be "Valéncia") and `"Andaluc�a"` (should be "Andalucía"). Two of these are in the N0.3 Iberian fixture set. This is a pre-existing defect in the source graph's name-baking pipeline (likely a mis-decoded source encoding upstream of `tools/map_graph/build_province_graph.py`), not something introduced by the naval tooling — the naval baker just passes the name through for the validation report's readability. Out of scope to fix here; flagged for whoever owns `tools/map_graph/build_province_graph.py` / the original province-name source data. It does not affect naval definitions correctness (`naval_definitions.json` does not store names, only IDs), only the readability of the generated report and any future UI that displays these province names verbatim.

## Headless test environment notes (for future N-slice work)

- Brand-new `class_name` scripts are not visible to other scripts until Godot's global script class cache (`.godot/global_script_class_cache.cfg`) is rebuilt. Headless `--script` execution does **not** rebuild it. Fix: run `Godot*_console.exe --headless --editor --path . --quit-after 60` once after adding a new `class_name` file, before running `--script` tests against it. Hit this for `NavalDefinitions`; future new naval classes (`MaritimeGraph`, fleet/ship registries, etc.) will need the same one-time step in a fresh environment.
- `JSON.parse_string()` parses every JSON number as `float`, never `int`, in this Godot build. Two consequences confirmed the hard way while getting `naval_definitions.gd` and its test to pass:
  - `String(x)` has no constructor for numeric Variants (int or float) — raised a runtime "Invalid call 'String' constructor" error, not a silent bad conversion. Always use `str(x)` for numeric-to-string conversion; reserve `String(x)` for values already known to be strings (JSON string fields, or dictionary keys from `for k in dict`, which are always `String`).
  - `str(1255.0)` renders `"1255.0"`, not `"1255"` — converting a JSON-sourced numeric ID to a dictionary-key string requires `str(int(x))`, not `str(x)`.
  - Cross-type numeric membership checks are unreliable: `1269 in [1269.0, 1271.0]` (int literal against an Array of floats sourced from JSON) evaluated `false` in this build, contrary to the assumption that Godot Variants numerically promote across `==`. Any comparison mixing a locally-typed `int` against a JSON-sourced `Array`/`Dictionary` value needs both sides explicitly cast to the same type first.
  This is a real, previously-undocumented gotcha for this codebase — every future naval definitions/registry class that round-trips IDs through JSON needs to apply the same `str(int(x))` discipline, not just this one file.

## Deferred to later N1 work packets

- Runtime `MaritimeGraph`/`is_sea_zone`/`sea_neighbors`/pathfinding API — N1B.
- Access/basing policy (`naval_access`, `fleet_basing_rights`) — N1B/N1.3.
- Supply range query — N1.3.
- Debug overlay, route preview, malformed-override interactive tooling — N1D/N1.4.
- Full-world Channel/Iberian *content* pass (harbour levels, shipyard capability, real historical balance) — the 29 fixture ports here carry placeholder baseline capability values (`harbour_level: 1`, `shipyard: false`, flat basis-point defaults) explicitly tagged `confidence: placeholder-reviewed`, not final content.
