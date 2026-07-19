# FL4 - Starting Naval Content and Leaders

**Status:** Complete. FL4.1/FL4.2/FL4.4 (content policy, fleet review, validation tooling) were already built and wired into `SimulationController` earlier in this effort; this packet re-verified that work against the roadmap's exact exit bar, closed the two real gaps found (FL4.3's admiral policy decision, and FL4.4's missing human-readable content report), and confirmed the rest.
**Satisfies:** [04_FL4_STARTING_CONTENT_AND_LEADERS.md](../04_FL4_STARTING_CONTENT_AND_LEADERS.md).

## What already existed (re-verified, not rebuilt)

- **`assets/grand_world_1444_naval_forces.json`** - five starting fleets (England Channel, France Atlantic, Portugal Atlantic, Castile Atlantic, Aragon Mediterranean), each with a full provenance block (`source`, `evidence_class`, `confidence`, `reviewer`, `review_date`, `review_status`, `note`) and `content_status: "approved_gameplay_placeholder"` at the file level - FL4.1's "reviewed, approved placeholder, generated, unknown" states are represented concretely rather than left abstract, and every row is honest that ship counts are gameplay capability fixtures, not exact 1444 historical counts.
- **`scripts/simulation/starting_naval_forces.gd`** (`class_name StartingNavalForces`) - loads and structurally validates the JSON (schema/scenario match, no duplicate/incomplete fleet IDs, every home port real/enabled, every ship a known definition, every provenance field non-empty, `review_status` in `VALID_REVIEW_STATUSES`), then `initialize_world()` creates the fleets/ships with deterministic IDs, skips countries absent from a reduced scenario ownership map without creating ghosts (the "focused synthetic fixtures" bullet), and refuses to run twice against an already-populated world (idempotency).
- **Wired into `SimulationController`** (`simulation_controller.gd:737-744`) - invalid content or a rejected row `push_error`s and aborts campaign start rather than silently continuing with a partial navy ("fail loudly on a participating country's invalid row").
- **`tests/starting_naval_forces_test.gd`** - already proved: content validity, exactly 5 fleets/22 ships, every fleet uses an owned home port, no ship double-membership, Channel-acceptance transport capacity (England ≥2000, France ≥2000, the other three ≥1000), every country's `naval_ai_controlled` runtime flag set, `content_status` recorded in `world.global_flags`, and a full save/load round trip preserving checksum plus confirming re-initialization against an already-loaded world does not duplicate the navy. Already registered in `tools/testing/run_all_tests.py`.

Re-running this test this session (clean, no hidden `SCRIPT ERROR`/`Parse Error` per this project's own established verification standard) confirmed none of the above regressed from any FL3/FL5/FL2.4 work done since it was built.

## What this packet found and closed

### FL4.3 - no admiral policy had been formalised

The JSON already carried `admiral_status: "no reviewed named naval leader assigned"` per fleet, but no document approved that as a deliberate decision with the source/reasoning/reviewer/date FL4.1 itself requires for every other release row - it read as an unaddressed gap, not a reviewed choice. Closed in [FL4_ADMIRAL_POLICY.md](FL4_ADMIRAL_POLICY.md): G1 ships with zero starting admirals by explicit decision (neither a reviewed historical-admiral content set nor an approved generated-leader formula exists yet), and every mechanical guarantee FL4.3 asks for (exclusivity, death cleanup, save compatibility) was confirmed already correct via pre-existing, general `CharacterSystem`/`AssignAdmiralCommand` machinery - no new code was needed or written.

### FL4.4 - the human-readable content report did not exist

`tools/naval/build_naval_forces_report.py` (new) reads the same JSON `starting_naval_forces.gd` validates and writes [FL4_2_STARTING_CONTENT_REPORT.md](FL4_2_STARTING_CONTENT_REPORT.md) - a table of every fleet's review status, reviewer, review date, confidence, and an explicit "Unresolved" column flagging any row missing a provenance field or carrying a `review_status` outside the same `VALID_REVIEW_STATUSES` set the GDScript validator enforces (kept in sync by comment across the Python/GDScript boundary, not by import - the two languages can't share a constant directly). Registered in `tools/testing/run_all_tests.py`'s `PYTHON_TESTS` with `--check` mode, matching every other generated-artifact script in this project (`build_country_registry.py` etc.) - a future content change that introduces an unresolved row now fails the suite rather than only being caught by manual review.

### Windows export inclusion - confirmed, not previously stated

`export_presets.cfg`'s `include_filter` already contains `assets/*.json`, a wildcard that covers `grand_world_1444_naval_forces.json` without needing a new entry - confirmed by reading the config rather than assumed. No dedicated export-specific test exercises this file by name; `tools/testing/run_all_tests.py`'s existing `export_and_start()` step covers Windows export generically for the whole project, not naval content specifically, so this is a structural verification (the filter pattern is broad enough), not an isolated regression test - stated precisely rather than overclaimed.

## Verification

- `tests/starting_naval_forces_test.gd` (pre-existing, re-run clean this session).
- `tools/naval/build_naval_forces_report.py --check` (new): exits 0 with zero unresolved rows against the current content; would exit non-zero and fail the suite if a future content change left a row unresolved.
- Full-project headless parse-check re-run clean after this packet's changes.
- `export_presets.cfg` read directly to confirm `assets/*.json` inclusion (see above).

## Deliberately out of scope for this packet

- **Reviewed named historical admirals or a generated-leader policy/formula** - see [FL4_ADMIRAL_POLICY.md](FL4_ADMIRAL_POLICY.md)'s own "deliberately out of scope" section; a real content-sourcing or game-design decision, not something to improvise here.
- **Expanding starting content beyond the five G1-required countries** - the roadmap's own FL4.2 bullet says "expand... only when required by the approved G1 content boundary"; no such expansion has been approved.
- **A dedicated Windows-export test naming this specific JSON file** - the existing wildcard filter and generic export smoke test were judged sufficient; a file-specific export test would be redundant with both.
