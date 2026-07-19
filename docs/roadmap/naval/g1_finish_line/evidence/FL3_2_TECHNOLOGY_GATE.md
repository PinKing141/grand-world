# FL3.2 Follow-up - Ship Construction Technology Gate

**Status:** Complete. Targeted tests pass (see Verification).
**Satisfies:** the "Respect... technology... land-war needs" bullet [FL3_2_STRATEGIC_POSTURE.md](FL3_2_STRATEGIC_POSTURE.md) originally recorded as a genuine, unfixed simulation-layer gap: `ship_definitions.json` already declares a `required_technology` `{track, level}` for every ship (`ShipDefinitions._validate()` has required and validated this field since N2.1), but `ConstructShipCommand.validate()` never read it - a real authoritative correctness gap, not merely an AI-planning omission, since it meant *any* caller (player or AI) could build a technology-gated ship regardless of the country's actual technology.

## What shipped

### Command-level gate (`ConstructShipCommand.validate()`)

Mirrors `RecruitUnitCommand.validate()`'s own technology check (`commands/recruit_unit_command.gd:32-36`) exactly - same guard, same data shape, same message shape:

```gdscript
if bool(world.global_flags.get("country_depth_enabled", false)):
	var requirement: Dictionary = definition.get("required_technology", {})
	var technology: Dictionary = world.country_runtime(country_tag).get("technology", {})
	if int(technology.get(String(requirement.get("track", "military")), 0)) < int(requirement.get("level", 0)):
		return "%s requires %s technology %d." % [definition_id, String(requirement.get("track", "military")), int(requirement.get("level", 0))]
```

- **Gated on `country_depth_enabled`** - a synthetic/legacy world without `CountryDepthSystem` (most naval unit tests in this project, and any save predating country depth) never sees this check at all, the same compatibility guarantee `RecruitUnitCommand` already established. Nothing about naval construction's own behaviour changes for those worlds.
- **A floor, not an exact match** - technology at or above the requirement is accepted; below it is rejected with a message naming the exact missing track and level.
- **No new data needed** - every ship already had a valid `required_technology` field; this closes the gap between data that existed and code that read it.

### Naval AI: skip locked designs, try the next family

`_plan_construction()`'s family-selection logic previously picked the single largest-deficit family (ties broken by `ShipDefinitions.ship_families()`'s fixed order) and gave up entirely - recording a rejected candidate - if that one family's cheapest ship happened to be locked (by date or, now, by technology). Real data makes this a genuine gap, not a hypothetical one: `heavy_galleon` requires military technology 1, so a country with technology 0 and a `wartime`/`threatened` posture (both weight `heavy` highest) would have proposed the same locked candidate every single `CONSTRUCTION_INTERVAL` tick forever, never building anything.

Fixed by ranking every family by deficit (same tie-break as before, preserving the exact "default to galley" fallback for the rare all-non-positive-deficit case), then trying each in order until one has an eligible design:

- **`_cheapest_eligible_ship_in_family()`** (renamed and extended from `_cheapest_ship_in_family()`) now applies the identical `country_depth_enabled`/`required_technology` check `ConstructShipCommand.validate()` itself uses, so a locked ship is treated as not existing yet - the same way an unreleased (future `unlock_date`) ship already was.
- If every family is locked, exactly one clear rejection is recorded (`"No unlocked, technology-eligible ship exists in any target family."`), not one per family attempted.
- If a legal family exists anywhere in the ranking, the AI builds toward it instead of the locked top-priority one - proven by a real `wartime` fixture where `heavy` (the highest-weighted family) is fully locked and the AI correctly falls through to `galley` (the next-highest weight), never proposing `heavy_galleon` at all.

## Verification

- `tests/naval_ship_technology_gate_test.gd` (new): the command gate stays inert on a world with no `country_depth_enabled` flag; rejects below the required level with the exact expected message; accepts at the exact required level and above (a floor, not an exact match); the naval AI skips a fully-locked top-priority family (`heavy`) and successfully builds the next-ranked eligible one (`galley`) instead, with the final recorded decision being the successful submission, not a rejection; a fully-locked navy (every family requiring more technology than the country has) records exactly one explained rejection rather than a crash or a rejection per family; and a player-issued and an AI-issued command for the identical illegal ship are rejected with the byte-identical message, proving there is no parallel eligibility path.
- `tests/naval_ai_test.gd`, `tests/naval_ai_strategic_posture_test.gd`, `tests/naval_ai_explainability_test.gd`, `tests/naval_economy_test.gd`, `tests/naval_blockade_test.gd` (pre-existing, re-run clean) - none of these fixtures set `country_depth_enabled`, confirming the gate's compatibility guarantee holds and that the family-ranking refactor reproduces the exact same construction choices these tests already assert on.
- Registered in `tools/testing/run_all_tests.py`.
- Full-project headless parse-check re-run clean after every edit in this packet.

## Deliberately out of scope for this packet

- **A synthetic ship-definitions fixture where every family requires technology > 0** - the "every family locked" test case instead uses a below-zero technology value against the real data (only `heavy` requires above level 0 today), a valid probe of the same comparison at a different boundary rather than a second, parallel data fixture.
- **Any change to `RecruitUnitCommand` or land-side technology gating** - already correct and already tested (`tests/phase_8_country_depth_test.gd`); this packet only extends the identical, already-proven pattern to the naval side.
