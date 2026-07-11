# Phase 3 — World Graph, Pathfinding, and Movement

## Mission

Transform the province map into a traversable strategic world and prove that armies can move through it using deterministic rules.

## Production Gate

Movement Gate.

## Implementation Status (July 2026)

Implemented in the current build:

- **3A Canonical graph.** `tools/map_graph/build_province_graph.py` is the single adjacency authority: horizontal/vertical pixel comparisons only (diagonal corner contact never connects), no edge wrapping, symmetric storage with shared-border pixel counts, land/sea neighbour split, coastal flags, bounding boxes, pixel areas, per-province movement class, and geographic classification (land/water/impassable). Baked to `assets/province_graph.json`; the runtime (`scripts/simulation/province_graph.gd`) only loads, never scans.
- **3B Overrides and validation.** `tools/map_graph/graph_overrides.csv` supports add_connection, remove_connection, mark_strait, override_anchor, mark_impassable. Configured straits: Gibraltar–Ceuta, Øresund, Great Belt, Little Belt. The build validates self-connections, asymmetry, unknown IDs, duplicate straits, and missing or out-of-province anchors, and reports isolated islands and connected components to `docs/data/province_graph_validation.md` (currently 0 problems).
- **3C Anchors.** Three-level interior erosion picks the in-province pixel nearest the centroid, at least 3 px from any border where possible, with stable tie-breaking and manual override support.
- **3D Pathfinding.** `province_pathfinder.gd`: Dijkstra with integer day costs packed as `(cost << 13) | id` in a binary heap, sorted neighbour iteration, and stable equal-cost tie-breaks — identical routes on every machine. Route results report existence, path, total days, strait usage, and a human-readable failure reason. Access rules live in one `can_enter` function ready for diplomacy-phase restrictions.
- **3E Army state.** Armies are dictionary records in `CampaignWorldState.army_registry` with the full Phase 3 field set; every country receives one test army at its lowest-ID province, deterministically. Markers are pure presentation.
- **3F Commands.** `MoveArmyCommand` (validates existence, control, lock, destination, route) and `CancelArmyMovementCommand` (stop = cancel: the army holds its current authoritative province). Rejected commands change nothing.
- **3G Scheduler.** `army_movement_system.gd` runs as a daily system: arrivals fire on exact campaign days, access is revalidated before entering each province, and blocked movement halts with a status and an event. Frame rate and game speed cannot change arrival dates. Terrain day-costs are data-driven in the baked graph (plains 5 … mountains 12, strait +4).
- **3H Presentation.** `army_layer.gd` renders MultiMesh markers coloured by owner with stack offsets, day-fraction interpolation between anchors, a selected-army ring, a route ribbon, and a destination marker. The simulation HUD adds Select army, a live route/arrival preview while targeting (hover shows the arrival date and strait usage), Set destination, Cancel movement, and rejection toasts.
- **3I Saves.** Schema version 2 stores the full army registry inside the existing checksummed save; schema 1 saves migrate by recreating the default army setup. `tests/phase_3_movement_test.gd` covers graph invariants, strait configuration, deterministic routing, exact-day arrival, rejected-order immutability, mid-movement save/load equality, cancellation, and migration.

Remaining before the Movement Gate: run the automated tests once the editor is closed, manual vertical-slice QA in Iberia (route readability, stacked markers, zoom visibility), and directional route indicators (the route ribbon is currently undirected).

## Player Outcome

The player can create or select a test army, order it through neighbouring provinces, see its planned route and arrival dates, and watch it move while time advances.

## Entry Conditions

- First Playable gate passes.
- WorldState, commands, clock, save/load, and map selection are stable.
- Province IDs are permanent.

## Major Deliverables

### Adjacency Generator

Scan the source province map and generate:

- Land neighbours.
- Sea neighbours.
- Coastal relationships.
- Province centre points.
- Bounding boxes.
- Pixel area.
- Shared border length.
- Map-edge wrapping links.
- Special crossings and straits.

### Graph Validation

Validate:

- Symmetric adjacency.
- Valid referenced province IDs.
- No impossible self-links.
- Land and sea classification.
- Connected components.
- Isolated provinces.
- Explicit special crossings.

### Province Centres

Generate stable positions for:

- Army markers.
- Province labels.
- Selection focus.
- Effects and notifications.

For irregular or disconnected provinces, permit manually overridden anchor points.

### Pathfinding

Implement:

- A* or Dijkstra search.
- Stable tie-breaking.
- Movement permission checks.
- Terrain cost.
- Country access.
- Enemy territory rules.
- Strait and sea-crossing rules.
- Path preview.
- Unreachable destination feedback.

### Army State Prototype

Initial fields:

- Army ID.
- Owner country.
- Current province.
- Destination.
- Path.
- Path index.
- Start day.
- Arrival day.
- Movement progress.
- Locked movement state.

### Movement Commands

- MoveArmyCommand.
- CancelMovementCommand.
- StopArmyCommand where rules permit.

Validation includes:

- Army ownership.
- Valid destination.
- Valid path.
- Access rights.
- Not currently in battle.
- Movement-lock rules.

### Army Marker Presentation

- Visible marker at province anchor.
- Selection.
- Route line.
- Destination.
- Arrival tooltip.
- Stacked-army handling.
- Marker culling by zoom.

### Save Integration

Save:

- Current province.
- Remaining path.
- Movement start.
- Arrival day.
- Lock state.

Loading must resume movement identically.

## Acceptance Criteria

- Generated adjacency is symmetric.
- Known neighbouring and non-neighbouring test cases pass.
- Every test-region land province is reachable where geography permits.
- Armies cannot cross invalid borders.
- Path results are deterministic.
- Arrival dates do not depend on rendering frame rate.
- Pausing freezes movement.
- Saving and loading during movement preserves the route and arrival date.
- Army markers appear at valid province anchors.
- Invalid movement returns a clear reason.

## Performance Gates

- Pathfinding for normal player orders feels immediate.
- Multiple AI path requests can be scheduled without a visible hitch.
- Adjacency data is loaded from baked output, not regenerated during normal campaign start.
- Route rendering is culled and pooled.

## QA Focus

- Islands.
- Straits.
- Enclaves and exclaves.
- Map wrapping.
- Disconnected province shapes.
- Long-distance routes.
- Access changes during movement.
- Owner changes during movement.
- Save/load near arrival.
- Multiple armies in one province.

## Primary Risks

- Pixel-based adjacency creates false links at diagonal corners.
- Province centres may land outside irregular shapes.
- Global pathfinding can become expensive for many AI armies.
- Access-rule changes may invalidate active paths.
- Sea movement can expand scope before naval design exists.

## Mitigations

- Compare only cardinal pixel neighbours for normal land borders.
- Support manual adjacency overrides.
- Cache or reuse paths where valid.
- Revalidate the next movement step when access changes.
- Keep naval transport minimal and explicitly scoped until later.

## Explicitly Out of Scope

- Full combat.
- Supply simulation.
- Detailed fleets.
- Zone-of-control forts.
- Final military AI.

