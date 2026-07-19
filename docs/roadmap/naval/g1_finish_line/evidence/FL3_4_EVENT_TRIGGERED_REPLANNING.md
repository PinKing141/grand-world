# FL3.4 Follow-up - Event-Triggered Replanning

**Status:** Complete. Targeted test passes (see Verification).
**Satisfies:** the remaining open half of FL3.4's "Avoid daily full replanning; use staggered schedules and event-triggered invalidation" bullet, recorded in [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md) as "Staggered per-country schedules are real and correctly implemented... Event-triggered invalidation does not exist at all... A fleet that becomes acutely endangered the day after its own TACTICAL_INTERVAL tick waits up to 5 days (minus stagger) before the AI reconsiders it."

## What shipped

`NavalAISystem` now subscribes to `naval_battle_started` and `fleet_moved` at construction time. Neither handler resolves "which country is affected" itself - that needs live world state (fleet ownership and location), which a signal handler does not receive, only `process_day(world)` does - so both handlers just queue the *zone* the event concerned into `_pending_replan_zones` (a `Dictionary`-as-set, since a busy day can report the same zone from several signals and only the distinct set matters).

`process_day()` snapshots and clears that set at the very top of each call - so a command issued mid-loop (an earlier country's own tactical order starting a new battle) cannot retroactively re-trigger countries already checked this same tick, and nothing leaks into tomorrow's otherwise-unrelated triggers. For every country not already due on its own staggered schedule, `_country_touched_by_replan_trigger()` checks whether any of that country's own fleets currently sits in one of this tick's touched zones; if so, `tactical_due` is forced true for that country this tick, and a new checksummed counter, **`naval_ai_event_replans`**, increments - making a "replan storm" (many countries triggered the same day) measurable rather than only theoretically bounded, per this packet's own explicit goal.

`fleet_moved` is queued unconditionally (friendly or hostile) rather than pre-filtered, since the real "is this actually a hostile arrival next to one of my own fleets" question can only be answered once `_country_touched_by_replan_trigger()` runs against live state anyway - pre-filtering in the handler would just duplicate that same check a second time for no benefit.

## Verification

- `tests/naval_ai_event_replan_test.gd` (new), using the real `AIDefinitions`-listed Castile fixture `tests/naval_ai_test.gd` itself uses (the synthetic ENG/BUR Channel fixture most other naval-AI tests use is *not* in the real AI country roster `process_day()`'s own loop visits, so it cannot exercise this specific code path):
  - A control case proves that on a day genuinely off Castile's own tactical schedule, with no event fired, no replan occurs at all (`naval_ai_event_replans` stays 0, nothing recorded).
  - A `fleet_moved` arrival in Castile's own zone, on that same off-schedule day, forces exactly one event-triggered replan, incrementing the counter and recording a real tactical decision on the trigger day itself - not the country's own next scheduled day.
  - A `naval_battle_started` event in Castile's own zone does the same.
  - A `fleet_moved` arrival in a zone Castile has no fleet in at all does **not** trigger a replan - the mechanism is scoped to zones a country actually has presence in, not a blanket "something happened somewhere" signal.
- `tests/naval_ai_test.gd` (pre-existing, re-run clean): its own two-instance 215-day determinism replay against the real 29-port Iberian fixture still reproduces an identical outcome and checksum - proving the new event-driven path, which fires constantly during normal fleet movement (`fleet_moved` emits on every leg), introduces no nondeterminism.
- `tests/naval_ai_trace_neutrality_test.gd` (pre-existing, re-run clean): the new `naval_ai_event_replans` counter is incremented unconditionally inside `process_day()` itself, not inside the tracing-gated `_record_decision()`/`_record_rejected_candidate()` path - confirmed to stay identical between the traced and untraced 215-day runs, same as the other three checksummed naval-AI counters.
- Every other naval-AI test file (`naval_ai_threat_test`, `naval_ai_organisation_test`, `naval_ai_transport_test`, `naval_ai_strategic_posture_test`, `naval_ai_tactical_missions_test`, `naval_ai_reinforcement_homeport_transport_test`, `naval_ai_explainability_test`, `naval_ship_technology_gate_test`, `naval_ai_player_battle_arbitration_test`, `naval_ai_recovery_matrix_test`) re-run clean - none of them drive the AI through `process_day()`'s own scheduling loop over multiple days the way this change touches, so none were expected to change, and none did.
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after every edit in this packet.

## Deliberately out of scope for this packet

- **Additional trigger signals** beyond `naval_battle_started`/`fleet_moved` (e.g. `blockade_started`, `fleet_supply_changed`) - the roadmap's own two named examples ("react to naval_battle_started, an enemy fleet's fleet_moved into a friendly zone") are exactly what this packet implements; expanding the trigger set is a real, separate, future-scoped decision about how sensitive replanning should be, not assumed here.
- **A budget or throttle on `naval_ai_event_replans` itself** - the counter makes a replan storm measurable, which is what this packet's own scope asked for; deciding whether a measured storm is *acceptable* is the still-open FL3 verification packet 4 (a measured performance budget), deliberately last per the closure audit's own recommended order.
