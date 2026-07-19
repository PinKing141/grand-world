# FL3 Verification 4/4 - Global Planning Work Is Bounded

**Status:** Complete. Targeted test passes (see Verification). This closes out the last of FL3's four "Automated verification" roadmap claims, and with it, FL3 itself.
**Satisfies:** the fourth of [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md)'s four untested "Automated verification" roadmap claims - "Global planning work is bounded and meets its measured budget," deliberately attempted last, after split/transfer (FL3.3), event-triggered replanning (FL3.4), and escort lifecycle (FL3.5) all landed and stopped changing planning cost.

## Why a synthetic 20-country roster, not the real Iberian fixture

`NavalAISystem.process_day()` only ever visits `AIDefinitions`' own real country roster. `tests/naval_ai_test.gd`'s existing 215-day fixture already proves correctness there, but its 5-country real Iberian roster is not a genuinely "global" scale to measure planning-loop overhead against. `AIDefinitions.from_data()` (already used by `phase_8_country_depth_test.gd`-style tests for malformed-data checks, reused here for a different purpose) builds a synthetic 20-country roster instead, each owning one real N0.3-reviewed fixture port from the same `FIXTURE_PORTS` list `naval_fleet_stress_smoke.gd`/`naval_battle_blockade_stress_smoke.gd` already use, spread across every schedule slot so posture/construction/organisation/tactical/transport planning all genuinely fire across the run.

## What is measured, and what is not

Only `NavalAISystem.process_day()`'s own wall-clock time is measured, not the whole scheduler tick - `FleetMovementSystem`/`NavalCombatSystem`/`BlockadeSystem`/`EconomySystem`'s own cost is already budgeted separately by the existing stress smokes. This isolates naval AI planning specifically, matching the roadmap's own "global planning work" wording.

**A real, genuine measurement, not a placeholder** - two bugs were found and fixed while building this, not assumed away:

1. **The fixture initially did no real work.** Each synthetic country started with 2 ships against a desired count of 1 (one port, peacetime multiplier), so `_plan_construction()` saw "fleet_sufficient" on its very first tick, every tick, for every country - the expensive path (family/port selection, sailor/treasury checks, command construction, validation, and application) never actually ran, and the measured time was a meaningless near-zero. Fixed by starting every country with an empty fleet, forcing genuine construction planning.
2. **The timing capture itself was broken.** The first working version wrapped `naval_ai.process_day()` in a closure appended to `scheduler.ai_hooks`, accumulating elapsed time into an outer local variable from inside that closure. GDScript captures local variables in a lambda **by value at creation time**, not by reference - the accumulator mutated inside the repeatedly-invoked closure never actually updated the outer variable in `_run()`'s own scope, so the "measured" time read back as an implausible `0.00ms` even after the first bug was fixed and real construction was happening. Caught because `0.00ms` for 20 countries' worth of real command construction and validation was itself an unbelievable number, not accepted at face value. Fixed by calling `process_day()` directly in a manual per-day loop instead of through `ai_hooks`, sidestepping the closure entirely.

## Verification

- `tests/naval_ai_performance_smoke.gd` (new): 20 synthetic AI-recognized countries, each with an empty starting fleet and one real fixture port, run for 65 simulated days. Every country is proven to have taken at least one real decision (not just been fast because it did nothing), every one of the 20 must have queued exactly one real `ConstructShipCommand` (not a bookkeeping rejection - `naval_ai_commands_submitted == 20` exactly), and every one of those must be a live `naval_construction_registry` entry (war_galley's own 150-day build time means completion itself is out of this fixture's 65-day span, matching `naval_ai_test.gd`'s own documented reasoning for needing 215 days to see a completed ship). Measured **~5.75-6.85s** across repeated runs on the development machine (a resource-constrained laptop, not representative target hardware - see this project's own documented environment notes). The budget is set to 30000ms (30s), a ~4.4x margin above the higher of those two measurements, matching this project's own established "generous conservative guard, not a tight bound" precedent (`naval_fleet_stress_smoke.gd`'s own 15s guard over a measured ~3.7s).
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after every edit in this packet.

## What this means for FL3

All four of FL3's "Automated verification" roadmap claims are now proven: same-zone player/AI battle arbitration ([FL3_VERIFICATION_1](FL3_VERIFICATION_1_BATTLE_ARBITRATION.md)), the full AI recovery matrix ([FL3_VERIFICATION_2](FL3_VERIFICATION_2_RECOVERY_MATRIX.md)), trace-neutrality ([FL3_VERIFICATION_3](FL3_VERIFICATION_3_TRACE_NEUTRALITY.md)), and this packet's global performance budget. Combined with all six FL3.1-FL3.6 sub-scopes being complete (see [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md)), FL3 itself has no remaining open item of its own.

## Deliberately out of scope for this packet

- **A certified, approved N0 numerical performance budget** - this is a conservative smoke-test guard, the same framing every other stress smoke in this project already carries; a certified release-quality target remains a separate, not-yet-approved item (see `N0_BASELINE_INVENTORY.md`).
- **Measuring on representative target hardware** - the development machine this budget was set on is explicitly resource-constrained; a hardware-validated budget is part of FL6/FL8.2's own still-open hardware-blocked work, not this packet's.
