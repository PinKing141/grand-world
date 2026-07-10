# Production Framework

## Purpose

This framework applies large-project production discipline to a small or growing team without copying the bureaucracy of a large studio.

The objective is to maintain:

- A continuously playable build.
- Clear milestone goals.
- Visible dependencies and risks.
- Stable data and save schemas.
- Testable exit criteria.
- Controlled scope.
- Regular profiling and validation.

## Workstreams

Every phase considers these workstreams:

| Workstream | Responsibility |
|---|---|
| Design | Rules, balance targets, player decisions, edge cases |
| Engineering | Runtime systems, tools, data, saves, performance |
| Map and Rendering | Selection, map modes, overlays, labels, visual updates |
| UI and UX | Interaction flow, accessibility, feedback, information hierarchy |
| Content | Historical setup, definitions, events, localisation, balance data |
| AI | Strategic, economic, diplomatic, and military decision-making |
| QA | Tests, validation, reproduction, regression, compatibility |
| Production | Scope, sequencing, dependencies, milestone health, risk |
| Audio and Presentation | Feedback, ambience, music, effects, polish |

One person may own several workstreams. The separation still matters because each produces different deliverables and risks.

## Milestone Gates

### Concept Gate

Required:

- Product statement.
- Core pillars.
- Historical period.
- Player identity.
- Platform assumptions.
- First playable definition.
- Explicit non-goals.

### Pre-production Exit

Required:

- Major technical risks prototyped.
- Map and data import reliable.
- Architecture boundaries documented.
- Source control and backup strategy active.
- Automated smoke-test path available.
- Performance budgets defined.
- Content validation pipeline designed.
- Save schema strategy documented.

### First Playable

Required:

- Player can select a country.
- Time can pause and advance.
- Provinces display useful data.
- Monthly economy updates.
- At least one meaningful command changes world state.
- Save and load restore the playable state.

### Vertical Slice

Required:

- Five-country regional campaign.
- Representative map UX.
- Economy, movement, warfare, peace, diplomacy, and AI connected.
- Representative art and audio direction.
- Representative UI quality.
- Stable save/load.
- Target performance reached in the slice.
- A new content item can be added through documented pipelines.

### Alpha

Required:

- Every planned 1.0 gameplay system exists.
- Systems are integrated.
- No major placeholder architecture remains.
- Campaign can run from 1444 to 1700 in automated simulation.
- Known content gaps are tracked.

### Content Complete

Required:

- Planned countries, provinces, starts, events, technologies, and localisation are present.
- Data validation passes.
- No feature requires new content schema work.

### Beta

Required:

- Feature lock.
- Save schema locked except critical migrations.
- Focus on defects, usability, balance, compatibility, and performance.
- Tutorial and onboarding path complete.

### Release Candidate

Required:

- No open release blockers.
- Supported hardware test matrix passes.
- Save/load, campaign soak, and upgrade tests pass.
- Distribution build and rollback procedure verified.
- Legal and asset provenance review complete.

## Definition of Ready

Work is ready to enter production when:

- The player or developer outcome is clear.
- Dependencies are identified.
- Acceptance criteria are testable.
- Required data and mock-ups exist or are explicitly part of the task.
- Performance and save implications are considered.
- Error and edge cases are identified.
- The work fits the active milestone.

## Definition of Done

Work is complete when:

- Acceptance criteria pass.
- Automated tests exist where appropriate.
- Error handling and validation are present.
- Save/load behaviour is defined.
- AI behaviour is defined when the feature affects AI.
- UI feedback is present when the player can interact with it.
- Performance is measured against its budget.
- Documentation is updated.
- No known critical or high-severity regression remains.
- The feature works in a packaged playable build, not only in the editor.

## Backlog Structure

Use this hierarchy:

~~~text
Pillar
└── Milestone
    └── Epic
        └── Feature
            └── Task or bug
~~~

Recommended priority labels:

- P0: release or milestone blocker.
- P1: required for milestone exit.
- P2: important but can be deferred without invalidating the milestone.
- P3: polish, experiment, or future work.

Recommended effort labels:

- XS: isolated and understood.
- S: small change with limited integration.
- M: multi-file feature with known dependencies.
- L: cross-system feature or tool.
- XL: epic that must be split before implementation.

## Production Cadence

For a small team:

- Keep a short active work queue.
- Review milestone health weekly.
- Produce a playable build at least weekly.
- Run automated validation on every meaningful change.
- Profile at fixed milestone checkpoints.
- Review the risk register at phase start and phase exit.
- Hold a retrospective after First Playable, Vertical Slice, Alpha, and Beta.

Do not assign calendar dates until team capacity and sustainable throughput are known. Use dependency order and milestone gates first; estimate dates after completing enough representative work.

## Scope and Change Control

Any proposed addition to the active milestone must answer:

1. Which product pillar does it support?
2. Is it required for the milestone exit criteria?
3. What dependency does it introduce?
4. What testing and content cost does it add?
5. What current work will be displaced?
6. Can it be deferred without damaging the player experience?

If no current work is displaced, the estimate is probably incomplete.

## Critical-Path Rules

- Do not build deep AI before commands and world state are stable.
- Do not build global content before the regional pipeline works.
- Do not build complex character succession before country ownership, time, saves, and events are stable.
- Do not optimise hypothetical bottlenecks; profile representative scenarios.
- Do not lock the save schema before core runtime state is understood.
- Do not begin Beta while planned systems are still being designed.

## Decision Records

Major technical and product decisions should record:

- Decision.
- Date.
- Context.
- Options considered.
- Selected option.
- Consequences.
- Revisit condition.

Examples:

- Country-first player identity.
- Daily deterministic ticks.
- Integer IDs for runtime entities.
- 1444–1700 initial campaign scope.
- Single-player first.
- Data-driven content definitions.

