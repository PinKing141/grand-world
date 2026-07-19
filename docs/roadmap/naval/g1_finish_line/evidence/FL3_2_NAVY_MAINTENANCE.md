# FL3.2 Closure - Navy Maintenance

**Status:** Complete. Targeted tests pass (see Verification). This closes the last remaining FL3.2 bullet and, with it, FL3 in full.
**Satisfies:** the "respect... maintenance..." clause of FL3.2's own scope bullet, the one item [FL3_CLOSURE_AUDIT.md](FL3_CLOSURE_AUDIT.md) had left genuinely open after every other FL3.1-FL3.6 gap and all four "Automated verification" claims were closed.

## The gap was deeper than "no command exists," and the first read of it was wrong

The closure audit's own earlier note said "no naval-specific maintenance command exists to mirror land AI's `SetArmyMaintenanceCommand` with." Investigating that literally, a per-fleet field called `maintenance_posture_bp` was found - read twice in `naval_combat_system.gd`, both times as a pure combat-readiness/power penalty, never connected to any economic cost anywhere. That looked like confirmation: a half-built mechanic (a penalty with no command to set it and no cost-saving upside to ever want to).

**That reading was corrected before building anything, not after**: checking how land's own `army_maintenance_bp` actually works (`economy_system.gd:236`, scaling the `army_maintenance` ledger line) revealed a *second*, separate, country-wide field already existed for navy - `navy_maintenance_bp` - already defaulted in `country_runtime`, and **already fully wired into the `navy_maintenance` ledger line** (`economy_system.gd:253,322-327`) exactly mirroring `army_maintenance_bp`'s own shape. The economic connection was never missing. Only a command to actually change it, and AI logic to use it, were.

`maintenance_posture_bp` (the per-fleet combat field) turned out to be a genuinely separate, distinct, still-unaddressed concept - confirmed, not assumed, by checking that land's own `army_maintenance_bp` has *no* combat-power connection anywhere either (`grep`-confirmed against `warfare_system.gd`: zero hits). It is not what "respect... maintenance..." refers to, and remains its own explicitly out-of-scope item.

## What shipped

- **`SetNavyMaintenanceCommand`** (`scripts/simulation/commands/set_navy_maintenance_command.gd`) - a direct mirror of `SetArmyMaintenanceCommand`: the same four discrete tiers (25/50/75/100%), the same ownership/range validation, the same `recalculate_country()` call, a dedicated `navy_maintenance_changed` event (not reusing `maintenance_changed`, which carries no way to distinguish army from navy in its own signature).
- **`NavalAISystem._consider_navy_maintenance()`** - a direct mirror of `StrategicAISystem._plan_economy()`'s own army-maintenance adjustment, reusing the identical shared `AIDefinitions` profile field (`peace_maintenance_bp`) rather than inventing a second, naval-only one: full maintenance during any war, the profile's peacetime rate otherwise, submitted only when it would actually change the current value. Called from `_review_posture()`, the same tick land AI's own equivalent logic runs from.
- **A real ordering decision, found and fixed while building this**: `_consider_navy_maintenance()` is called *before* `_review_posture()`'s own `review_posture` decision is recorded, not after - so `debug_snapshot()`'s `last_decision` always reflects the posture review itself (the country's primary, always-present per-tick summary), not silently overwritten by a conditional secondary maintenance action. Caught by an existing test (`naval_ai_explainability_test.gd`) that asserted on `last_decision`'s own structured fields immediately after calling `_review_posture()` - the maintenance-first ordering keeps that assertion meaningful without weakening it.

## Verification

- `tests/naval_economy_test.gd` (extended): `SetNavyMaintenanceCommand` rejects an off-tier value and accepts a valid one; reducing maintenance to 25% scales `navy_maintenance` proportionally (200 -> 50 for the fixture's one transport cog); restoring to 100% restores the full cost; `navy_maintenance_bp` itself is confirmed to reflect the change.
- `tests/naval_ai_explainability_test.gd` (fixed, not just re-run): the fixture now pre-sets `navy_maintenance_bp` to the peacetime rate `_review_posture()` would itself choose, so its own new maintenance step finds nothing to change - keeping this test's own "pure bookkeeping decision" case isolated, since a real command firing there would legitimately (and correctly) bump `naval_ai_candidates_evaluated`, which is exactly what a different case in the same file already proves elsewhere.
- `tests/naval_ai_performance_smoke.gd` (fixed, not just re-run): the strict `naval_ai_commands_submitted` assertion was widened from "one command per country" to "two commands per country" (one `ConstructShipCommand`, one `SetNavyMaintenanceCommand`) - the real, now-correct count once both are genuinely exercised, not a weakened bound.
- `tests/naval_ai_test.gd`, `tests/naval_ai_trace_neutrality_test.gd` (pre-existing, re-run clean): both two-instance 215-day determinism replays against the real Iberian fixture still reproduce an identical outcome and checksum, confirming the new maintenance step introduces no nondeterminism.
- Every other naval-AI and broader naval test (`naval_ai_threat_test`, `naval_ai_organisation_test`, `naval_ai_transport_test`, `naval_ai_tactical_missions_test`, `naval_ai_reinforcement_homeport_transport_test`, `naval_ai_escort_lifecycle_test`, `naval_ship_technology_gate_test`, `naval_ai_player_battle_arbitration_test`, `naval_destructive_edge_gate_test`, `naval_blockade_test`) re-run clean.
- Full-project headless parse-check re-run clean after every edit in this packet.

## What this means for FL3

Every FL3.1-FL3.6 sub-scope, all four "Automated verification" roadmap claims, and this last named FL3.2 bullet are now complete. FL3 has no remaining open item of its own.

## Deliberately out of scope for this packet

- **`maintenance_posture_bp`'s own missing economic connection** - confirmed to be a genuinely separate concept from the one this bullet asks for (a per-fleet combat-readiness dial, not a country-wide economic lever), and land's own equivalent field has no combat connection either, so building one for naval here would not actually be "mirroring land AI" - left open as its own distinct, not-yet-designed item.
- **A UI control for `SetNavyMaintenanceCommand`** - the command exists and the AI uses it; a player-facing control is a separate FL1/FL2 UI concern, not attempted here.
