# FL3 Verification 3/4 - Trace Production Does Not Change Authoritative Results

**Status:** Complete. Targeted test passes (see Verification).
**Satisfies:** the third of [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md)'s four untested "Automated verification" roadmap claims - "Confirm trace production does not change authoritative results."

## Why this was previously untestable, not just untested

The closure audit's own FL3.6 finding: "recording is unconditional, not gated behind a flag... 'very likely' true by construction - but 'very likely' is not the same as verified, and there is no flag to even express 'tracing off' if it ever needed testing." Proving "with tracing vs without tracing, results are identical" requires an actual "without tracing" state to compare against, which did not exist. This packet built that switch specifically to make the claim checkable, not as a feature anyone asked for on its own.

## What shipped

A `world.global_flags["naval_ai_tracing_enabled"]` toggle (default `true` when absent, so every existing caller - every test in this project, every real campaign - is completely unaffected), read once at the top of `_record_decision()`/`_record_rejected_candidate()`:

- **Gated on the flag** (trace content, skipped when disabled): `last_decision`, `decision_history`, `decision_counts`, `rejected_candidates`.
- **Never gated** (checksummed `world.global_counters`, always incremented): `naval_ai_decisions`, `naval_ai_commands_submitted`, `naval_ai_candidates_evaluated`. These are the roadmap's own separate "Add counters for countries planned, candidates evaluated, cache rebuilds and elapsed time" bullet - authoritative deterministic tallies the game itself may reasonably depend on existing consistently, not trace content a debug view happens to also read. Keeping them unconditional and proving they stay identical either way is itself part of what this packet verifies, not an oversight.

## Verification

`tests/naval_ai_trace_neutrality_test.gd` (new) reuses `tests/naval_ai_test.gd`'s own real 29-port Iberian fixture and 215-day simulated span verbatim - the same rigor that test's two-instance determinism replay already established - but varies the tracing flag between the two instances instead of nothing at all:

- Both instances run the identical seed (`14441111`) for 215 real days.
- The three checksummed counters are proven to have actually incremented (not a vacuously-true zero-vs-zero comparison) and to be **exactly equal** between the traced and untraced runs.
- The toggle is proven to be a genuine switch, not a no-op: every maritime country has a real, non-empty `decision_history` in the traced run and a genuinely empty one in the untraced run (same for `rejected_candidates`).
- A "gameplay fingerprint" - every fleet, ship, naval construction order, transport operation, naval battle, war record, blockaded-province entry, and each maritime country's own runtime state (with its `naval_ai` trace sub-dictionary explicitly stripped first, the one place a difference is expected) - is built for both worlds using `CampaignWorldState._canonical_variant()`, the exact same deterministic, sorted canonicalisation `checksum()` itself uses, and proven **byte-identical** between the traced and untraced runs. A full `world.checksum()` comparison was deliberately not used for this final check, since `checksum()` also includes `global_flags` (which necessarily differs by design - one world has the toggle set, one doesn't) and each country's full runtime including `naval_ai` (which is expected and correct to differ) - the fingerprint isolates exactly the claim being tested from the parts intentionally varied to test it.
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after the toggle was added.

## Deliberately out of scope for this packet

- **A UI or command-level way to toggle tracing during a real campaign** - the flag exists purely to make this verification claim checkable; no player, AI, or command path sets it, and none is expected to.
- **Verification packet 4** (a measured performance budget) - its own tracked packet, deliberately last per the closure audit's own recommended order (after split/transfer, event-triggered replanning, and escort behaviour stop changing planning cost, so the measurement is not immediately stale).
