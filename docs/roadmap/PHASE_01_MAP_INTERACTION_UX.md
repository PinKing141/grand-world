# Phase 1 — Map Interaction and Strategy UX

## Mission

Turn the rendered world into an understandable strategic interface.

## Production Gate

Map UX Gate.

## Phase 1A Implementation Status

Implemented in the current build:

- Safe pixel-to-province lookup with controlled invalid results.
- Cursor hover state and a screen-clamped province tooltip.
- Left-click province selection with persistent cyan selection feedback.
- Gold hover feedback driven by province IDs in the lookup texture.
- Hover and selection highlights run in the final screen-resolution shader and do not redraw the 5632×2048 distance fields or political texture.
- Province panel with owner, tag, capital, culture, religion, and trade goods.
- Right-click, Escape, and close-button selection clearing.
- UI-safe input routing through `_unhandled_input`.
- Left-button grab-and-drag panning with a configurable pixel threshold that prevents drag gestures from becoming province clicks.
- Immediate middle-mouse panning, WASD/arrow movement, cursor-anchored wheel zoom, keyboard zoom, Home reset, height limits, and map-centre bounds.
- Normal selection separated from ownership mutation.
- Ownership editing gated behind explicit debug properties.
- Prebaked political-texture path that avoids the unstable compute-generation path during normal play.
- Automated `tests/phase_1a_smoke.gd` coverage for the interaction contract.
- A performance-regression assertion that interaction never requests full-map viewport updates.

Remaining before the full Map UX Gate:

- Selected-country territory highlighting and country panel.
- Controller, terrain, region, and coastal-status data.
- Search and camera focus.
- Terrain and debug province-ID map modes.
- Mouse-drag camera movement, zoom-limit review, and horizontal wrapping decision.
- UI scale and tiny-island QA across target resolutions.

## Player Outcome

The player can navigate the map, hover any valid province, select provinces and countries, understand basic ownership, search the world, and switch between early map modes.

## Entry Conditions

- Phase 0 exit criteria pass.
- Static province and country definitions are available through a runtime database.
- Province lookup fails safely.

## Major Deliverables

### Camera

- Smooth keyboard movement.
- Mouse-drag movement.
- Mouse-wheel zoom.
- Configurable zoom limits.
- Configurable movement speed.
- Optional edge scrolling.
- Horizontal map wrapping decision and prototype.
- Focus camera on searched province or country.

### Hover and Selection

- Hovered province ID.
- Hovered province outline.
- Selected province outline.
- Selected country highlighting.
- Selection state separated from simulation state.
- Clear selection action.
- UI-safe input handling so clicks over panels do not affect the map.

### Province Tooltip

Initial fields:

- Province name.
- Province ID.
- Owner country.
- Controller country.
- Terrain.
- Region.
- Coastal status.

Tooltip requirements:

- Appears quickly without flicker.
- Stays inside the screen.
- Does not block map input.
- Handles invalid or hidden information.

### Province Panel

Initial panel:

- Name and ID.
- Owner and controller.
- Terrain.
- Capital or important status.
- Placeholder sections for economy, population, buildings, and unrest.
- Button to open the owner country.

### Country Panel

Initial panel:

- Country name and tag.
- Political colour.
- Capital.
- Owned province count.
- Placeholder sections for ruler, economy, diplomacy, armies, and technology.
- Focus-capital button.

### Search

- Search countries by name and tag.
- Search provinces by name and ID.
- Keyboard navigation.
- Focus map on result.
- Select result.
- Handle duplicate names.

### Initial Map Modes

- Political ownership.
- Terrain.
- Selected-country relations placeholder.
- Debug province ID mode.
- Map-mode button bar.
- Keyboard shortcuts.
- Mode-specific legend.

### Information Architecture

Define:

- Hover information.
- Selected-object information.
- Persistent HUD information.
- Modal screens.
- Notifications.
- Debug-only information.

## Work Breakdown

| Epic | Required implementation | Validation |
|---|---|---|
| Camera | Movement, zoom, limits, focus | Input test checklist |
| Hover | Raycast, lookup, outline, tooltip | All test provinces selectable |
| Selection | Province/country selection state | No simulation mutation |
| Panels | Province and country views | Data fields match database |
| Search | Indexed search and focus | Known queries pass |
| Map modes | Colour providers and legends | Fast mode switching |
| UX framework | Input routing and feedback rules | UI clicks never select map |

## Acceptance Criteria

- Every valid province in the test region can be hovered and selected.
- Hover displays the correct ID, name, owner, and controller.
- Selecting a country highlights its territory.
- Search finds known countries and provinces.
- Camera focus works for search results.
- Map-mode switching does not rebuild the province source texture.
- Mode switching remains responsive.
- Clicking UI does not trigger province selection.
- Missing data displays a controlled placeholder rather than an error.
- All visible controls have tooltips or labels.

## Performance Gates

- Map interaction targets 60 frames per second at 1080p on the reference machine.
- Hover response target is under 100 milliseconds.
- Map-mode switching should not cause a visible multi-frame freeze.
- No per-province scene nodes are introduced.
- Map colour changes are batched.

## QA Focus

- Province edges.
- Tiny islands.
- Sea zones.
- Map corners and wrapping.
- UI scaling.
- Different window sizes.
- Very long names.
- Search with accents and case differences.
- Rapid map-mode switching.
- Clicking while paused or at maximum speed.

## Primary Risks

- Exact pixel lookup may fail near texture filtering boundaries.
- Highlight shaders may interfere with political borders.
- Large embedded data may slow search or panel updates.
- Camera behaviour may become tightly coupled to map dimensions.

## Explicitly Out of Scope

- Economy calculations.
- Army movement.
- Real diplomacy.
- Save-game campaign state.
- Character UI.
- Final visual design.
