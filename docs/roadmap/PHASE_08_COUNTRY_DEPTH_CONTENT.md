# Phase 8 — Country Depth and Historical Content

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

