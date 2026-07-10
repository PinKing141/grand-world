# Phase 3 — World Graph, Pathfinding, and Movement

## Mission

Transform the province map into a traversable strategic world and prove that armies can move through it using deterministic rules.

## Production Gate

Movement Gate.

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

