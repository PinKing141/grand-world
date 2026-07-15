# 06 — Delivery Sequence and Gates

## Revised Critical Path

```text
Scope and architecture lock
        ↓
Naval/maritime foundation
        ↓
Exploration and colonisation
        ↓
Global trade network
        ↓
HRE and Reformation
        ↓
Existing-system depth pass
        ↓
Non-Iberian global-content pilot
        ↓
Worldwide regional content waves
        ↓
Presentation, audio and onboarding complete
        ↓
Global Alpha → Content Complete → Beta → Release Candidate → 1.0
```

Naval, colonisation and trade can overlap in implementation after their shared map/economy interfaces are locked, but none should be called complete without cross-system tests. HRE and Reformation can also overlap after religion, government and diplomacy contracts are approved.

## Milestone G0 — Global Scope and Architecture Lock

### Objective

Turn the five missing pillars from broad ideas into bounded 1.0 specifications before more dependent content is authored.

### Deliverables

- Approved 1.0/non-goal list for each pillar.
- Data schemas, stable IDs and save-version impact.
- Command/API boundaries and AI action surfaces.
- UI entry points and debug tooling requirements.
- Daily/monthly CPU, memory and save-size budgets.
- Acceptance tests and historical validation scenarios.
- Updated risk register and staffing/effort forecast.

### Exit criteria

- No unresolved design choice can force worldwide country/province content to be re-authored.
- Test fixtures exist for England–France naval transport, Portuguese/Castilian colonisation, a multi-node trade flow, the HRE election and the Reformation.
- The Phase 9 scope document explicitly references the revised gate structure.

## Milestone G1 — Maritime First Playable

### Objective

Make coastlines and sea zones strategically functional.

### Deliverables

- Port/sea graph authority and fleet data.
- Ship construction, movement, maintenance and repair.
- Army transport and disembarkation.
- First naval battle and blockade loop.
- Player fleet UI and basic naval AI.

### Exit criteria

- England–France Channel scenario passes deterministic replay and mid-operation save/load.
- No army becomes permanently stranded by transport-state failure.
- Fleet updates remain within the approved simulation budget.

## Milestone G2 — Age of Discovery First Playable

### Objective

Create the first complete exploration-to-colonial-subject loop.

### Deliverables

- Per-country discovery state and terra incognita.
- Exploration leaders/missions.
- Colonist assignment, range, cost and colony growth.
- Native interaction and colonial ownership conflict.
- Colonial regions and subject formation.
- Player UX and initial Portuguese/Castilian AI.

### Exit criteria

- Portugal and Castile complete an Atlantic exploration/colony scenario through deterministic seeds.
- Existing American states remain playable and interact correctly with discovery/colonial systems.
- Save files preserve discovery and colony state exactly.

## Milestone G3 — Global Trade First Playable

### Objective

Make goods, geography, maritime power and diplomacy feed one explainable economic network.

### Deliverables

- Trade-node/route data and validator.
- Province membership and monthly value propagation.
- Trade power, merchants, collection and steering.
- Trade/embargo/blockade/fleet integration.
- Trade map mode, node panel and debug trace.
- AI merchant and trade-fleet assignment.

### Exit criteria

- Every eligible province has one valid node.
- No route cycle or invalid sink/source exists.
- Global monthly calculation is deterministic and within budget.
- A player can reconstruct trade income from the UI explanation.

## Milestone G4 — Imperial and Reformation Arc

### Objective

Make central European politics and religious change function across the full campaign period.

### Deliverables

- HRE membership, offices, elections, authority and reforms.
- Imperial defence, incidents, Free Cities and unlawful territory.
- Reformation trigger, denominations, spread and country conversion.
- Confessional diplomacy, conflict and settlement.
- HRE/religion UI, map modes and AI.

### Exit criteria

- The 1444 HRE scenario validates and elections survive succession/save-load.
- Multi-seed 1517–1650 soaks produce bounded but non-identical religious outcomes.
- Imperial and religious war interactions produce valid peace states.

## Milestone G5 — System-Depth Vertical Slice 2

### Objective

Deepen existing systems and prove them in a harder non-Iberian region before worldwide authoring.

### Recommended test region

British Isles plus France, Burgundy and nearby HRE/Italian interfaces. This region exercises naval transport, French appanages/subjects, dynastic diplomacy, the HRE edge, trade and early colonisation.

### Deliverables

- Approved warfare, diplomacy, estate, government, economy and technology depth subset.
- Complete French appanage/subject data and visual rules.
- At least 20 fully authored non-Iberian countries.
- Final content packet/tool workflow exercised by people other than the original author where possible.
- Updated map/label/UI benchmark captures.

### Exit criteria

- A 100-year regional campaign is strategically varied, explainable and stable.
- Content-entry time and review cost are measured.
- No required global schema change remains.

## Milestone G6 — Global Content Waves

### Objective

Move from representative data to worldwide reviewed content without sacrificing consistency.

### Execution rule

Only one or two geographic waves should be in active authoring at once. Research, data entry, review and simulation validation form a pipeline, not a single bulk task.

### Exit criteria per wave

- All active countries have explicit completeness status.
- Ownership, capital, rulers, governments, culture/religion, claims and subject data validate.
- Historical and heraldry sources are reviewed.
- Regional multi-seed soaks have no unresolved blocker outlier.
- Localisation and full-name map/UI presentation pass.

## Milestone G7 — Presentation, Audio and Onboarding Complete

### Objective

Replace prototype presentation and missing player guidance with a coherent shippable experience.

### Deliverables

- Final component-based UI skin and icon set.
- Visual Greenlight for map, labels, borders, terrain, water and rivers.
- Portrait/heraldry coverage or approved neutral fallbacks.
- Music, SFX and audio settings.
- Full notifications, outliner, ledger, macro-builder and save browser.
- Tutorial, glossary, accessibility settings and localisation coverage.

### Exit criteria

- First-session usability test passes.
- UI layout/accessibility matrices pass.
- Every critical action has visual and optional audio feedback.
- All final art/audio assets have provenance approval.

## Milestone G8 — Global Alpha

- Every planned 1.0 pillar is integrated.
- Worldwide 1444 scenario loads without fallback-blocker data.
- Global AI can use every pillar.
- Save/load and deterministic replay pass with all systems enabled.
- Known placeholder content is enumerated and owned.

## Milestone G9 — Content Complete

- All active countries and planned historical arcs are reviewed.
- No missing localisation or unapproved release asset remains.
- Global multi-seed campaigns satisfy stability and plausibility review.
- Feature/content lock begins.

## Milestone G10 — Beta

- Only bugs, balance, UX, compatibility and performance changes are allowed.
- Save compatibility policy is frozen and tested.
- Minimum/target hardware budgets pass.
- Tutorial and accessibility sessions are complete.
- Crash, exploit and regression burn-down is tracked weekly.

## Milestone G11 — Release Candidate and 1.0

- Clean-install package passes on supported systems.
- Windows signing/Application Control plan is approved.
- Legal/provenance register is complete.
- No blocker or critical defect remains.
- Release notes, known issues, credits, backup/archive and support process are prepared.

## Work That May Run in Parallel

- Historical research packets can be prepared before schema lock, but final data entry should wait when fields may change.
- UI component artwork can progress while systems are built if it uses stable component contracts.
- Audio composition and SFX sourcing can run independently after asset/legal standards are fixed.
- Map provenance replacement and river sourcing should begin immediately because they may become long-lead blockers.
- Performance instrumentation should run throughout; optimisation should not be postponed entirely to Beta.

## Work That Must Not Be Parallelised Prematurely

- Do not enter global trade data before the route/node model is approved.
- Do not author colonial-region content before colonisation/subject rules are stable.
- Do not globally assign HRE/religious content before those schemas and event contracts are locked.
- Do not approve thousands of flags/portraits without a written provenance and review workflow.
- Do not label Phase 9 “Alpha” while mandatory 1.0 pillars are still absent.

