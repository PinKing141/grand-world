# FL3.2 - Strategic Posture and Force Plan

**Status:** Complete except technology gating (genuinely absent from the simulation layer, not this system's job - see below). Targeted tests pass (see Verification).
**Satisfies:** the FL3.2 findings recorded in [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md), consuming FL3.1's `NavalThreatMap`.

## Posture: all six, not two

`_review_posture()` now classifies `peace`, `threatened`, `wartime`, `invasion`, `recovery`, or `expansion`, mirroring `StrategicAISystem._review_strategy()`'s own precedence-chain *shape* (most urgent category wins, checked in a fixed order) rather than copying its four category names verbatim - land AI's own `peaceful`/`defensive`/`offensive`/`recovering` set doesn't map one-to-one onto the roadmap's naval-specific six. Precedence, most urgent first:

1. **invasion** - at war, and a live overseas land-AI objective needs sea transport to reach (`_overseas_objective_landing()`).
2. **wartime** - at war, no such objective.
3. **recovery** - debt or a negative ledger balance, regardless of war - matches land AI's own "debt overrides ambition" rule.
4. **threatened** - not at war, but a rival country's fleet is staged near an owned port.
5. **expansion** - treasury comfortably above (2x) the construction reserve, no war, no debt.
6. **peace** - the default.

**A real design problem found and fixed while building "threatened," not assumed away**: the natural first attempt reused `NavalThreatMap`'s own `hostile_power`/`threat_score`, but those are deliberately gated on an *active war* (correct for the tactical evade/retreat decisions they back - a fleet you are not at war with cannot attack you, so counting it as tactical danger would be wrong). That gate makes "threatened via hostile_power" structurally unreachable: any country with nonzero hostile_power is, by definition, already at war, and the `invasion`/`wartime` branches above already claim that case first. `_country_rival_power()` uses `DiplomacySystemScript`'s own existing `rivalry` relation field instead - a real pre-war tension signal that needs no war declared on either side. This is also the honest reason the simulation currently has *no* concept of "danger before a war starts" anywhere else either (blockades, battles, and hostile-power queries are all war-gated project-wide) - rivalry was already there to use, not invented for this.

`desired_ship_count` still scales with `_country_ports().size()`, now also with posture: frozen at the peacetime `x1` multiplier during `recovery` (don't grow the navy while broke), doubled everywhere ambitious (`wartime`, `invasion`, `threatened`, `expansion`).

## Force mix: a real heavy/light/galley/transport split

`POSTURE_SHIP_MIX_BP` gives each posture a basis-point target mix across the four ship families (every row sums to 10000bp) - a first-slice combination, not an approved N0/N6 budget, the same caveat every other placeholder table in this pillar carries:

| Posture | heavy | light | galley | transport |
|---|---|---|---|---|
| peace | 1000 | 2000 | 6000 | 1000 |
| expansion | 1500 | 2000 | 5500 | 1000 |
| threatened | 3500 | 1500 | 4000 | 1000 |
| wartime | 4500 | 1500 | 3000 | 1000 |
| invasion | 3500 | 1000 | 2000 | 3500 |
| recovery | 1000 | 1000 | 6000 | 2000 |

`_plan_construction()` compares each family's target count (`mix[family] * desired_ship_count / 10000`) against what the country already owns or has queued (`FleetSystem.class_counts_for_ships()` for owned, a per-family scan of `naval_construction_registry` for pending), and builds toward whichever family has the largest deficit - ties broken by `ShipDefinitions.ship_families()`'s own fixed order for determinism. Within the chosen family, it always picks the *cheapest* eligible ship (`_cheapest_ship_in_family()`) - the AI prefers affordability within a family over capability, matching its existing conservative treasury-reserve philosophy rather than reaching for "the best ship" and risking the reserve.

## Reserve inputs: treasury, sailors, port capacity, land-war needs - not technology

- **Treasury**: unchanged reserve formula, now shared via `_construction_reserve()` between posture classification and construction (previously only `_plan_construction()` computed it).
- **Sailors**: now checked *proactively*, before submitting the command - previously only `ConstructShipCommand.validate()` caught an unaffordable sailor cost, silently, after the fact. `_plan_construction()` now records an explicit `insufficient_sailors` decision.
- **Port capacity**: already respected before this packet (`desired_ship_count` scales with port count; one eligible free port is required per construction) - confirmed still true, not re-built.
- **Land-war needs**: respected by *sharing the exact same ledger-based reserve formula* land AI's own `_plan_economy()` uses, not by inventing a new cross-system arbitration mechanism - naval construction never competes past what land AI would also consider affordable, because it's the same number.
- **Technology**: **not respected, because it does not exist in the simulation yet.** `ConstructShipCommand.validate()` itself never checks a ship's `required_technology` field (`track`/`level`) - only its date-based `unlock_date`. This is a genuine simulation-layer gap discovered while auditing this bullet, not something naval AI is uniquely failing to honour; fixing it would mean adding tech-gating to `ConstructShipCommand` itself, out of scope for an AI-planning packet.

## Verification

- `tests/naval_ai_strategic_posture_test.gd` (new): all six postures reached from a hand-built Channel fixture with precise control over war/debt/rivalry/objective state independently of each other (including the negative-ledger-balance-without-formal-debt case, and the "war beats debt" precedence check); the `POSTURE_SHIP_MIX_BP` table's own internal correctness (every row sums to 10000bp, `invasion` weights transport higher than `peace`); a real construction from an empty fleet under `wartime` actually building a `heavy` ship (the unambiguous highest-weighted family); and the proactive sailor-reserve rejection, explicitly recorded as `insufficient_sailors`.
- `tests/naval_ai_test.gd` (pre-existing, one line updated): the recognised-posture assertion now accepts all six names instead of the old two; re-run clean, including its own two-instance 215-day determinism replay against the real Iberian fixture.
- `tests/naval_ai_threat_test.gd`, `tests/naval_ai_organisation_test.gd`, `tests/naval_ai_transport_test.gd`, `tests/naval_threat_map_test.gd` (pre-existing, unmodified): all re-run clean.
- Registered in `tools/testing/run_all_tests.py`.

## Deliberately out of scope for this packet

- **Technology gating** - see above; a `ConstructShipCommand`/simulation-layer gap, not this packet's to fix.
- **Cooldowns/stable construction slots beyond `CONSTRUCTION_INTERVAL`** - confirmed unchanged from before this packet; the existing spacing was already judged "defensible in effect" by the closure audit and this packet's own scope was posture and mix, not queue-spam mechanics.
- **Maintenance** - land AI adjusts army maintenance via `SetArmyMaintenanceCommand` reactively to war posture; no naval-specific maintenance command exists to mirror it with, and inventing one is a larger, separate surface area than this packet's own scope.
