# 05 — Release Readiness

Release readiness is a separate production track. A feature-rich build is not shippable until performance, compatibility, balance, onboarding, legal and operational gates pass.

## Global AI

### Current state

Deterministic AI can play the Iberian vertical slice and use the same command API as the player. This does not prove worldwide scheduling or competence in systems that do not exist yet.

### Required work

- Global AI scheduler with explicit daily/monthly CPU budgets.
- Naval, trade, colonisation, HRE, Reformation, coalition and expanded diplomacy reasoning.
- Regional priorities, threat maps and long-distance opportunity costs.
- Anti-thrashing rules and cooldowns for expensive decisions.
- Explainable decision traces and reproducible seed reports.
- Difficulty settings that change priorities/resources transparently rather than introducing hidden instability.
- Multi-seed outcome distributions for 10-, 50-, 100- and 256-year runs.

### Exit gate

The global AI must finish the full campaign within simulation budgets, avoid systematic bankruptcy/stagnation, use every core pillar competently and produce varied but plausible outcome distributions.

## Balance and Tuning

- Define target bands for treasury, manpower, army/fleet size, technology pace, revolt frequency and territorial change.
- Create telemetry reports for percentile outcomes, not just averages.
- Run controlled A/B parameter sets with identical seeds.
- Maintain exploit tests for loans, sieges, peace costs, coalitions, trade and colonisation.
- Balance small-country survival without forcing historical outcomes.
- Record every major tuning change and its evidence.

### Exit gate

No known dominant strategy invalidates a major pillar, target outcome bands are approved across multiple seeds and balance changes no longer require schema or architecture changes.

## Tutorial and Onboarding

- First-launch settings and accessibility setup.
- Contextual tutorial for camera, selection, time and map modes.
- Guided first-month country loop: economy, construction, diplomacy and army orders.
- War declaration, battle, siege and peace tutorial.
- Later contextual teaching for trade, naval, colonisation, HRE/religion and characters.
- Glossary/encyclopaedia links from tooltips.
- Safe tutorial reset and skip/resume controls.

### Exit gate

Unassisted target players must complete the approved first-session objectives, understand why time is paused and know what to do next. Completion, abandonment and confusion points must be measured.

## QA and Compatibility

- Unit, integration, deterministic replay and save round-trip suites.
- Save migration tests across every supported schema transition.
- 1444–1700 world soaks across fixed seed sets.
- UI layout matrix for resolutions, scaling and localisation expansion.
- GPU/CPU matrix covering minimum, target and high-end hardware.
- Windows packaging and Application Control/code-signing plan.
- Crash capture, structured logs and reproducible bug-report bundle.
- Input, alt-tab, window mode, monitor/DPI and clean-install testing.
- Corrupt/missing data and interrupted-save recovery tests.

### Exit gate

Zero open release blockers, blocker/critical crash rates within the approved threshold, supported hardware meets performance budgets and a clean machine can install, launch, save, reload and uninstall correctly.

## Performance Budgets

Final budgets must be approved, but the release gate should at minimum track:

| Area | Required measurement |
|---|---|
| Map rendering | P50, P95 and max frame time while panning/zooming in representative dense regions. |
| Labels/markers | Draw count, CPU update time, GPU time, memory and collision/clustering cost by zoom. |
| Simulation | Daily/monthly tick P50/P95, worst country, worst system and scheduled AI cost. |
| Saves | Save/load duration, file size, migration time and peak memory. |
| World soak | Real time to simulate 10/100/256 years and memory growth over time. |
| Front-end | Menu/nation-selection load time and first interactive frame. |

## Legal, Provenance and Historical Review

### Known blockers

- Province-map and definition-map provenance is not fully approved for commercial release.
- Water-source provenance/import authority requires resolution.
- Rivers do not yet have an approved production source.
- Most historical shields remain missing or unapproved.
- Future music, SFX, portraits and UI art will require explicit rights records.

### Required work

- Asset register with creator/source, licence, permitted use, transformations and approval status.
- Project-owned replacements for any asset without commercially defensible provenance.
- Historical review records for disputed ownership, rulers, names, subjects and symbols.
- Third-party notice and credits generation from the asset/dependency registry.
- Code-signing plan for Windows builds if required by the distribution environment.

### Exit gate

Every shipped asset and dependency must be traceable and approved; no blocker may be waived by assumption.

## Late-Campaign Scope

The current 1.0 endpoint is 1 January 1700. The 1700–1821 period remains a later expansion and must not silently enter the 1.0 critical path. However, 1444–1700 still requires full late-16th and 17th-century technology, units, religion, trade, government and event coverage.

## Release Stages

1. **Global Alpha:** all 1.0 pillars integrated; placeholder content/art allowed but explicitly tracked.
2. **Content Complete:** every planned country/region and core historical arc approved.
3. **Beta:** feature/content lock; balance, UX, optimisation and bug work only.
4. **Release Candidate:** packaging, legal, accessibility, compatibility and blocker gates pass.
5. **1.0:** signed/approved build, release notes, support process and archived source/content baseline.
