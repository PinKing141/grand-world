# N0.1 - Baseline Inventory

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N0.1  
**Captured:** 2026-07-17, against the working tree at the time of the naval roadmap kickoff.

## Water / coast / sea-neighbour / strait counts

Recomputed directly from `assets/province_graph.json` (3,924 total province records) rather than trusted from prose:

| Metric | Count | Roadmap claim | Match |
|---|---|---|---|
| Records with `classification == "water"` | 566 | 566 baked water-region records | Yes |
| Records with `coastal == true` | 1,373 | 1,373 coastal graph records | Yes |
| Records with a non-empty `sea_neighbors` map | 1,859 | 1,859 sea-neighbour graph records | Yes (per-record count; unique undirected sea-neighbour edges dedup to 3,043; strait edges dedup to 4) |

No separate "water-region baking" tool exists outside the main graph build. `tools/map_graph/build_province_graph.py` is the single topology authority producing `classification`, `coastal`, `land_neighbors`, `sea_neighbors`, `straits`, `area`, `anchor`, `bbox`, `name`. `tools/hydrography/` only validates river definitions, not water regions — N1.1 will need its own water/port audit tool, there is nothing to reuse besides the graph file itself.

`assets/province_graph.json` schema root: `version`, `map_size`, `terrain_costs`, `provinces` (dict keyed by string province ID). No content hash is currently embedded in the file; N1 will need to add one (see [01 - N1](../01_N1_MARITIME_GRAPH_AUTHORITY.md) "stable graph content hash").

## Current save schema, scheduler order, economy ledger, war fields

### Save schema

- `scripts/simulation/campaign_world_state.gd:6` — `const SAVE_SCHEMA_VERSION := 5`.
- Migration is sequential step-migration (`migrate_save_data()`, line ~167): `if schema == 1` → 2, `if schema == 2` → 3, etc., rejecting `schema < 1 or schema > SAVE_SCHEMA_VERSION`.
- `CampaignSaveService` (`scripts/simulation/campaign_save_service.gd`) writes to a `.tmp` file and atomically renames over the target; on load, checksum mismatch triggers rollback.
- Checksum (`campaign_world_state.gd:315`) covers canonical string parts of all major registries, including RNG stream states. Any new naval registry must be added to both `to_save_dict`/`apply_save_dict` and the checksum computation, and bump `SAVE_SCHEMA_VERSION` with an explicit migration step (schema 5 → 6) once naval state exists.

### Scheduler order

`SimulationScheduler.advance_one_day()` (`scripts/simulation/simulation_scheduler.gd:51`), comment: "Stable Phase 2 order: commands, daily rules, periodic rules, events, AI, then presentation subscribers react":

1. `process_commands()` — player commands due today.
2. `daily_systems`: `ArmyMovementSystem.advance_day` → `WarfareSystem.advance_day` (registered `simulation_controller.gd:674-681`).
3. `world.current_day += 1`.
4. `start_of_day_systems`: `EconomySystem.process_day` (`simulation_controller.gd:682-685`).
5. On month rollover — `monthly_systems`: `CharacterSystem.process_month` + character AI, `CountryDepthSystem.process_month` + depth AI, `EconomySystem.process_month` (`simulation_controller.gd:687-701`), then `events.publish_month`.
6. On year rollover — `yearly_systems`, then `events.publish_year`.
7. `ai_hooks`: `CampaignGoalSystem.process_day` + `StrategicAISystem.process_day` (`simulation_controller.gd:705-708`).
8. `process_commands()` again — resolves AI-issued commands the same day.
9. `events.publish_date`.

This is the order the naval scheduler steps in [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#cross-system-daily-order) must be woven into; naval construction-completion / movement / interception / battle / embarkation steps slot between step 2 and step 4 (before land movement resolves, per the locked cross-system order), and blockade-to-siege contribution slots inside step 4 (`WarfareSystem` siege advancement) or immediately after it.

### Economy ledger categories

`EconomySystem._empty_ledger()` (`scripts/simulation/economy_system.gd:87`): `tax`, `production`, `subject_income`, `subject_payments`, `event_income`, `total_income`, `army_maintenance`, `fort_maintenance`, `interest`, `event_expenses`, `total_expenses`, `balance`, `province_tax` (per-province breakdown), `province_production` (per-province breakdown).

Naval maintenance/repair/construction/blockade-penalty categories (`navy_maintenance`, a blockade income/expense line, etc.) do not exist yet and must be added as new keys here, matching the existing per-category integer pattern — do not invent a parallel ledger.

### War registry fields (observed usage in `warfare_system.gd`)

Wars live in `world.war_registry` keyed by `war_id` (string). Observed fields: `war_id`, `total_war_score`, plus attacker/defender side membership and active battle references (`"attacker"` / `"defender"` side tags used on battles, e.g. `battle["winner_side"]`). War-score updates run in `_update_war_scores()` (line 416) and emit `events.war_score_changed`. Naval battle outcomes and blockade pressure will need to contribute to `total_war_score` through the same update path rather than a separate score channel.

### Character/commander rules

`CharacterSystem` / `CharacterAISystem` own character lifecycle, dynasties, titles, and claims and run monthly. Admirals (per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#characters)) are characters with an exclusive naval command assignment — this must reuse the existing character registry and its death/succession/country-change handling rather than a separate admiral roster; no separate admiral entity type exists today.

## Test runner coverage

- `tools/testing/run_all_tests.py` — orchestrator; `GODOT_TESTS` tuple runs each `.gd` test headless via Godot, matching stdout against a success marker; report written to `docs/test_reports/latest_headless_report.md`.
- Godot test files: `tests/*.gd`, `extends SceneTree`, `_initialize()` → `call_deferred("_run")`, `_require(condition, message)` assert helper (`push_error` + `quit(1)` on failure), final success-marker `print()` + `quit(0)`.
- Some checks are plain Python scripts run directly by the orchestrator (e.g. `tests/map_hydrography_topology_smoke.py`, `tests/biome_classification_smoke.py`, `tests/marker_asset_contract_smoke.py`).
- **Environment note (resolved):** this machine initially had no working `python`/`python3`/`py` on PATH (only the Windows Store alias stubs). Installed Python 3.12.10 via `winget install Python.Python.3.12` on 2026-07-17. N1.1 tooling can now follow the existing `tools/map_graph/build_province_graph.py`-style pattern. New shells pick up the PATH update automatically (winget updates the user `PATH` registry value); a shell opened before the install needs its `Path` env var re-read from the registry.

## Non-naval performance baseline

Not captured in this pass — no existing benchmark harness was found that records CPU/memory/save-size/load-time numbers outside of the general test suite pass/fail. Capturing a numeric baseline (per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#performance-principles) "measured CPU, memory, save-size, and load-time budgets") requires either an existing profiling script this survey did not find, or a new one. Recorded here as an open item rather than guessed.

## Open items carried forward

- No numeric performance baseline captured yet; needed before N0.3 budgets can be finalized.
- No content hash currently exists for `province_graph.json`; N1 must add one.
