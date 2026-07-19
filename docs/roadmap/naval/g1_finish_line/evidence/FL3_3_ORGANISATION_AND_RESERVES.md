# FL3.3 Follow-up - Split/Transfer Organisation and Reserve Fleets

**Status:** Complete for the one real, well-motivated case found. Targeted test passes (see Verification).
**Satisfies:** the remaining FL3.3 gaps [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md) recorded - "Group ships into task fleets using normal split, merge and transfer commands" (only merge was previously used) and "Keep repair and reserve fleets available."

## What was found before implementation

`SplitFleetCommand`/`TransferShipsCommand` existed and were fully functional but never called by `NavalAISystem` - only `MergeFleetsCommand` was in use (`_consider_fleet_merge()`). Rather than inventing a speculative "split for a smaller mission" use case with no concrete trigger, the actual codebase was audited for a real, already-reachable scenario split would fix:

**A mixed fleet ties down combat ships on transport voyages they contribute nothing to.** `_plan_transport()` selects a docked fleet by transport *capacity* alone (`TransportSystem.available_capacity(world, fleet_id) >= required`) - it does not care whether that fleet also contains non-transport-family ships. A fleet built from a mixed `POSTURE_SHIP_MIX_BP` construction plan (or the reviewed starting-fleet content, which is deliberately mixed by design - see [FL4_STARTING_CONTENT_AND_LEADERS.md](FL4_STARTING_CONTENT_AND_LEADERS.md)) that gets selected for a transport run sails its combat ships along for the whole voyage, unavailable for blockade, patrol, or interception duty the entire time, contributing nothing to the crossing itself.

**Reserve fleets, checked against actual behaviour rather than assumed to need new mechanism:** `EconomySystem._complete_naval_construction()` already deposits every newly-built ship into a per-port `"reserve_<port_id>_<country_tag>"` fleet (`economy_system.gd:523-527`) - this *is* the reserve-fleet concept the roadmap names, already real, just never previously called out as such. Tracing what happens to it: a solo reserve fleet with no sibling fleet at the same port is never touched by any tactical `_consider_*` function while docked (all of them require `FLEET_LOCATION_AT_SEA` except `_consider_repair_or_return()`, which only acts on a damaged or unsupplied fleet - a fresh reserve fleet is neither), so it is never accidentally deployed into risk. It graduates into active service exactly when `_consider_fleet_merge()` finds a sibling fleet at the same port to consolidate with, or once it accumulates enough ships for `_plan_organisation()`'s own admiral-assignment loop to notice it. **No new mechanism was needed** - "keep reserve fleets available" is already true by construction, confirmed by tracing every code path that could touch a docked fleet, not assumed.

## What shipped

`_consider_transport_ship_separation()`, slotted into `_plan_organisation()` right after fleet merging: for a docked, organisable fleet that mixes `"transport"`-family ships with any other family, while the country has a live overseas objective genuinely needing sea transport (`_overseas_objective_landing()` - the same query `_review_posture()`'s invasion detection and `_plan_transport()` itself already share, so this never splits speculatively when nothing is waiting to sail), the non-transport ships are split off via `SplitFleetCommand` - freeing them for combat duty and leaving a transport-only fleet `_plan_transport()` can then select cleanly.

Deliberately multi-tick by design: the split lands this tick, and `_plan_transport()` picks up the now-pure fleet on its own next due tick, the same "a command takes effect over subsequent ticks" pattern construction and movement already use elsewhere in this file - a same-tick split-then-transport pair would validate the transport half against the fleet's pre-split composition, which `_submit()`'s own queued-not-immediate command model does not support within one call.

`TransferShipsCommand` remains unused by the AI - no real, concrete trigger for it was found (it only matters when moving ships between two *already-existing* fleets at the same port without creating a new one, a narrower case than either merge or this new split already cover) - honestly left unattempted rather than invented a use for it.

## Verification

- `tests/naval_ai_organisation_test.gd` (extended, three new cases): a mixed galley+transport fleet with a live overseas objective is split into exactly two fleets, the original left holding only the transport-family ship and the new fleet holding only the non-transport one; a control proves no split occurs without a live overseas objective; a second control proves an already-pure transport fleet is never split (nothing to separate).
- `tests/naval_ai_test.gd` (pre-existing, re-run clean): its own two-instance 215-day determinism replay against the real Iberian fixture still reproduces an identical outcome and checksum.
- `tests/naval_ai_transport_test.gd`, `tests/naval_ai_reinforcement_homeport_transport_test.gd`, `tests/naval_ai_event_replan_test.gd`, `tests/naval_destructive_edge_gate_test.gd` (pre-existing, re-run clean) - confirming the new organisation step does not disturb transport planning, reinforcement, event-triggered replanning, or the broader destructive lifecycle matrix.
- Full-project headless parse-check re-run clean after every edit in this packet.

## Deliberately out of scope for this packet

- **`TransferShipsCommand`** - no concrete, well-motivated trigger found; not invented for its own sake.
- **A generalised "split for any smaller mission" mechanism** - the roadmap's own "avoid splitting below mission viability" bullet implies splitting has a real trigger already in mind; the one found and built here (freeing combat ships before a transport voyage) is that trigger, not a speculative general-purpose splitter.
- **FL3.5's escort lifecycle** (proactive reservation, escort-follows-the-voyage) - its own separate, still-open packet.
