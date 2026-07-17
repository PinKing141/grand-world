# Master Production Roadmap

## Confirmed Scope

- Start date: 11 November 1444.
- Initial endpoint: 1 January 1700.
- Future endpoint: 3 January 1821.
- First playable scale: small regional scenario.
- Recommended first region: Iberia.
- Initial player entity: country.
- Character and dynasty layer: introduced after the country-level vertical slice.

## Current Production Status

Phase 8's complete thin-loop country-system set is implemented in `0.8.0-phase8` and is undergoing validation. The project is not yet a conventional global Alpha because naval warfare, colonisation, a global trade network, HRE mechanics and the Reformation remain absent or incomplete. The [Completion Audit and Revised Delivery Roadmap](completion_audit/README.md) inserts measurable global-pillar and content-pilot gates before unrestricted Phase 9 worldwide content production. The [Naval and Maritime Implementation Roadmap](naval/README.md) expands the first global pillar into reviewable N1-N6 delivery slices. The [Strategic Map Visual Production Roadmap](map_visual_production/README.md) remains the cross-cutting art/rendering/content track required to bring the world map and remaining country-label work to release quality.

## Roadmap Summary

| Phase | Primary outcome | Production gate |
|---|---|---|
| 0. Pre-production and foundation | Reliable project, architecture, tools, data, tests, budgets | Pre-production Exit |
| 1. Map interaction and strategy UX | Hover, selection, information panels, map modes, camera | Map UX Gate |
| 2. Deterministic simulation core | Clock, WorldState, commands, events, RNG, save/load | First Playable |
| 3. World graph and movement | Adjacency, centres, pathfinding, armies, movement | Movement Gate |
| 4. Economy and country loop | Monthly economy, manpower, recruitment, construction | Economy Loop Gate |
| 5. Warfare and diplomacy | Wars, battles, sieges, occupation, peace, relations | War Loop Gate |
| 6. AI and regional vertical slice | Five-country autonomous campaign at representative quality | Vertical Slice |
| 7. Characters and dynasties | Rulers, families, titles, succession, opinions, vassals | Character Loop Gate |
| 8. Country depth and content | Technology, religion, culture, unrest, government, historical content | Alpha |
| 9. Global release production | Full-map scale, content complete, Beta, release candidate | 1.0 |
| Future. 1700–1821 | Enlightenment, revolutions, nationalism, extended technology | Post-1.0 expansion |

## Critical Path

~~~text
Reliable data and project foundation
        ↓
Province selection and legible UI
        ↓
WorldState, clock, commands, and saves
        ↓
Adjacency and movement
        ↓
Economy and recruitment
        ↓
War, occupation, peace, and diplomacy
        ↓
AI using the same command API
        ↓
Regional vertical slice
        ↓
Character and dynasty layer
        ↓
Country depth and historical production
        ↓
Global scale, Alpha, Beta, and release
~~~

## Cross-Cutting Tracks

These run throughout production:

### Quality

- Unit and integration tests.
- Deterministic replay tests.
- Save round-trip tests.
- Data validation.
- Campaign soak tests.
- Regression tracking.

### Performance

- Frame-time measurement.
- Simulation tick profiling.
- AI scheduling budgets.
- Save size and loading time.
- Map update batching.
- Memory tracking.

### Content

- Stable IDs.
- Historical source tracking.
- Validation and bake steps.
- Localisation-ready text.
- Scenario ownership and ruler histories.
- Content review and lock.

### Tools

- Adjacency generator.
- Province validator.
- Country and title editor.
- Scenario validator.
- Save inspector.
- Simulation debug overlay.
- AI decision inspector.

### User Experience

- Tooltips and explanations.
- Notifications.
- Information hierarchy.
- Keyboard shortcuts.
- Accessibility.
- Tutorialisation.
- Error recovery.

### Strategic Map Visual Production

- Approved political-atlas art direction and benchmark scenes.
- Sharp render output, political palette, borders, overlays, terrain, water, rivers, and map objects.
- Full-name country labels, localisation, historical review, and campaign lifecycle.
- Zoom LOD, accessibility, visual regression, asset provenance, and map performance gates.
- Detailed plan: [Strategic Map Visual Production Roadmap](map_visual_production/README.md).

## Milestone Build Expectations

Every major gate must produce a packaged build with:

- A known version identifier.
- A written test checklist.
- Known-issues notes.
- Performance capture.
- Save compatibility statement.
- Content version.
- Reproduction steps for blockers.

## Phase Entry Rule

A phase enters production only when:

- Its required predecessor gate passes.
- The phase document has been reviewed.
- Dependencies are available or explicitly scheduled.
- Exit criteria are measurable.
- The active risk register is updated.

## Phase Exit Rule

A phase exits only when:

- Required deliverables are integrated.
- Exit criteria pass.
- The build is playable.
- Required tests and documentation exist.
- Performance remains within budget.
- No blocker is deferred without an approved mitigation.

## Release Strategy

The release path is:

~~~text
Regional First Playable
→ Regional Vertical Slice
→ Full-System Alpha
→ Global Content Complete
→ Beta
→ Release Candidate
→ 1.0
→ 1700–1821 Expansion
~~~

The project should not scale content globally until the vertical slice proves that the gameplay, tools, UI, AI, saves, and performance form a sustainable production pipeline.
