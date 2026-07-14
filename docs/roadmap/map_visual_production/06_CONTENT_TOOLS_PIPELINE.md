# 06 — Content and Tools Pipeline

## Outcome

Make global map quality reproducible. A reviewed source change should flow through deterministic import, bake, validation, in-game review, and packaged-build verification without hand-editing generated output.

## Pipeline Principles

- Source data and generated runtime assets are different and clearly labelled.
- Generated files are never the only copy of an authored decision.
- Stable IDs survive display-name, colour, and art changes.
- Every bake records tool version, input hashes, configuration, and output hashes.
- Validation fails loudly on missing/duplicate/ambiguous data.
- Regional production scales through tools and review templates, not repeated shader changes.
- Historical/geographic uncertainty is recorded rather than silently guessed.
- Shipping rights and attribution are first-class data.

## Proposed Source-to-Game Flow

~~~text
Approved source datasets + authored overrides
        ↓
Import and normalize
        ↓
Schema validation
        ↓
Derived bakes (IDs, distance fields, labels, terrain, rivers, LOD)
        ↓
Cross-layer alignment validation
        ↓
Godot import/package validation
        ↓
Automated logic + rendered capture tests
        ↓
Regional art/historical/UX review
        ↓
Approved content version and build
~~~

## Epic CT-1 — Map Source Registry

### CT-1.1 Create a map asset manifest — P1 / M

For each source and output record:

- Stable asset ID and semantic type.
- Source path/URL reference and licence.
- Author/organisation and attribution requirement.
- Projection, geographic extent, dimensions, bit depth, channels, and colour space.
- Allowed transformations and redistribution status.
- Authored overrides.
- Generating tool/command and version.
- Input/output hashes.
- Review state and owner.

**Done when**

- Every shipping map texture/data file resolves to an approved source or an internally authored record.
- A release report lists licences and provenance automatically.

### CT-1.2 Define generated-asset repository policy — P1 / S

Decide which derived files are committed, which are built in CI, and which are Godot import cache only.

**Done when**

- Fresh clone, clean bake, editor import, tests, and export reproduce required assets.
- UID and `.import` file policy is consistent.
- Generated files cannot drift silently from source hashes.

## Epic CT-2 — Unified Map Configuration

### CT-2.1 Create authoritative map metadata — P1 / M

Minimum fields:

- Projection type and wrap policy.
- Source pixel dimensions.
- World-space dimensions/scale.
- Land/sea conventions.
- Height scale/sea level.
- Province colour/ID rules.
- Texture tier dimensions.
- Coordinate transform version.
- Current content/bake version.

All terrain, label, graph, marker, shader, selection, and testing tools consume this metadata instead of duplicating constants.

### CT-2.2 Add cross-layer alignment validator — P1 / L

Validate:

- Province ID versus land/water mask.
- Ownership versus valid country registry.
- Terrain/height/normal dimensions and transform.
- Coast/lake/river continuity.
- Province centres and adjacency.
- Label territory bake and map transform.
- Port/coastal province relationship.
- Capital/settlement province location.
- Wasteland/impassable/colonisable status.

**Done when**

- Reports identify exact pixel/province/asset responsible.
- Critical mismatches block local full tests and CI.

## Epic CT-3 — Deterministic Bake Tools

### CT-3.1 Standardize command-line interfaces — P1 / M

Every bake supports, where appropriate:

- `--check` without modifying files.
- Explicit source/config/output paths.
- Deterministic seed/version.
- Machine-readable report.
- Human-readable summary.
- Non-zero exit on failure.
- Incremental rebuild based on input hashes.
- `--force` for controlled full rebuild.

### CT-3.2 Build one orchestration command — P1 / L

The orchestration layer runs dependency order for:

- Country registry.
- Province/ownership data.
- Province graph/straits.
- Terrain/height/normal/material masks.
- Coast/border distance fields.
- Rivers/lakes.
- Label territory and placement metadata.
- Marker/settlement data.
- Godot import readiness.

**Done when**

- Developers cannot accidentally bake labels against one map revision and terrain against another.
- Partial and full rebuild timing is measured.

### CT-3.3 Add bake golden fixtures — P1 / M

Use tiny synthetic maps to verify exact behaviours such as islands, holes, straits, concavity, coast edges, river mouths, duplicate province colours, and component classification.

## Epic CT-4 — Regional Production Workflow

### CT-4.1 Define region packages — P1 / M

Each production wave has:

- Region bounds and province list.
- Country/relationship setup.
- Terrain/climate/height inputs.
- Rivers/lakes/coasts.
- Capitals/ports/settlements.
- Label outliers and authored hints.
- Reference camera bookmarks.
- Historical/geographic sources.
- Known simplifications and open questions.
- Review checklist and approval state.

### CT-4.2 Establish a four-pass review — P1 / M per wave

1. **Data review:** IDs, ownership, transforms, adjacency, and completeness.
2. **Historical/geographic review:** 1444 setup, names, political status, terrain, rivers, and settlement importance.
3. **Art/UX review:** hierarchy at three zooms and required modes.
4. **Technical QA:** performance, memory, export, visual baselines, and regression.

No single review substitutes for another.

### CT-4.3 Track outliers explicitly — P1 / S ongoing

Outlier classes:

- Microstate/one-province country.
- Fragmented island realm.
- Transcontinental realm.
- Very long localised name.
- Dense border cluster.
- Large wasteland/uncolonised region.
- Complex delta/lake/river network.
- Map-edge/seam province.
- High marker density.

Every new outlier either fits an existing rule or creates a reviewed reusable rule—not a hidden one-off code branch.

## Epic CT-5 — Historical and Editorial Content

### CT-5.1 Add provenance fields to country/province review — P1 / L

For active 1444 content capture source, reviewer, confidence, date, notes, and dispute status. Separate historical correctness from technical validity.

### CT-5.2 Create naming review queue — P1 / M

Integrate the catalogue tasks from [04 — Country Labels and Localisation](04_COUNTRY_LABELS_LOCALISATION.md), including spelling candidates, spacing/CamelCase, diacritics, adjectives, formal names, aliases, companies, formables, and future tags.

### CT-5.3 Define political-status review — P1 / L

Review whether each 1444 region is:

- Sovereign country territory.
- Subject/appanage/personal-union territory.
- Occupied or disputed at start.
- Indigenous polity represented as a country.
- Inhabited/uncolonised gameplay territory.
- Impassable/wasteland.
- Ocean/lake/non-playable.

This prevents the visual map from treating “every non-ocean pixel must have a random country colour” as a historical rule.

## Epic CT-6 — Authoring and Preview Tools

### CT-6.1 Add map-layer inspector — P2 / L

Development overlay should inspect at cursor:

- Pixel/world coordinate.
- Province ID/name.
- Owner/controller/subject relation.
- Political status.
- Terrain/biome/elevation/slope.
- River/lake/coast status.
- Label component and priority.
- Marker/settlement IDs.
- Active map-mode layers and sampled colours.

### CT-6.2 Add camera bookmark/capture tool — P1 / M

Bookmarks store map position, zoom, rotation/tilt, mode, selected entity, resolution, graphics tier, and expected visible layers.

**Done when**

- Art and QA can reproduce review images exactly.
- Visual-regression capture uses the same bookmarks.

### CT-6.3 Add palette and border preview — P2 / M

Preview neighbouring colours, Oklab distances, colour-vision simulations, terrain blend, and border treatments before a full bake.

### CT-6.4 Add label review overlay — P2 / L

Show owned sample region, components, selected primary component, oriented bounds, collision footprint, priority, culling reason, authored hints, and localisation string.

## Epic CT-7 — CI and Change Management

### CT-7.1 Add tiered validation jobs — P1 / L

Suggested jobs:

- Fast data/schema check.
- Deterministic bake check.
- Godot logic-headless smoke.
- Rendered benchmark capture on supported GPU host.
- Packaged export/startup.
- Scheduled full visual matrix and global performance run.

### CT-7.2 Require intentional golden updates — P1 / S

Visual baseline changes require:

- Before/after images.
- Reason and linked task/decision.
- Reviewer approval.
- Performance delta.
- Confirmation that ownership/data did not change accidentally.

### CT-7.3 Version map content and save dependencies — P1 / M

Store content version and transform/schema version in saves. A changed province topology, stable ID, or dynamic-name schema requires an explicit migration/compatibility decision.

## Pipeline Exit Criteria

- All shipping map layers reproduce from documented source and tools.
- One authoritative transform/config drives every layer.
- Data, alignment, licence, and generated-output validators pass.
- A new region can reach reviewed in-game quality without editing runtime shader code.
- Global production throughput and defect rates are measured after each wave.
- Country names, political status, terrain, rivers, and settlements have review/provenance status.
- CI distinguishes fast logic, rendered GPU, export, and scheduled global jobs.

