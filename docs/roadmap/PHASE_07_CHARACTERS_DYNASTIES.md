# Phase 7 — Characters, Dynasties, Titles, and Succession

## Mission

Add a CK-style human and feudal layer on top of the proven country simulation without destabilising country ownership, war, economy, saves, or AI.

## Production Gate

Character Loop Gate.

## Current Status

**Validation.** The systemic Phase 7 character loop is integrated in build `0.7.0-phase7`. It remains country-first: characters influence and legally hold titles, while countries remain the authoritative owners of provinces, treasuries, armies, diplomacy, and player control.

## Implemented Foundation

- Validated, data-driven Iberian characters, dynasties, primary titles, ruler/heir assignments, and representative claims in `assets/character_definitions.json`.
- Save schema 4 registries for characters, dynasties, titles, and claims, all included in deterministic checksums and exact save/load replay.
- Schema-3 migration that restores scenario character defaults without corrupting older country/economy/war state.
- Stable family references, symmetric marriages, living-dynasty indexes, title-holder indexes, character-title/claim reverse links, and ancestry/title-cycle rejection.
- Derived age, skills, traits, health, fertility, stress, illness, court, offices, titles, claims, parents, spouses, former spouses, and children.
- Batched monthly health, illness, fertility, birth, coming-of-age, death, trait-pressure, court-demographic, heir, and character-AI processing.
- Deterministic absolute-primogeniture succession with child/dynasty ordering, short reign, legitimacy loss, ruler-modifier recalculation, commander cleanup, inheritable claims, and cadet-house continuity fallback.
- Explainable character opinions from family, marriage, dynasty, culture, religion, traits, claims, recent title grants, and short reign.
- Ruler stewardship/martial/traits modify economy and manpower; commander martial/traits modify battle power.
- Authoritative marriage, commander, title-grant, and claim-war commands with rejection reasons.
- Claim war goals, enforce-claim peace terms, title transfer, and initial personal-union placeholder state.
- Periodic character AI for commander selection, scored marriages, succession awareness, and strength/truce-gated claim evaluation.
- Court & Dynasty UI with portrait placeholder, ruler/heir, succession order, character sheet, dynasty/family data, skills, traits, health, titles, claims, opinions, marriage actions, claim actions, and character-AI reasoning.
- Birth, illness, coming-of-age, marriage, death, succession, title, commander, claim, and AI events for UI and future event content.

## Automated Evidence

- `tests/phase_7_character_test.gd`: malformed ancestry rejection, initial content, marriage/kinship validation, commander ownership, opinion sources, deterministic death/succession, schema migration, exact save round-trip, claim war/peace, reproduction, and reference integrity.
- `tests/phase_7_integration_smoke.gd`: packaged scene, Court & Dynasty UI, player marriage, player-country AI exclusion, character-AI review, exact quick save/load, claim-war peace UI, and live succession refresh.
- `tests/phase_7_multigeneration_soak.gd`: one hundred simulated years with repeated marriages, births, illnesses, deaths, successions, midpoint deterministic replay, reference audits, final save round-trip, bounded AI history, and memory-growth budget.
- `tests/ui_layout_smoke.gd`: character window containment at 1700×960 and 1152×648.
- `tools/testing/run_all_tests.py`: unified Phase 1–7 regression, three campaign soaks, export-content verification, and exported-build startup.

## Remaining Validation Before Gate Approval

- Historically review and source the representative Iberian ruler, family, title, and claim setup; current data is a gameplay-validation slice rather than content lock.
- Tune mortality, fertility, court arrivals, skills, traits, ruler modifiers, legitimacy, marriage scoring, and claim-war behaviour through repeated player and observer campaigns.
- Replace initials with an approved portrait system and add the planned ruler/heir/consort/death/succession icon set.
- Review family-tree navigation, opinion explanations, marriage controls, claim feedback, and death/succession notifications on supported displays.
- Profile the graphical build during century-scale simulation and inspect save size/loading time as character populations grow.
- Verify the Windows export with real mouse/keyboard interaction and record remaining P0/P1 defects.

## Player Outcome

Countries have rulers with families, traits, skills, claims, opinions, and succession. Ruler death changes leadership and may alter legitimacy, diplomacy, vassal loyalty, and realm structure.

## Entry Conditions

- Vertical Slice passes.
- Country-level campaign loop is stable and measured.
- Event, modifier, command, save, and AI frameworks are extensible.
- Player identity remains country-first for the initial implementation.

## Architecture Principle

Keep these separate:

~~~text
Country or Realm
Political institution and international actor

Title
Legal claim connecting authority to territory

Character
Person who holds titles and offices

Dynasty
Family identity shared across characters
~~~

A character influences a country but does not replace its WorldState identity.

## Major Deliverables

### Character Definition and State

Core fields:

- Character ID.
- Name and localisation key.
- Birth and death date.
- Sex.
- Culture.
- Religion.
- Dynasty.
- Parents, spouses, and children.
- Skills.
- Traits.
- Health.
- Fertility.
- Stress or personal pressure placeholder.
- Employer or court.
- Titles and claims.

### Dynasty

- Dynasty ID and name.
- Founder.
- Living members.
- Prestige or renown placeholder.
- Player-dynasty flag where future modes require it.
- Family-tree query APIs.

### Titles

Ranks:

- Barony placeholder.
- County.
- Duchy.
- Kingdom.
- Empire.

Title fields:

- Holder.
- Liege title.
- De jure parents and vassals.
- Associated provinces.
- Capital.
- Claims.
- Succession law.

### Rulers and Offices

- Country ruler.
- Heir.
- Commander assignment.
- Advisor or council placeholders.
- Skill effects through the modifier system.

### Marriage and Family

- Marriage validation.
- Spouse relationship.
- Child generation.
- Parentage.
- Dynasty assignment.
- Basic AI marriage scoring.

### Health, Ageing, and Death

- Daily or periodic health processing.
- Natural death.
- Scripted death.
- Death event.
- Cleanup without invalid references.

### Succession

Initial law:

- Primogeniture or a deliberately simpler single-heir model.

Succession process:

1. Identify ruler death.
2. Determine eligible heirs.
3. Rank heirs deterministically.
4. Transfer ruler role and titles.
5. Update heir.
6. Apply legitimacy and short-reign modifiers.
7. Recalculate diplomatic and vassal effects.
8. Notify player and AI.

Partition and complex elective succession are deferred until the simple model is stable.

### Opinions

Explainable opinion sources:

- Base.
- Family.
- Marriage.
- Culture.
- Religion.
- Traits.
- Claims.
- Recent actions.
- Liege and vassal relationship.
- Short reign.
- Granted or revoked titles.

### Claims

Initial claim types:

- Strong claim.
- Weak claim placeholder.
- Inheritable claim.

Claims integrate with war-goal validation.

### Character Events

Representative events:

- Birth.
- Coming of age.
- Marriage.
- Illness.
- Death.
- Succession.
- Trait-driven interaction.

### Character UI

- Ruler portrait placeholder.
- Character sheet.
- Family tree.
- Spouse and children.
- Skills and traits.
- Titles and claims.
- Opinion breakdown.
- Succession screen.

### AI

- Marriage candidates.
- Heir and succession awareness.
- Commander assignment.
- Claim evaluation.
- Opinion-driven diplomacy modifiers.

### Save Integration

Save:

- Characters.
- Dynasties.
- Relationships.
- Titles.
- Claims.
- Health state.
- Traits.
- Succession state.
- Character event cooldowns.

## Acceptance Criteria

- Every active test country has a valid ruler.
- Rulers age and can die.
- Death triggers deterministic succession.
- The new ruler affects country modifiers.
- Family relationships remain valid after save/load.
- No title has an invalid living holder reference.
- Claims can create a valid war goal.
- Opinion breakdown matches its sources.
- AI can arrange valid marriages and handle succession.
- A multi-generation automated campaign completes without reference corruption.

## QA Focus

- Ruler dies with no child.
- Multiple eligible heirs.
- Child ruler.
- Ruler holds multiple titles.
- Spouse belongs to another country.
- Dynasty extinction.
- Simultaneous family deaths.
- Save/load immediately before death.
- Annexed country with living ruler.
- Title holder changing country.

## Performance Gates

- Characters are data objects, not per-character processing nodes.
- Ageing and health are scheduled in batches.
- Family-tree indexes avoid global scans.
- UI loads only visible relationship data.
- Character AI runs periodically, not daily for every person.

## Primary Risks

- Character scope becomes a second complete game before the country layer is ready.
- Family and title references become difficult to migrate in saves.
- Succession creates invalid country or title ownership.
- UI requirements expand rapidly.
- Historical character content becomes a production bottleneck.

## Explicitly Out of Scope

- Full CK-style intrigue.
- Complete genetic inheritance.
- Dozens of succession laws.
- Detailed court positions.
- Complex regencies.
- Playable dynasty mode.
- Full 1444 world character database.
