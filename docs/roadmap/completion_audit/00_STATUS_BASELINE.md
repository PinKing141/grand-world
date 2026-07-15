# 00 — Status Baseline

## Purpose

This file records what Grand World can already do, where that implementation is representative rather than global, and which completion label should be used in future planning.

## Completion Vocabulary

| Status | Required evidence |
|---|---|
| Framework | Stable data model/API exists and can be saved. |
| Thin loop | A player and AI can complete the simplest end-to-end interaction. |
| Vertical-slice ready | Representative content, UX, art, AI and performance demonstrate target quality in one region. |
| Global Alpha | Every planned 1.0 system exists, connects to every required region and passes automated integration gates. |
| Content complete | Planned worldwide content is authored, sourced, validated and reviewed. |
| Beta | Feature and content scope are locked; only balance, UX, optimisation and defect work remain. |
| Release candidate | Packaging, compatibility, legal, accessibility and blocker gates pass on supported hardware. |

## What Is Already Implemented

### Strategic map and interaction

- Full-world province topology, province selection and country selection.
- Political, terrain, IDs, relations, war and access map modes.
- Mouse drag-pan, wheel zoom, WASD/arrow movement and camera reset.
- Country and province labels with a screen-space rendering path.
- Terrain, height and water presentation with zoom-aware rendering work.
- Country, subject, province and coast border work, including a canonical shared-edge direction.
- Army markers, marker clustering and marker interaction foundations.
- Main menu, single-player nation selection and campaign HUD shell.

### Deterministic campaign foundation

- Pauseable date clock and multiple time speeds.
- Deterministic WorldState, command API, event flow and RNG practices.
- Save/load with schema migration work and save round-trip tests.
- Stable country/province IDs and data-driven content loaders.
- Headless test harness and long-run campaign validation.

### Land graph and movement

- Province adjacency and centre generation.
- Land and strait pathfinding.
- Army creation, orders, travel and arrival.
- Army panel and map marker representation.
- Coastal/sea graph information that can support a later naval layer.

### Economy and country loop

- Province development, tax, production, manpower and trade-good data.
- Country treasury, income, expenses, loans and construction.
- Recruitment, manpower and maintenance.
- Buildings, unit definitions and country economy panels.
- AI commands that use the same deterministic state-changing API.

### Warfare and diplomacy

- War declaration, war membership, war goals and active-war state.
- Land battle, morale, retreat, reinforcement and commander inputs.
- Sieges, occupation, war score and peace resolution.
- Relations, alliances, access, subjects and personal-union foundations.
- Deterministic AI capable of participating in the regional war loop.

### Country depth and characters

- Government, stability, unrest, rebellion and province control.
- Culture, religion, tolerance and conversion foundations.
- Administrative, diplomatic and military technology tracks.
- National-direction, core, claim, event and decision frameworks.
- Rulers, heirs, dynasties, titles, succession and opinion foundations.
- Country release/formation and subject-state foundations.

### Testing and performance

- Recorded full headless suite: 42/42 passing.
- Deterministic campaign, save/load and content-validation coverage.
- Recent front-end shell, country-selection and layout checks passing.
- Recorded 1080p map-motion frame time: P50 13.266 ms and P95 15.748 ms on an AMD Radeon 610M.

## What These Achievements Do Not Yet Prove

- They do not prove that every country has historical content.
- They do not provide naval play, overseas transport or naval AI.
- They do not provide exploration, colonisation or colonial nations.
- They do not provide a directional global trade network.
- They do not provide HRE or historical Reformation mechanics.
- They do not prove worldwide AI behaviour, balance or late-campaign stability with all future pillars active.
- They do not clear the project for release while map-source provenance, water-source provenance, final river sourcing, historical shield review and third-party asset rights remain unresolved.

## Current Honest Milestone

Grand World is best described as a **broad systems prototype with an Iberian-focused vertical-slice foundation**. It is beyond a tech demo: it contains connected economy, land movement, warfare, diplomacy, country depth and character systems. However, it is not yet a global Alpha because several genre-defining pillars do not exist and worldwide authored content is extremely thin.

## Decision Needed Before Further Scale

Before mass worldwide content production, approve one of these product definitions:

1. **Full global 1444–1700 1.0:** naval, colonisation, trade, HRE and Reformation are mandatory before Alpha.
2. **Reduced regional 1.0:** geographically restrict the release and formally defer global pillars.
3. **Staged Early Access:** ship a clearly labelled regional build, then add the global pillars before calling the product 1.0.

The existing product vision points to option 1. This roadmap assumes that full global scope remains the goal.
