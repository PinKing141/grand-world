# Phase 8 — Country Depth and Historical Content

## Implementation Status

**Implemented in build `0.8.0-phase8`; Alpha gate is in validation.** The complete thin-loop Phase 8 system set is authoritative, deterministic, command-driven, saved in schema 5, exposed to the player, and usable by the authored Iberian AI profiles. Automated tests cover the systemic gate and a deterministic campaign from 1444 to 1700.

Historical data in `assets/country_depth_definitions.json` is deliberately marked as a representative Iberian gameplay setup with provenance notes and a required historical-review flag. It is not presented as globally content-complete. Scaling reviewed cultures, religions, governments, capitals, technology, cores, claims, diplomacy, and event content to every active country is Phase 9 production work.

### Delivered systemic loops

- Data-validated governments, authority, reforms, centralisation, modifiers, stability, and an initial three-estate placeholder.
- Province control, source-by-source unrest, recent-conquest and separatism penalties, rebel organisation, uprisings, and suppression.
- Primary and accepted cultures, state and province religions, tolerance, religious unity, and gradual culture/religion conversion.
- Administrative, diplomatic, and military technology with date-sensitive costs and building, unit, reform, formation, culture, and integration unlocks.
- Data-driven national directions with modifiers and deterministic AI preference.
- Permanent cores, expiring fabricated claims, justified conquest declarations, and core/claim war-score discounts.
- Vassals and character-driven personal unions with liberty desire, subject income, war participation, diplomacy restrictions, succession reconciliation, and deterministic integration.
- Localised, data-driven country events and decisions with validated triggers/effects, weighted AI options, cooldowns, bounded history, expiry fallback, and national formations.
- Expanded building families and five-step land-unit progression, all technology-gated and available through the province economy interface.
- Safe country extinction, successor-country formation, independent-country release, and reference replacement across subjects, wars, diplomacy, armies, characters, titles, and player control.
- Country-depth AI that uses the same validated player commands and records bounded decision explanations.
- A draggable Country & State interface with government, technology, society, province, rebel, subject, event, and decision tabs plus unrest, control, culture, religion, and technology map modes.
- Schema-5 checksums, migrations, registry validation, exact save/load replay, and packaged-resource coverage.

### Automated acceptance evidence

- `tests/phase_8_country_depth_test.gd` validates the complete command/system loop, corruption handling, formation/release, subject lifecycle, and AI exclusion of the player.
- `tests/phase_8_integration_smoke.gd` validates the packaged main scene, UI actions, strategic overlays, player event path, and exact quick-save restoration.
- `tests/phase_8_1444_1700_soak.gd` runs 1444–1600, forks through a schema-5 checkpoint, replays both branches to 1700, compares checksums, validates bounded/valid state, and round-trips the final save.
- `tools/testing/run_all_tests.py` includes all Phase 8 checks and requires the new data, UI, simulation, and AI resources in Windows exports.

### Validation still requiring humans

- Historical review and source replacement for the representative Iberian government, culture, religion, core, claim, ruler, and province setup.
- Hands-on balance for technology pacing, stability cost, conversion speed, revolt pressure, liberty desire, integration duration, buildings, units, and event outcomes.
- Readability, colour-blind safety, tooltip quality, UI scaling, feedback art/audio, and input ergonomics on reference hardware.
- Phase 9 global content throughput and performance projections before calling the project content-complete.

## Mission

Expand the proven country and character loops into the complete planned 1.0 system set, and establish sustainable historical content production for 1444–1700.

## Production Gate

Alpha.

## Player Outcome

Countries develop distinct identities through government, technology, culture, religion, internal politics, claims, subjects, and events. Campaign decisions meaningfully change long-term development.

## Entry Conditions

- Character Loop Gate passes.
- Core country, war, economy, AI, and character systems are stable.
- Content pipelines have measured throughput from the vertical slice.

## Major System Epics

### Government

- Government type.
- Laws or reforms.
- Legitimacy or equivalent authority.
- Centralisation.
- Government-specific modifiers.
- Reform costs and requirements.

### Stability and Internal Politics

- Stability.
- Unrest.
- Revolt risk.
- Rebel factions.
- Control.
- Separatism.
- Recently conquered penalties.
- Internal-faction placeholder or initial estate model.

### Culture

- Province culture.
- Country primary culture.
- Accepted cultures.
- Cultural penalties.
- Gradual conversion.
- Cultural unrest.

### Religion

- Province religion.
- State religion.
- Tolerance.
- Conversion.
- Religious unity.
- Religious diplomacy.
- Reformation-era content architecture.

### Technology

- Administrative technology.
- Diplomatic technology.
- Military technology.
- Ahead-of-time or era balancing.
- Unlocks for units, buildings, governments, and actions.
- Technology modifiers.

### Ideas or National Direction

- Country-level strategic specialisation.
- Data-driven groups.
- Unlock progression.
- AI selection weights.

### Claims and Cores

- Permanent or timed cores.
- Claims.
- Claim fabrication or acquisition.
- War-goal integration.
- Peace-cost modifiers.
- Province unrest and legitimacy effects.

### Subjects

Initial relationships:

- Vassal.
- Personal union where character and title systems permit.

Required:

- Liberty or loyalty.
- Subject income.
- War participation.
- Integration placeholder.
- Subject diplomacy restrictions.

### Events and Decisions

- Trigger/effect framework expanded.
- Country decisions.
- Historical event chains.
- AI option weights.
- Event history and cooldowns.
- Localisation.

### Buildings and Units

- Expanded building families.
- Unit upgrade path.
- Technology unlocks.
- Maintenance and manpower balance.
- AI understanding.

### Historical 1444 Setup

Content production includes:

- Active countries.
- Ownership and control.
- Capitals.
- Governments.
- Rulers and heirs.
- Basic dynasties.
- Diplomacy.
- Existing wars and truces.
- Cultures and religions.
- Province economy.
- Technology.
- Claims and cores.

## Alpha Definition

Alpha means:

- Every planned 1.0 system exists.
- Systems communicate through production APIs.
- The campaign can run from 1444 to 1700.
- Major content gaps remain, but no new foundational system is required.
- UI may still be incomplete or unpolished.
- Balance is not final.

## Acceptance Criteria

- Every planned 1.0 system has an implemented player path.
- AI can use or respond to every required system.
- Save/load supports all new state.
- A 1444–1700 automated campaign completes.
- Country extinction and formation are safe.
- Religious and cultural changes remain valid.
- Claims and cores affect war and peace correctly.
- Subject relationships survive war, succession, and save/load.
- Content validators detect missing required fields.
- System explanations appear in UI tooltips and breakdowns.

## Content Production Gates

- Stable content schemas.
- Source citation or provenance field for historical data.
- Localisation keys instead of hard-coded player-facing text.
- Automated ID and reference validation.
- Batch import and bake.
- Content review checklist.
- No editor-only manual step required for every build.

## QA Focus

- Country annexation and release.
- Religious conversion and revolt.
- Government change.
- Technology unlock.
- Subject inheritance.
- Claims after ruler death.
- Event chains interrupted by country destruction.
- Save migration after schema expansion.
- AI handling of new actions.

## Primary Risks

- Feature breadth prevents any system from reaching useful depth.
- Historical content volume overwhelms implementation.
- Character and country rules conflict.
- AI cannot reason about all added mechanics.
- Save schema churn accelerates.

## Scope Controls

- Each new system needs a complete thin loop before additional depth.
- Historical exceptions should prefer data and modifiers over special-case code.
- Global content production cannot begin until validators and bake tools are reliable.
- Features not required for the declared 1.0 loop move to the future backlog.

## Explicitly Out of Scope

- 1700–1821 mechanics.
- Complete global trade simulation unless specifically promoted into 1.0 scope.
- Detailed naval combat unless specifically promoted into 1.0 scope.
- Multiplayer.
- Unlimited mod scripting.
