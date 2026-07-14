# 08 — Audit Traceability, Priority Backlog, and Risks

## Purpose

Prove that the new roadmap does not lose unfinished work from the original country-name/map-label audit, and keep the visual critical path priority-based.

The original audit remains the detailed historical record of P0/P1 implementation and evidence. This document is the production authority for its unfinished P2–P4 work.

## Country-Label Audit Migration

| Original item | New production location | Target milestone | Priority | Status |
|---|---|---|---|---|
| P2.1 Disconnected realms, islands, and straits | CL-3.1; CT-4.3 | MV-4 | P1 | Open |
| P2.2 Curved safe label path decision | CL-3.3 | MV-4 | P2 spike | Open |
| P2.3 Map-mode visibility and player toggle | CL-5.1, CL-5.2; RP-4.1 | MV-2/MV-4 | P1 | Open |
| P2.4 Localisation-ready country identity | CL-1.1–CL-1.3 | MV-4 | P1 | Open |
| P2.5 Editorial/historical review | CL-2.1–CL-2.3; CT-5 | MV-4/MV-6 | P1 | Open |
| P2.6 Remove hard-coded map geometry | RP-1.2; CL-6.1; CT-2.1 | MV-1 | P1 | Open |
| P3.1 Zoom-level presentation | CL-4.2, CL-4.3; MO-4 | MV-4/MV-5 | P1 | Open |
| P3.2 Terrain/marker-aware labels | CL-4.1, CL-4.4; MO-1.3 | MV-2/MV-4 | P1 | Open |
| P3.3 Full-name alternate layouts | CL-4.5 | MV-4 | P2 | Open |
| P3.4 Save/replay behaviour for names | CL-1.3; CT-7.3 | MV-4 | P1 | Open |
| P4.1 Untracked script UID policy | CL-7.1; CT-1.2 | MV-0/MV-4 | P2 | Open |
| P4.2 Separate draggable-panel behaviour | CL-7.2 | MV-0/MV-5 | P2 | Open |
| P4.3 Headless-render limitation | CL-7.3; QA headless/rendered policy | MV-0/MV-7 | P1 | Open |
| Colonial/transcontinental visual coverage | CL-6.3; benchmark matrix | MV-4/MV-6 | P1 | Open |
| Additional release platform/resolution coverage | QA compatibility matrix | MV-7 | P1 | Open |
| Hands-on label UX review | Typography Gate and Visual Beta | MV-4/MV-7 | P1 | Open |

## Integrated Priority Backlog

### P0 — Stop-the-line conditions

No known P0 is intentionally scheduled at roadmap creation. Any of the following immediately becomes P0:

- Land, water, or required map layer disappears in a supported build.
- Province selection and visible ownership disagree.
- A country registry/ownership change corrupts or erases valid territory.
- Packaged build omits required map assets.
- Supported GPU/driver has a repeatable crash in normal map use.
- A shipping asset has an unresolved redistribution/legal blocker.

### P1 — Critical path before global visual production

1. MV-0 baseline captures, art bible, reference board, render architecture, hardware, and provenance audit.
2. One authoritative map transform/configuration.
3. Sharp output, sampling/AA decision, texture tier and colour-space policy.
4. Political status semantics for countries, subjects, occupation, uncolonised land, wasteland, and water.
5. Political palette normalization and accessible neighbour separation.
6. Zoom-aware country/province/coast/interaction border hierarchy.
7. Declarative map-mode and overlay composition.
8. Political atlas vertical slice including France/Orléans, Italy, and Iberia.
9. Terrain/normal/material and hydrography vertical slice.
10. Label render-method decision and crispness gate.
11. Runtime localisation service and no-tag fallback validation.
12. Disconnected-realm/strait/island component policy.
13. Dynamic names, save/replay behaviour, and label invalidation.
14. Essential marker replacement and marker/label hierarchy.
15. Shared zoom LOD/culling service.
16. Deterministic map bake orchestration and cross-layer validation.
17. GPU-rendered visual regression and reference-hardware budgets.

### P1 — Critical path before Visual Content Complete

1. Global country editorial/historical review.
2. Global political-status review.
3. Major river/lake/coast production and review.
4. Regional terrain/material production waves.
5. Global label outlier review and visual matrix.
6. Capitals, ports, essential settlements, armies, battles, sieges, and occupation marker coverage.
7. Provenance and licence completion.
8. Global performance/memory delta tracking.
9. Colour-blind, high-contrast, label scale, and reduced-motion settings.

### P2 — Important depth and polish

- Curved safe-label spike and conditional implementation.
- Full-name authored line breaks/leader treatments.
- Label/palette/content review tooling.
- Vegetation scatter.
- Seasonal presentation if it remains in 1.0 scope.
- Fort/infrastructure detail beyond required marker state.
- Optional reflections after water base passes.
- Keyboard/focus navigation enhancements beyond essential paths.
- Shared UI stacking cleanup and script UID policy.

### P3 — Defer first when schedule or budget is threatened

- Weather/cloud layer.
- Ambient trade ships and road traffic.
- Advanced reflections.
- Decorative minor rivers without gameplay/readability value.
- Unique decorative assets for low-importance settlements.
- Curved labels that do not beat straight/hinted labels in review.
- Ultra graphics tier.

## Risk Register

| ID | Risk | Likelihood | Impact | Trigger | Mitigation/owner |
|---|---|---:|---:|---|---|
| MV-R01 | Scope becomes “recreate all EU4/CK2 visuals” | High | Critical | New layer requested without pillar/gate/displaced scope | Enforce non-goals and change control; Product/Production |
| MV-R02 | Global art starts before vertical-slice quality is stable | High | Critical | Multiple regions hand-authored while render rules still change | Freeze global production until MV-2/MV-3 gates; Production |
| MV-R03 | Source assets cannot be redistributed | Medium | Critical | Missing licence/provenance in asset manifest | Source registry and legal gate before integration; Production/Content |
| MV-R04 | Full-world texture stack exceeds VRAM/load budgets | High | High | Texture tiers keep multiplying or all resolutions stay resident | Tier budgets, compression review, tiling/streaming spike; Rendering/Tech Art |
| MV-R05 | Political readability is lost under terrain/detail | High | High | Reviewer cannot identify ownership quickly | Mandatory hierarchy tests and per-mode blending; Art/UX |
| MV-R06 | “Fill every land pixel” produces ahistorical confetti | High | High | Uncolonised/wasteland/indigenous status inferred as random country ownership | Explicit political-status schema and sourced 1444 review; Design/Content |
| MV-R07 | Border and coast AA fix makes text/terrain blurry | Medium | High | Global post-AA chosen without layer comparisons | Controlled AA spike and separate layer strategy; Rendering |
| MV-R08 | Labels look correct in stills but blur/collide in motion | High | High | Screenshot gate passes while pan/zoom review fails | Motion captures, final render-method spike, screen-space collision; UX/Rendering |
| MV-R09 | Localisation breaks layouts and saves late in Beta | High | High | Identity/localisation model deferred until content complete | Complete CL-1 and representative language tests at MV-4; Content/Engineering |
| MV-R10 | Fragmented/subject realms produce misleading labels | High | High | Overlord label spans subject land or colonies distort homeland | Component classes and reviewed realm cases; Design/Labels |
| MV-R11 | Rivers/terrain source data create huge correction workload | High | High | Vertical slice reveals systematic projection/quality errors | Source spike, correction tools, wave throughput metrics; Map Art/Tools |
| MV-R12 | Camera/menu lag returns as visual layers grow | High | Critical | P95 frame or dynamic update budget regresses | Capture every milestone, cull early, batch, incremental updates; Rendering/QA |
| MV-R13 | Shader compilation/import instability blocks production | Medium | High | Godot/driver/import crash or long runtime shader stall | Pin versions, warm/cold tests, shader permutation review; Rendering/QA |
| MV-R14 | Visual goldens become noise and are blindly updated | Medium | High | Large unexplained image diffs routinely accepted | Intentional update record with before/after and ownership masks; QA/Art |
| MV-R15 | One-off country/region exceptions become unmaintainable | High | Medium | Repeated hard-coded tag/coordinate branches | Validated authored hints and reusable outlier rules; Tools/Content |
| MV-R16 | Accessibility arrives after palette/art lock | Medium | High | Colour-only states survive to Beta | Simulations and high-contrast/pattern alternatives at MV-1/MV-2; UX/Art |
| MV-R17 | Dynamic names desynchronise UI, labels, search, and save | Medium | High | Formation/rename updates only one presentation path | One identity service and invalidation bus; Engineering |
| MV-R18 | Rendered tests are confused with dummy headless failures | Medium | Medium | Unsupported headless renderer used as visual release evidence | Split logic/GPU jobs and document host; QA |
| MV-R19 | Province topology/transform changes break old saves and bakes | Medium | Critical | Map dimension/ID changes after content scale-up | Version transforms/stable IDs and explicit migration gate; Tools/Simulation |
| MV-R20 | Visual polish hides gameplay bugs | Medium | High | Screenshot looks plausible while selected/owned data differs | Exact ID/ownership masks and interaction tests; QA |

## Risk Escalation Rules

- Critical-impact risks are reviewed at every milestone gate.
- Any trigger that threatens ownership correctness, legal distribution, supported-hardware stability, or save compatibility blocks the gate.
- A mitigation is incomplete without an accountable role, measurable signal, and fallback.
- A deferred visual feature must name what remains shippable without it.
- Risks that become defects move into the defect system with severity; they do not disappear from reporting.

## Decision Record Queue

Create formal decision records for:

1. EU4-led political atlas with project-original asset language.
2. Primary renderer and graphics fallback.
3. Authoritative map projection/transform.
4. Texture resolution/tile/streaming strategy.
5. Anti-aliasing and sampling.
6. Country/subject/uncolonised/wasteland political semantics.
7. Border generation and screen-space line policy.
8. Label render method.
9. Curved-label go/no-go.
10. Dynamic country names and save ownership.
11. River source/representation.
12. Water quality/reflection scope.
13. Seasonal/weather 1.0 scope.
14. Generated asset and UID repository policy.
15. Reference hardware and visual performance budgets.

## Waiver Policy

A P1 item may not be silently downgraded. A release waiver must include:

- Player impact.
- Affected regions, modes, settings, and saves.
- Reproduction and screenshots/captures.
- Workaround or fallback.
- Performance/legal/accessibility implications.
- Owner and post-release target.
- Approval from Product, relevant discipline, and QA.

P0 items cannot be waived for Release Candidate.

## Completion Statement

This roadmap has absorbed the unfinished label-audit backlog when every row in the migration table is complete, explicitly deferred with an approved waiver, or superseded by a documented decision that passes the same original acceptance intent.

