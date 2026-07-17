# N5.1 - Blockade Eligibility and Power (partial)

**Status:** Recorded for eligibility and effective power only. Target resistance, full contested-zone rules, reverse indexes/threshold events, and every downstream N5.2 item (siege, economy, war score, trade hook) are explicitly open.  
**Satisfies:** the eligibility/effective-power portion of [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N5.1, and the N5A work packet in [05 - N5 Strategic Effects](../05_N5_STRATEGIC_EFFECTS.md)  
**Scope:** a pure query layer answering "which fleets can blockade, how much power do they contribute, and which provinces does that affect right now" - and the one new command (`SetFleetMissionCommand`) needed to make "mission permits blockade" a real, settable fact rather than an unreachable condition. No persistent blockade state, no war score, no economy/siege effects, no events.

## Why this is a query layer, not a registry

Every other naval system this roadmap has built so far - fleets, ships, naval construction, transport operations, naval battles - is a persistent registry with reverse indexes, because each of those is a *thing with a lifecycle* (created, mutated over days, eventually completed or destroyed). A blockade is different: 05_N5 says outright that it "is calculated from fleet/zone/target state, not written directly by UI." There is no blockade *object* to create - only a fact that is true or false, and a power value, computed fresh from whatever fleets currently exist and where they are. `BlockadeSystem` is therefore a set of static query functions with no stored state at all, following the same "scan and filter current state" shape `CampaignWorldState.armies_in_province()`/`country_fleets()` already use, rather than a `blockade_registry` that would need to be kept in sync with fleet movement, mission changes, and combat outcomes on every tick.

This has a direct consequence for what's *not* built yet: "Province blockade level changed across meaningful thresholds" (05_N5 "Events and Queries") needs a *previous* value to compare against to detect a threshold crossing - which needs something to persist that previous value somewhere. A pure query has nothing to compare against. Threshold events, war blockade score accumulation, and reverse indexes for "which provinces does country X currently have blockaded" are consequently N5.2's job, once there is a persistent value for them to attach to.

## Architectural choices

**`fleet.mission` is used for the first time since it entered the schema in N2.1.** The field has always existed (`make_fleet_record()`'s default `"idle"`), but nothing before this slice ever read or wrote it - move orders, transport, combat, and repair all operate independently of mission. 05_N5 is the first roadmap section to actually gate behaviour on it ("Its mission permits blockade"), so this slice adds the minimum needed to make that gate real: `SetFleetMissionCommand`, restricted to `["idle", "blockade"]` for now. The many other missions 05_N5 and later pillars imply (patrol, intercept, protect, avoid, return-to-port, repair) are not modeled - only the one this slice's eligibility check actually needs.

**Eligibility treats "in active battle" as a hard exclusion, not a partial-power contest.** 05_N5's "Contested Zones" describes a richer rule ("An active naval battle pauses/contests power according to one explicit rule... Multiple friendly fleets combine... with any diminishing-return/cap rule applied once"). This slice's simplification: a fleet with a non-empty `battle_id` is simply ineligible, full stop, until the battle resolves. This is defensible as a *specific instance* of "pauses... power" (the simplest one - a paused contribution is zero, not partial), but it is not the full contested-zone model 05_N5 eventually wants, particularly around *opposing* fleets in the same zone reducing (not merely pausing) a blockade.

**Damage scaling reuses `NavalCombatSystem`'s own shape rather than inventing a second damage-effectiveness formula.** A fleet's blockade contribution scales by its aggregate hull ratio, and drops to zero entirely below the same kind of binary threshold `TransportSystem.DAMAGED_CAPACITY_THRESHOLD_BP` already established for transport capacity - two different systems (transport capacity, blockade power) independently arrived at "a damaged unit either contributes proportionally or not at all below a floor," and this slice reuses that precedent rather than picking new, unrelated numbers.

**Combination across multiple fleets is a plain sum, clamped to `[0, 10000]` - not the diminishing-return rule 05_N5 mentions as a possibility.** "The result is an integer blockade basis-point value... clamped" is satisfied; "any diminishing-return/cap rule applied once" is not attempted, consistent with this being the simplest formula that is genuinely explicit, matching the "simple explainable formula first" precedent every N2/N3/N4 first slice has already established.

## What was built

- `scripts/simulation/commands/set_fleet_mission_command.gd` (new): validates ownership and that the fleet isn't in battle/retreating, restricted to a two-value `VALID_MISSIONS` list for this slice.
- `scripts/simulation/blockade_system.gd` (new): `is_fleet_eligible()`, `effective_power()`, `blockaded_provinces_for_fleet()`, `province_blockade_bp()`, `all_blockaded_provinces()`.
- One new `SimulationEventBus` signal: `fleet_mission_changed`.
- `simulation_controller.gd`: `set_fleet_mission()` wrapper method.
- `tests/naval_blockade_test.gd`, registered in `tools/testing/run_all_tests.py`.

## Results (verified via `naval_blockade_test.gd`, exit 0, no errors)

- `SetFleetMissionCommand` rejects an unknown mission name and a country that doesn't own the fleet; a legal change reaches `WorldState`.
- Eligibility correctly requires all four conditions independently: at-sea (not docked), blockade mission (not idle), supplied, and (implicitly, via zero effective power) undamaged enough - flipping any one of the first three to a disqualifying value makes an otherwise-eligible fleet ineligible.
- Effective power equals the fleet's full aggregate `total_blockade_power` when undamaged, and exactly zero once hull drops below the damage-effectiveness threshold - no partial credit below the floor.
- `blockaded_provinces_for_fleet()` correctly finds Picardie (Burgundy's, hostile, coastal, adjacent to the Straits of Dover) while excluding England's own Calais and Kent, even though all three are `land_neighbors` of the same sea zone.
- Two eligible fleets at the same location combine their power (3 + 2 = 5); a third fleet left on the default "idle" mission does not contribute even though it is otherwise co-located and hostile.
- A friendly province never shows a blockade value; with no active war at all, an otherwise-eligible fleet contributes nothing.
- `all_blockaded_provinces()` returns exactly the provinces under blockade world-wide, never a friendly one.
- No regression: re-ran all 42 Godot phase/core/naval tests after this round's changes - 41/42 pass, the one failure being the same pre-existing `country_label_layer_test.gd` frame-timing flake recorded in every N2/N3/N4 evidence doc so far.

## Deliberately simple / deferred

- **No target resistance term.** `province_blockade_bp()` only sums attacker-side power; 05_N5's resistance model (coastal development, harbour/fort/shipyard level, defending fleet presence, country/technology/building modifiers, occupation state) is not subtracted or applied at all yet - the current output is closer to "attacking power present" than "net blockade achieved."
- **No full contested-zone model.** Opposing eligible fleets do not yet reduce each other's contribution; only "in active battle" is excluded, not "hostile fleets present but not yet fighting."
- **No reverse indexes, no threshold events, no war blockade score, no economy ledger effect, no coastal siege contribution, no port-status/repair/construction effects, no trade-protection hook, no AI valuation, no UI/map feedback.** All of 05_N5's N5B through N5E work packets remain entirely open - this slice is only the eligibility/power query N5A work packet, and even that only partially (target resistance and the fuller contested-zone rule are its own remaining gaps).
- **No naval-blockade-scale stress/performance test.** `province_blockade_bp()`/`all_blockaded_provinces()` are O(fleets) scans with no caching; 05_N5's "Full-coast calculation meets approved budget without all-country/all-zone scans" required test has not been attempted.
