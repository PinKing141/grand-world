# Phase 9 — Global Scale, Alpha, Beta, and 1.0

## Mission

Scale the feature-complete simulation and content pipeline to the full world, reach content complete, stabilise the 1444–1700 campaign, and produce a release candidate.

## Production Gates

- Alpha.
- Content Complete.
- Beta.
- Release Candidate.
- 1.0.

## Entry Conditions

- Phase 8 Alpha criteria pass.
- No planned 1.0 foundational system remains unimplemented.
- Global content schemas and validators are stable.
- Regional performance budgets have passed with scaling projections.
- The Strategic Map Visual Production Roadmap has passed its Visual Greenlight and has an approved political/environment vertical-slice plan.

## Major Deliverables

### Global Data

- Full province definitions.
- Active 1444 countries.
- Ownership and control.
- Country capitals.
- Cultures.
- Religions.
- Governments.
- Technology.
- Province economies.
- Claims and cores.
- Diplomacy, wars, and truces.
- Required rulers, heirs, dynasties, and titles.

### Global Simulation Scale

- AI scheduling across active countries.
- Large-war handling.
- Global pathfinding load.
- Country formation and extinction.
- Long-distance diplomacy.
- Map labels and culling.
- Map-mode batching.
- Memory and save-size control.

### Strategic Map Visual Production

- Execute the [Strategic Map Visual Production Roadmap](map_visual_production/README.md).
- Lock a project-original EU4-led political-atlas art direction.
- Complete political readability, terrain, water, hydrography, country labels, map objects, and zoom LOD.
- Scale approved regional pipelines to the full world.
- Meet visual regression, accessibility, provenance, performance, compatibility, and packaged-build gates.

### UI Completion

- Main HUD.
- Province and country panels.
- Military.
- Economy.
- Diplomacy.
- Technology.
- Government.
- Religion and culture.
- Characters and succession.
- Outliner.
- Message settings.
- Notifications.
- Pause and settings menus.
- Save/load browser.
- Tutorial and help.

### Onboarding

- First-session flow.
- Country selection.
- Recommended countries.
- Contextual tutorial.
- Tooltips.
- Glossary.
- Error prevention.
- Recovery guidance.

### Accessibility

- UI scale.
- Colour-blind-safe map modes.
- Remappable controls.
- Text readability.
- Pause-friendly interaction.
- Reduced motion where relevant.
- Audio volume categories.

### Audio and Presentation

- UI feedback.
- Map interaction sounds.
- War and battle notifications.
- Ambient layers.
- Music state logic.
- Consistent icon and visual language.
- Loading and transition presentation.

### Packaging and Compatibility

- Supported Windows versions.
- Reference hardware matrix.
- Graphics fallback policy.
- Addon binary verification.
- Clean install.
- Upgrade install.
- Save location and backup.
- Crash logs.

## Alpha Exit

- Full 1.0 system set integrated.
- Automated campaign reaches 1700.
- Global scale runs within provisional budgets.
- All P0 and most P1 functional gaps resolved.
- Content production can continue without schema redesign.

## Content Complete Exit

- Planned 1444–1700 content exists.
- Localisation keys resolve.
- No missing required country or province data.
- Historical setup review complete.
- Tutorial content complete.
- No planned content category remains empty.
- The map-visual track has passed Visual Content Complete, including the migrated country-label/name backlog.

## Beta Entry

Beta begins only when:

- Feature lock is active.
- Content schemas are locked.
- Save schema changes require explicit approval.
- Focus shifts to bugs, balance, usability, performance, and compatibility.

## Beta Activities

- Balance campaigns.
- AI tuning.
- Exploit testing.
- Usability testing.
- Tutorial iteration.
- Hardware compatibility.
- Save upgrade tests.
- Long soak tests.
- Memory and leak testing.
- Load-time optimisation.
- Localisation layout testing.

## Release Candidate Gate

- No open P0 issues.
- No unmitigated P1 issues.
- Campaign start, save, load, and completion paths pass.
- Supported hardware matrix passes.
- Deterministic tests pass.
- Content validation passes.
- Legal and provenance checks pass.
- Installer and rollback path pass.
- Release notes and known issues prepared.
- The map-visual track has passed its Visual Release Candidate gate.

## Acceptance Criteria for 1.0

- A new player can start and understand a campaign.
- A campaign can run from 1444 to 1700.
- AI countries remain active and coherent.
- Saves survive normal upgrades within the supported policy.
- Global map interaction remains responsive.
- No recurring simulation hitch breaks high-speed play.
- Country, war, economy, diplomacy, and character loops remain functional over centuries.
- The build can recover gracefully from invalid external content.

## Primary Risks

- Global content reveals assumptions hidden by the regional slice.
- AI and pathfinding cost grow non-linearly.
- Save size and load time become unacceptable.
- Late-game simulation slows dramatically.
- Final UI integration creates regressions.
- Feature requests continue after Beta.

## Scope Controls

- Beta feature lock is real.
- New mechanics after Alpha require removal of equivalent scope or deferral.
- Historical flavour must use existing systems.
- 1700–1821 work remains deferred until after 1.0 stability.
