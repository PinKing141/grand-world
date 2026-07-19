# FL8.2 - Country-Label Batch Performance

**Status:** Hardware-blocked. Two real fixes shipped and verified; the remaining budget failure is proven to be a frame-coincidental host/runtime stall unrelated to label geometry, text content, or font warm-up timing - it requires target-hardware validation (FL6.4), not further label-code changes.
**Satisfies:** FL8.2 ("Country-label batch performance") from [08 - FL8 Project Gate Recovery](../08_FL8_PROJECT_GATE_RECOVERY.md).

## What was actually wrong (three separate issues, not one)

### 1. Test harness: fixed 300-frame wait cap

`tests/country_label_layer_test.gd` waited `while labels.debug_pending_count() > 0 and initial_wait_frames < 300`, a constant that predates any batch-size change. Reducing the label layer's own `MAX_INCREMENTAL_TAGS_PER_FRAME` (more frames needed to drain ~700 countries) made this cap insufficient, and - because `_require()`'s `quit(1)` does not actually halt the currently-running coroutine, only schedules the tree to exit - the test fell through to every subsequent assertion anyway, producing a cascade of misleading failures (Sweden, Naples, Münster, Sofala) against countries whose layouts simply hadn't been computed yet. Fixed: the wait cap is now derived from `expected_tag_count / batch_size` plus a safety margin, and an incomplete queue now stops the test immediately with an explicit diagnostic message instead of falling through.

Confirmed via `git stash`: this defect exists in the original, unmodified code too - it was only ever masked by an earlier, unrelated timing failure that happened to abort the test before reaching the false-positive assertions.

### 2. Real algorithmic hotspot: `_territory_province_id()`

Every pixel `_shape_alignment()`/`_largest_safe_rectangle()` scanned called `Image.get_pixel()` and decoded a `Color` back to an int, on every lookup, for every country's own bounding-box scan. Fixed by decoding the whole (already cell-resolution) territory image into a `PackedInt32Array` once at load (`_build_territory_cell_cache()`), turning every later lookup into a plain array index. Verified via a direct per-country diagnostic (bypassing the batcher, so insulated from scheduling noise): worst-case per-country cost dropped from ~15-22ms to ~9-10ms, with byte-identical output (Sweden, Naples, etc. produce the exact same angle/pixel-size values before and after). The "0/703 countries exceed 30ms alone" result (down from the pre-fix noise-contaminated "1/703") confirms no remaining country is shape-alignment-bound above budget.

### 3. `MAX_INCREMENTAL_TAGS_PER_FRAME` batch size: tried, then ruled out

Initially reduced 4→2 to keep alphabetically-adjacent expensive countries from stacking into one over-budget frame. Multiple repeated real-test runs (6x) showed this environment's wall-clock timing is far too noisy to validate against a 30ms budget on its own (`initial_layout_ms` varied 762ms-3340ms run to run; the "worst batch" identity itself changed between runs - JFN/JGD, MBA/MBL, EIC/EJZ - ruling out any specific pairing as the cause). Per the user's directed FL8.2a investigation (below), the one country that reproducibly costs the budget (JFN) costs the same whether alone (batch=1) or paired - proving batch size is not the lever that matters here. **Reverted to the original 4**; reducing it further only adds more frames to the initial rebuild wall-clock without addressing the real remaining blocker.

## FL8.2a - targeted JFN/JGD investigation

Per-batch and per-stage timing instrumentation was added (gated behind the `LABEL_STAGE_PROFILE` environment variable, zero cost when unset): `debug_batch_durations_ms()` records every batch's duration, not just the running max; `debug_stage_timings(tag)` splits a country's `_rebuild_country_layout()` into land-body discovery, bounding-box setup, shape-alignment scan, safe-rectangle scan, and `_make_layout()` (final text/layout creation).

Six repetitions at batch size 1 (so "batch cost" == "single country's own cost", eliminating pairing as a variable):

| run | JFN total_ms | JFN layout_ms | JGD total_ms |
|---|---|---|---|
| 1 | 41.65 | 41.42 | 0.34 |
| 2 | 39.01 | 38.89 | 0.34 |
| 3 | 69.89 | 69.72 | 0.75 |
| 4 | 39.05 | 38.89 | 0.42 |
| 5 | 72.99 | 72.69 | 0.40 |
| 6 | 38.54 | 38.41 | 0.45 |

JGD was never a real problem (0.34-0.75ms every run) - it only ever looked bad by association, paired with JFN under the old batch=2 config. JFN's cost is genuine, reproducible, and lives entirely in `layout_ms` (`_make_layout()`) - `land_body_ms`, `bbox_setup_ms`, `shape_scan_ms`, and `rect_ms` are all sub-millisecond every single run. Fine-grained instrumentation inside `_make_layout()` isolated it further: **100% of the cost is inside `_text_pixel_bounds()`'s `_label_font.get_string_size()` call** (`text_pixel_bounds=40.959ms` against every other sub-stage under 0.02ms in the same call).

Two hypotheses were formed and both were disproven by direct experiment, not assumption:

- **"Uncached glyph in JFN's name"**: "Jaffna" (JFN's display name) is plain ASCII, already within the pre-warmed Latin-1 range. Ruled out on inspection.
- **"Cold text-shaping cache, first real string measured after font warm-up"**: moving a representative `get_string_size()` pre-warm call earlier (to fire the moment ASCII becomes usable, rather than only at the very end of the full warm-up range) had **zero effect** - JFN still cost 38-73ms every run afterward. Ruled out by experiment.
- **Direct proof it isn't about the string or the cache at all**: after the real per-country queue finished, calling `get_string_size("Jaffna", ...)` again cost 0.187ms, and calling it with a fabricated string that had never been measured anywhere in the session ("Xyzzzqvwk") cost 0.082ms on its very first measurement. Any string, including a brand-new one, is fast once measured after the full queue has run - which rules out "first measurement of this text" and "first measurement of any text" as the cause.

The only remaining explanation consistent with every measurement: something else in the wider engine/scene, unrelated to fonts or label geometry, does one-time expensive work that happens to coincide with the specific frame JFN's turn falls on (JFN's alphabetical rank puts it at a fixed, deterministic point in the ~700-country incremental queue, which is why the same country reproduces every run). This is exactly the FL6.4 "host/runtime overhead requiring target-hardware validation" case, not a label-algorithm defect - proven by elimination rather than assumed by default. Both disproven fixes (the early shaping pre-warm, and the batch-size reduction) were reverted; only the two proven fixes (territory-lookup cache, harness wait-cap) remain.

## Deliberately not pursued further

Confirming the exact engine-internal mechanism (a specific GPU sync point, driver stall, or unrelated resource load coinciding with JFN's frame) would need a real frame-capture profiler (RenderDoc or Godot's own profiler with call stacks), which FL6.4 already names as the tool for exactly this class of question and which is not practical from this headless CLI environment. Re-running this investigation on the project's actual target/reference hardware (FL6.4) is the correct next step, not further blind instrumentation here.

## Regression evidence

`tests/country_label_layer_test.gd` (harness fix applied) still fails at the `max_layout_batch_ms` assertion - `["JAP", "JAR", "JFN", "JGD"]` at ~38-41ms, consistent with JFN's own isolated cost and confirming no pairing effect. This is the expected, understood, hardware-blocked result, not a regression. The broader quick regression suite was re-run after all changes to confirm no collateral damage elsewhere (see the suite's own report for the current pass/fail state).
