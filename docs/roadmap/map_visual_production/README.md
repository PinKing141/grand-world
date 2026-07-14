# Strategic Map Visual Production Roadmap

**Roadmap type:** Cross-cutting map art, rendering, content, UX, and release track  
**Primary release dependency:** Phase 9 — Global Scale, Alpha, Beta, and 1.0  
**Current status:** MV-0 Direction Lock in progress; baseline/audit implemented, Visual Greenlight not yet passed  
**Target experience:** A clear, handsome, historically grounded political atlas that remains readable during real-time play from 1444 to 1700  
**Primary reference family:** Europa Universalis IV for political-map hierarchy; Crusader Kings II for terrain, holdings, and regional character where those ideas support this game's country-first design  
**Successor to:** The open P2–P4 work in [Country Names and Map Labels — Priority Audit](../COUNTRY_NAMES_MAP_LABELS_AUDIT.md)

## Mission

Bring the world map from a technically functional strategy prototype to a release-quality grand-strategy presentation. The result must communicate ownership, geography, hierarchy, and player intent immediately while still rewarding close inspection.

This roadmap treats the map as a complete product surface, not as a single shader. It coordinates:

- Art direction and visual language.
- Political colours, borders, overlays, and selection feedback.
- Terrain, relief, biomes, water, coasts, rivers, and climate cues.
- Country labels, province labels, localisation, and map-mode visibility.
- Armies, capitals, settlements, ports, and other map objects.
- Camera-dependent level of detail and presentation transitions.
- Asset generation, historical review, validation, and licensing.
- GPU, CPU, memory, loading, export, accessibility, and visual-regression gates.

## Honest Starting Point

The project already has a world-scale map, province ownership, terrain classification, political colours, borders, camera controls, map modes, country labels, a deterministic simulation, and automated tests. Those are valuable foundations.

The present image is nevertheless closer to a political-data renderer over a softened biome texture than to a finished Paradox-style strategy map. The largest gaps are:

1. No approved art bible or reference-quality vertical slice.
2. Political colours are too saturated and borders are too heavy at common zooms.
3. Coastlines can read as a bright cyan halo instead of a natural land-water transition.
4. Terrain lacks a layered material language, authored normal detail, rivers, vegetation, and settlements.
5. Water is visually static and lacks coastal depth, controlled motion, and hierarchy.
6. Map information does not yet change enough by zoom level.
7. Labels are technically capable but still require sharper rendering, content review, localisation, realm-component rules, and mode-aware presentation.
8. The full-world setup can become visual confetti because political ownership and uncolonised/wasteland semantics are not yet art-directed as a hierarchy.
9. Rendering budgets and reference-hardware captures are not yet established for the final stack.

## Product Pillars

### 1. Readable before decorative

At a glance, a player must distinguish country, subject, occupied territory, selected territory, wasteland, uncolonised land, and water. Decorative detail must never erase political information.

### 2. Geographic credibility

Sahara, Sahel, Alps, Baltic, Nile, Andes, monsoon Asia, steppe, and tropical regions must feel materially different without pretending to be a satellite image.

### 3. Stable strategic hierarchy

Country borders dominate province borders; selected and war-state overlays dominate passive decoration; labels defer to interaction markers; debugging modes can remove presentation layers.

### 4. Cohesion across zoom

The map must have intentional wide, regional, and close presentations. Elements fade, simplify, or appear through controlled LOD rules rather than popping or scaling without limit.

### 5. Data-driven and reproducible

Political ownership, names, terrain classes, rivers, label hints, and generated textures must come from authoritative data with deterministic bake steps and validation.

### 6. Shippable at global scale

The complete map stack must stay within frame, memory, load, export, and compatibility budgets on defined reference hardware.

## Scope

### Included for 1.0

- Political, terrain, and debug/ID presentations.
- Country/province border hierarchy.
- Ownership, subject, occupation, selection, and diplomatic overlays.
- Country labels and required supporting province/capital labels.
- Terrain biomes, macro relief, normal detail, climate cues, and wasteland treatment.
- Oceans, coastal shelves, lakes, and major rivers needed for geographic readability.
- Capitals, settlements, ports, armies, battles, and essential map markers.
- Zoom LOD, culling, transition rules, and user settings.
- Colour-blind-safe alternatives and label controls.
- Visual regression, performance captures, content validation, and packaged-build testing.

### Explicit non-goals for this roadmap

- Copying EU4 or CK2 assets, shaders, exact palettes, fonts, or proprietary content.
- Photorealistic terrain or a globe projection for 1.0.
- A fully simulated 3D city for every province.
- Province-level seasonal simulation unless the gameplay system requires it.
- Unique handcrafted art for every one of the roughly one thousand country definitions.
- Expanding the campaign beyond 1700.
- Replacing simulation architecture that does not affect map presentation.
- Redesigning the general HUD/menu skin; only map-attached controls, markers, tooltips, and accessibility settings required by this visual stack are included.

## Roadmap Package

| Document | Purpose |
|---|---|
| [00 — Art Direction Bible](00_ART_DIRECTION_BIBLE.md) | Target look, hierarchy, zoom language, references, and approval process |
| [01 — Delivery and Milestones](01_DELIVERY_AND_MILESTONES.md) | Critical path, work packages, dependencies, responsibilities, and gates |
| [02 — Rendering and Political Readability](02_RENDERING_POLITICAL_READABILITY.md) | Render architecture, palette, borders, overlays, ownership semantics, and anti-aliasing |
| [03 — Terrain, Water, and World Detail](03_TERRAIN_WATER_WORLD_DETAIL.md) | Relief, biomes, hydrography, coastlines, water, climate, and environmental detail |
| [04 — Country Labels and Localisation](04_COUNTRY_LABELS_LOCALISATION.md) | All remaining label-audit work, name content, typography, placement, modes, and saves |
| [05 — Map Objects, Atmosphere, and LOD](05_MAP_OBJECTS_ATMOSPHERE_LOD.md) | Capitals, settlements, ports, units, effects, fog, seasons, and zoom-dependent presentation |
| [06 — Content and Tools Pipeline](06_CONTENT_TOOLS_PIPELINE.md) | Authoritative sources, import/bake workflow, review, validation, provenance, and change control |
| [07 — Performance, QA, and Release Gates](07_PERFORMANCE_QA_RELEASE_GATES.md) | Budgets, test matrix, visual baselines, accessibility, compatibility, and ship criteria |
| [08 — Audit Traceability and Risks](08_AUDIT_TRACEABILITY_RISKS.md) | Mapping from old audit items to this plan, risk ownership, and deferral policy |
| [MV-0 Working Package](mv0/README.md) | Current captures, generated audit, references, zoom matrix, technical decisions, and gate status |

## Milestone Summary

| Milestone | Outcome | Gate |
|---|---|---|
| MV-0 Direction Lock | Approved visual target, benchmark captures, technical constraints, and reference scenes | Visual Greenlight |
| MV-1 Readability Foundation | Stable render path, sharp output, border hierarchy, palette rules, and ownership semantics | Readability Gate |
| MV-2 Political Atlas Slice | Western Europe/Iberia demonstrates final political mode quality at all zooms | Political Vertical Slice |
| MV-3 Geographic Material Slice | Terrain, relief, water, coasts, and rivers reach representative quality in selected biomes | Environment Gate |
| MV-4 Labels and Identity | Country names, layout, localisation model, and map-mode rules are content-complete | Typography Gate |
| MV-5 Living Map | Essential map objects, feedback, atmosphere, and LOD are integrated without clutter | Presentation Alpha |
| MV-6 Global Production | All regions use the approved pipeline; outlier regions and countries are reviewed | Visual Content Complete |
| MV-7 Optimisation and Beta | Global scale meets performance, accessibility, compatibility, and regression budgets | Visual Beta |
| MV-8 Release Candidate | Legal, content, technical, packaged-build, and hands-on reviews pass | Visual RC |

## Critical Path

~~~text
Reference captures and art bible
        ↓
Render-path and output-quality decisions
        ↓
Political palette, ownership semantics, and border hierarchy
        ↓
Representative political vertical slice
        ↓
Terrain + relief + hydrography vertical slice
        ↓
Typography/localisation + map-object hierarchy
        ↓
Global content production and validation
        ↓
Optimisation, accessibility, compatibility, and release review
~~~

Labels, tools, profiling, and provenance work begin early, but no global art-production pass should begin until the relevant vertical-slice gate is approved.

## Priority Policy

| Priority | Meaning in this roadmap | Release treatment |
|---|---|---|
| P0 | Corrupt ownership/identity, broken rendering, unusable performance, or invalid distributable asset | Stop the line; resolve immediately |
| P1 | Required for the active visual milestone or Phase 9 release quality | Must close before the relevant gate |
| P2 | Important depth, tooling, or polish with a controlled fallback | Schedule before Visual Content Complete where possible |
| P3 | Optional polish or advanced treatment | Defer explicitly if it threatens the critical path |

## Definition of Ready

A map-visual feature may enter production only when:

- Its player-facing purpose and target zoom levels are written down.
- A reference, mock-up, or benchmark capture exists.
- Ownership of design, implementation, content, and validation is explicit.
- Input assets and data authority are known.
- Interactions with selection, labels, markers, map modes, saves, and accessibility are identified.
- CPU, GPU, memory, and content-cost implications are estimated.
- Acceptance criteria can be evaluated in a packaged build.

## Definition of Done

A map-visual feature is not done merely because it looks correct in one editor view. It is done when:

- Approved benchmark scenes match the art direction at wide, regional, and close zoom.
- Political information remains correct and interactive.
- No generated file has an untracked or ambiguous source.
- Automated validation and visual baselines pass.
- Reference-hardware frame, memory, load, and update budgets pass.
- Required accessibility alternatives exist.
- Save/load, ownership change, map-mode switch, resize, export, and long-session behaviour are verified where applicable.
- Content and licensing provenance are recorded.
- Art, design, engineering, and QA sign off at the corresponding milestone gate.

## Relationship to the Main Roadmap

This is a cross-cutting production track, not a new gameplay phase between Phase 8 and Phase 9. It supports Phase 8 Alpha validation and becomes a direct dependency of Phase 9 Content Complete, Beta, and Release Candidate. Gameplay work may continue while MV-0 and MV-1 are in progress, but global visual-content production must respect the vertical-slice gates in this package.
