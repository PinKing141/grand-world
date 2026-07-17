# Grand World Completion Audit and Revised Roadmap

**Audit date:** 15 July 2026  
**Campaign scope assessed:** 11 November 1444 to 1 January 1700  
**Target:** a global, pauseable, real-time grand-strategy game with the breadth and readability expected from the EU4/CK2 genre

This roadmap converts the project-completion audit into an actionable production plan. It deliberately separates four different meanings of “done”:

1. A system exists in code.
2. The system forms a playable loop.
3. The system has representative vertical-slice content.
4. The system has global, reviewed, release-quality content and presentation.

That distinction matters because Grand World already has a broad playable foundation, but many systems are still thin loops and most countries do not yet have authored historical depth.

## Executive Assessment

| Measurement | Estimated completion | Meaning |
|---|---:|---|
| Core technical architecture | 80–85% | Deterministic state, time, saves, commands, land movement, economy, war, characters, UI shell and automated testing exist. |
| Iberian vertical slice | 65–75% | The regional loop is substantially playable, but still needs balance, UX, art and content refinement. |
| Full EU4-scale 1444–1700 product | 25–35% | Major pillars and most worldwide content remain. |
| Release-ready 1.0 | 20–25% | Global content, final UX, audio, tutorial, legal provenance, compatibility and balance are incomplete. |
| Worldwide authored historical content | 2–5% | Frameworks exist, but authored coverage is concentrated in roughly five Iberian countries. |
| Final map/UI/audio presentation | 35–45% | The strategic map and interface have advanced substantially; final art, river, audio and accessibility work remain. |

These are production-planning estimates, not a claim that every task has been measured to an exact percentage.

## Priority Order

The next critical-path work is not simply “add more countries.” The project must first decide and build the global pillars that every country and AI will depend on.

| Priority | Workstream | Production outcome |
|---|---|---|
| P0 | Scope and architecture gate | Lock the 1.0 definition, data ownership and interfaces for all missing global pillars. |
| P0 | Naval and maritime warfare | Fleets, transport, blockades and naval battles make the world map function globally. |
| P0 | Exploration and colonisation | Unknown-world discovery, colonies and colonial subjects create the Age of Discovery loop. |
| P0 | Trade network | Province production flows through nodes/routes, merchants and trade power. |
| P0 | HRE and Reformation | The central European political and religious arcs become mechanical rather than decorative. |
| P1 | Existing-system depth | Warfare, diplomacy, estates, governments, economy and technology become strategically rich. |
| P1 | Global content pilot | A second non-Iberian region proves that content tools and schemas scale before mass production. |
| P1 | Global content waves | Countries, rulers, claims, ideas, governments, events and decisions receive reviewed coverage. |
| P2 | Presentation, audio and onboarding | Final UI art, portraits, rivers, map polish, alerts, tutorial and sound make the game understandable and marketable. |
| P2 | Global Alpha/Beta/RC | Balance, world-scale AI, compatibility, performance, legal clearance and release hardening. |

The P0 naval workstream is expanded into detailed, independently reviewable slices in the [Naval and Maritime Implementation Roadmap](../naval/README.md).

## Split Roadmap

Read the files in this order:

1. [Status Baseline](00_STATUS_BASELINE.md) — what is already implemented and what “complete” means.
2. [Missing Core Pillars](01_MISSING_CORE_PILLARS.md) — naval, colonisation, trade, HRE and Reformation.
3. [Global Historical Content](02_GLOBAL_HISTORICAL_CONTENT.md) — how to scale authored content from Iberia to the full world.
4. [Existing-System Depth](03_EXISTING_SYSTEM_DEPTH.md) — warfare, diplomacy, estates, government, economy and technology.
5. [Presentation, UI and Audio](04_PRESENTATION_UI_AUDIO.md) — map, interface, portraits, rivers, notifications, front-end and sound.
6. [Release Readiness](05_RELEASE_READINESS.md) — AI scale, balance, tutorial, QA, performance, compatibility and legal gates.
7. [Delivery Sequence and Gates](06_DELIVERY_SEQUENCE_AND_GATES.md) — the revised production order and measurable milestone exits.
8. [Metrics and Evidence](07_METRICS_AND_EVIDENCE.md) — current content counts, test results, performance measurements and known blockers.

## Scope Correction to the Existing Roadmap

The existing Phase 8 milestone correctly describes its result as a complete **thin-loop system set**. It does not mean the global product is Alpha-complete in the normal production sense. Naval warfare, colonisation, the trade network, HRE mechanics and the Reformation are still absent or only represented by underlying data.

Therefore, Phase 9 should not begin as unrestricted worldwide content entry. It should be preceded by the P0 Global Pillars gate in [Delivery Sequence and Gates](06_DELIVERY_SEQUENCE_AND_GATES.md). Otherwise, global content will be authored against incomplete schemas and may need expensive rework.

## Roadmap Governance Rules

- A feature is not “complete” because a class, data row or UI panel exists; its gameplay loop, AI use, save compatibility, tests and player feedback must also pass.
- A country is not “content complete” until its ruler history, government, culture/religion, cores/claims, national direction, historical relations and validation status are all recorded.
- Every global-content row must carry a source/provenance status and reviewer status.
- Every new core system must work through the deterministic command/state architecture and be covered by save/load and replay tests.
- Global content production may begin only after the schemas and acceptance gates for the related system are locked.
- Release status is determined by evidence in tests, builds and review records—not by roadmap prose alone.

## Companion Document

The same audit and roadmap are also maintained as a formatted Word report:

- [Grand World Completion Audit and Revised Roadmap.docx](GRAND_WORLD_COMPLETION_AUDIT_AND_REVISED_ROADMAP.docx)
