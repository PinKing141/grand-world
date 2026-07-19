# G1 Finish-Line Roadmap

**Status:** Active - G1 remains blocked at P1.
**Purpose:** Complete the remaining naval work proven open by the 2026-07-18 release-gate audit.
**Authority:** This folder is the authoritative board for remaining G1 work. The original N0-N6 documents remain the design authority and historical record.
**Restriction:** Do not begin C1 Discovery Authority until FL1-FL9 are complete and the final gate verdict is PASS.

## What is already trusted

The deterministic simulation core is not being reopened without a failing test or an approved design change. Fleet construction and logistics, transport reservations, movement, interception, combat, retreat, disembarkation, blockade effects, lifecycle cleanup, save migration, the destructive matrix, the 290-fleet logistics fixture, and the 100-seed Channel replay currently pass.

Every finish-line change must preserve those results.

## Status definitions

- `Not started`: no implementation or current evidence.
- `In production`: implementation is being changed; the slice is not gate-safe.
- `Validation`: implementation exists and targeted tests pass, but required rendered, manual, stress, or full-suite evidence is incomplete.
- `Complete`: every exit condition is supported by dated evidence.
- `Blocked`: progress requires an unresolved dependency or decision.

## Finish-line slices

| Slice | Work packet | Status | Depends on | Completion result |
|---|---|---|---|---|
| [FL1](01_FL1_MAP_PRESENTATION.md) | Fleet, route, battle and blockade map presentation | Validation (all named automatable gaps closed: merge/split selection, cancellation/peace/merge/load route reconciliation, blockade attacker attribution and the persistent-cue/on-demand-coast-overlay contract; rendered/manual acceptance remains FL6 work - see evidence) | Existing authoritative naval queries | The player can see and select naval activity on the map. |
| [FL2](02_FL2_FLEET_MANAGEMENT.md) | Complete player fleet-management workflow | Complete (FL2.1-FL2.6 all complete and verified, plus the transport-capacity, disembark-cancellation, and mission-picker/save-validation correctness fixes found along the way - see evidence) | Existing fleet commands; FL1 selection contract | Every supported fleet action is safely available from UI. |
| [FL3](03_FL3_NAVAL_AI_COMPLETION.md) | Threat, organisation, basing, reinforcement and transport AI | Complete (closure audit corrected an overstated `Validation` line; all six sub-scopes FL3.1-FL3.6 and all four "Automated verification" claims (battle arbitration, recovery matrix, trace-neutrality, performance budget) complete - threat/opportunity map, full posture spectrum/ship mix with the ship-construction technology gate and navy maintenance command, reinforcement/home-port/danger-aware-routing with split-based organisation and confirmed reserve-fleet availability, the full 8-mission tactical set with event-triggered replanning, escort lifecycle (proactive reservation and follow-the-voyage), and explainability fields/counter - no remaining named gap, see evidence) | Existing deterministic naval AI and commands | AI can autonomously execute the complete naval loop. |
| [FL4](04_FL4_STARTING_CONTENT_AND_LEADERS.md) | Reviewed starting forces, admirals and provenance | Complete (five source-tracked starting fleets with full provenance, a generated content report, and an explicit no-starting-admirals policy decision - see evidence) | Existing placeholder starting fleet loader | Starting naval content is reviewable and release-ready. |
| [FL5](05_FL5_STRATEGIC_CONTRACT_CLOSEOUT.md) | Trade-protection output and downstream contract lock | Complete (FL5.1 trade-protection query, FL5.2 blockade/coastal contract audit, FL5.3 downstream boundary lock all done - see evidence) | Existing blockade/coastal effect queries | Naval outputs consumed by later pillars are explicit and stable. |
| [FL6](06_FL6_RENDERED_AND_ACCESSIBILITY_ACCEPTANCE.md) | Resolution, input, accessibility and hardware checks | Validation (automatable slice complete: a real off-canvas panel bug found and fixed, plus rapid-click/duplicate-command safety proven; the acceptance walkthrough, keyboard-only UX, colour-vision review, and hardware/GPU checks all still need a human - see evidence) | FL1 and FL2 | The complete naval interface is usable on supported targets. |
| [FL7](07_FL7_GLOBAL_NAVAL_STRESS.md) | Simultaneous global naval stress and performance | Validation (named dense-presentation and combined eight-country simultaneous headless fixtures now pass, including two reload continuations matching the uninterrupted checksum; rendered mode and approved low-end/target-hardware budgets remain open - see evidence) | FL1-FL3 | Full naval load remains deterministic and inside budgets. |
| [FL8](08_FL8_PROJECT_GATE_RECOVERY.md) | Resolve six remaining project-wide failures | In production (FL8.1, FL8.3 complete; FL8.2, FL8.4, FL8.5, FL8.6 all hardware-blocked - each reproduced and profiled, no code defect found, all four need real target-hardware validation - see evidence) | May run alongside FL1-FL7 | The canonical full suite is green. |
| [FL9](09_FL9_FINAL_RELEASE_GATE.md) | Final audit, release evidence and G1 decision | Blocked | FL1-FL8 | G1 is either approved with evidence or remains explicitly blocked. |

## Recommended execution order

```text
FL1 map presentation
  -> FL2 fleet management
  -> FL6 rendered/accessibility acceptance

FL3 naval AI --------------------\
FL4 starting content/leaders -----+-> FL7 global naval stress
FL5 downstream contract ----------/

FL8 project gate recovery may proceed alongside the feature slices.

FL1-FL8 complete -> FL9 final release gate -> only then consider C1.
```

Only one dependency-heavy slice should be changed at a time. FL4, FL5 and targeted FL8 investigations may proceed independently when they do not alter shared naval state.

## Rules for every slice

1. Reproduce or record the missing behavior before implementation.
2. Use authoritative simulation commands and queries; UI and AI must not mutate registries directly.
3. Add focused automated tests for state-changing behavior.
4. Test save/load and deterministic replay whenever authoritative state changes.
5. Record performance when work adds per-day, per-fleet, per-zone, or rendered-frame cost.
6. Run the targeted naval regression set before marking `Validation`.
7. Add dated evidence only after the named checks pass.
8. Do not weaken assertions, raise timeouts, or revise budgets without measurement and an explicit rationale.

## Completion rule

This roadmap is complete only when FL1-FL8 are `Complete`, FL9 records a clean targeted naval run and clean canonical full suite, no P0/P1 issue remains, and the 100-seed Channel scenario again reports zero desyncs, invalid references, leaked reservations, duplicated armies, or stranded armies.
