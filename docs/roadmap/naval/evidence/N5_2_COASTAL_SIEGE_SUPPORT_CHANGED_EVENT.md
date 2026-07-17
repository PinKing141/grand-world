# N5.2 - Coastal Siege Support Changed Event

**Status:** Recorded. "Province blockade level changed across meaningful thresholds" remains the one still-open item from 05_N5's "Events and Queries" list. Peace lifecycle and the trade-protection hook remain open.
**Satisfies:** the coastal-siege-support-changed portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N5.2, and another item of [05 - N5 Strategic Effects](../05_N5_STRATEGIC_EFFECTS.md) "Events and Queries"
**Scope:** one new field on each siege record (`blockade_assisted`) and one new event (`coastal_siege_support_changed`), emitted by `WarfareSystem._advance_sieges_and_occupations()` when a siege's blockade-assist state flips. No new persisted registry, no schema bump.

## Why this needed no schema bump, unlike the blockade started/ended events

The blockade started/ended events (an earlier N5.1 round) needed a brand-new persisted field (`CampaignWorldState.blockaded_provinces`) and a schema bump, because nothing existing tracked "was this province blockaded yesterday." Coastal siege support is different: a siege already has its own per-siege record (`war["sieges"][province_id]`), created and updated daily by `_advance_sieges_and_occupations()`, which already computes `siege_assist_bp(...) > 0` every day to decide the progress bonus. Adding one more field to that already-existing, already-daily-updated dictionary - `blockade_assisted: bool` - is the same additive, backward-compatible pattern every other war-record field addition this session has used (`blockade_score_attacker` itself needed no schema bump for the identical reason). No new registry, no new save-schema version.

## Architectural choices

**The transition check reuses the exact boolean the progress-bonus decision already computes, rather than querying `siege_assist_bp()` a second time.** `_advance_sieges_and_occupations()` was already calling `BlockadeSystemScript.siege_assist_bp(world, besieger_side_countries, province_id) > 0` to decide whether to apply the daily-progress multiplier. This round stores that same boolean in a local `assisted` variable, uses it for both the multiplier decision and the transition comparison, and only then writes it into the siege record - one query, two consumers, not two queries.

**The event fires per-siege, not per-province-independent-of-a-siege.** Coastal siege support is meaningless without an active siege to support - unlike blockade started/ended (which is about a province in isolation) or port fully blockaded/unblocked (about a port in isolation), "siege support changed" only exists in the context of `_advance_sieges_and_occupations()`'s own per-siege loop, where a siege record already exists to attach the flag to. This is why the field lives on the siege record itself rather than in a new world-level dictionary parallel to `blockaded_provinces`.

**A freshly created siege's default `blockade_assisted: false` cannot itself cause a false "changed" event on day one.** The literal default dict `sieges.get(key, {..., "blockade_assisted": false})` already carries `false`, matching whatever `assisted` would be if there truly is no blockade yet - so a brand-new, unassisted siege correctly reports no transition on its first day. Only when a *pre-existing* siege's assist state genuinely differs from its own stored flag does the event fire, verified explicitly in this round's test (a siege created without an active blockade fires nothing on creation, then fires exactly once when a blockade later starts assisting it, and again exactly once when that blockade is later released).

## What was built

- `scripts/simulation/simulation_event_bus.gd`: `coastal_siege_support_changed(war_id: String, province_id: int, assisted: bool)`.
- `scripts/simulation/warfare_system.gd`: siege records gain a `blockade_assisted` field (defaulted `false` on creation); `_advance_sieges_and_occupations()` computes `assisted` once, compares it against the stored flag, emits the event on a mismatch, then updates the stored flag - all before the existing progress-bonus and weekly-random-roll logic that already used the same boolean.
- `tests/naval_blockade_test.gd`: extended (no new file) with a section proving the three-state sequence - no event on creation of an unassisted siege; exactly one event (`assisted=true`) the day a blockade starts assisting it; no repeat event on an unchanged following day; exactly one event (`assisted=false`) the day that blockade is released.

## Results (verified via `naval_blockade_test.gd`, exit 0, no errors)

- A siege that begins with no blockade present fires no `coastal_siege_support_changed` event on its creation day.
- The day an above-threshold, on-side blockade first assists an already-active siege, exactly one event fires with `assisted=true`.
- A following day with the same assist state active fires no additional event.
- The day the assisting fleet is reassigned off the blockade mission, exactly one event fires with `assisted=false`.
- No regression: re-ran all 42 Godot phase/core/naval tests after this round's changes - 41/42 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4/N5 evidence doc so far. `phase_5_warfare_test.gd`'s own full battle-to-siege-to-occupation loop passes unaffected, confirming the new field/event addition is a no-op for any siege that never encounters a naval blockade.

## Deliberately simple / deferred

- **No "province blockade level changed across meaningful thresholds" event.** *(Built in a later round - see [N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md](N5_1_BLOCKADE_LEVEL_CHANGED_EVENT.md).)*
- **No garrison-recovery or resupply-penalty equivalent event**, consistent with those two effects never having been built (see `N5_2_COASTAL_SIEGE_ASSIST.md`) - there is nothing else about siege state for a blockade to change and signal.
- **No naval-blockade-scale stress/performance test.** This change adds no new queries beyond what `_advance_sieges_and_occupations()` already performed - no new performance concern introduced, but the underlying deferred item remains open regardless.
