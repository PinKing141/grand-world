# 05 — Map Objects, Atmosphere, and Level of Detail

## Outcome

Make the map feel inhabited and responsive without sacrificing strategic clarity or frame time. Essential gameplay objects appear first; ambience is added only after interaction and political hierarchy are stable.

## Object Hierarchy

| Tier | Examples | Rule |
|---|---|---|
| Interaction-critical | Hover, selection, command destination, invalid target | Always wins visual priority |
| Conflict-critical | Armies, navies, battles, sieges, occupation, war goal | Clear in relevant modes and zooms |
| Strategic infrastructure | Capital, fort, port, major settlement, trade hub | Visible according to zoom/mode/importance |
| Geographic support | River crossing, mountain pass, strait, impassable boundary | Visible when it changes understanding or movement |
| Ambient | Vegetation clusters, roads, ships, clouds, waves, decorative settlement detail | Cull first and never block gameplay |

## Epic MO-1 — Marker Visual Language

### MO-1.1 Inventory every current marker — P1 / M

Record the marker's gameplay meaning, source data, current asset, size, colour, update trigger, map modes, zoom range, and whether it is still a placeholder.

Audit at least:

- Capital/province centre.
- Army and navy.
- Movement destination/path.
- Battle and siege.
- Occupation/control.
- Construction/recruitment.
- Rebel/unrest.
- Event/decision/notification anchors.
- Selection and hover.
- Debug nodes and province IDs.

**Done when**

- Every normal-play marker has an approved owner and replacement plan.
- Debug-only markers are hidden behind a development setting.

### MO-1.2 Create shared silhouette and state grammar — P1 / L

Markers must communicate through more than colour:

- Shape identifies object family.
- Interior icon identifies function.
- Border/emblem identifies owner or allegiance.
- Small badges identify exceptional states.
- Animation is reserved for urgency or active change.
- Size and label reveal strategic importance.

**Done when**

- A player can distinguish the main marker families in greyscale.
- Enemy/friendly/neutral remains understandable under supported colour-vision simulations.
- Marker art remains legible over desert, snow, forest, ocean, and political fills.

### MO-1.3 Define marker-label-border precedence — P1 / M

Recommended ordering:

1. Active hover/selection/command.
2. Battle/siege/critical warning.
3. Selected army/navy and route.
4. Other armies/navies.
5. Capital/fort/port.
6. Country/province labels.
7. Decorative settlements and environment.

**Done when**

- No essential marker is hidden by a country label.
- Collisions use bounded screen-space regions.
- Tooltip targets remain clickable and predictable.

## Epic MO-2 — Settlements and Strategic Geography

### MO-2.1 Add capital and settlement tiers — P1 / L

Suggested tiers:

- Country capital.
- Regional/provincial capital.
- Major city/trade centre.
- Minor settlement, only at close zoom if justified.

Use symbolic/cartographic markers first. Add miniature 3D/2.5D settlement art only if it meets the clarity and batching budget.

**Done when**

- Every country capital resolves to a valid province and marker.
- Capital importance is clear without reading a tooltip.
- Dense Europe does not become a carpet of identical buildings.
- Destroyed/occupied/moved capital states update correctly.

### MO-2.2 Add ports and straits — P1 / M

Ports must communicate naval access and be tied to validated coastal province data. Straits should have a restrained geographic/route cue in movement-relevant modes.

**Done when**

- Inland provinces cannot receive ports.
- Port orientation/placement does not float on land or deep water.
- Strait links agree with pathfinding and label-component rules.

### MO-2.3 Add forts and major infrastructure — P2 / M

Only expose infrastructure the player can act on or that changes strategy. Do not add decorative roads/forts before the underlying gameplay state exists.

## Epic MO-3 — Army, Navy, Battle, and Occupation Presentation

### MO-3.1 Replace placeholder unit markers — P1 / L

The approved unit marker needs:

- Owner identity.
- Army/navy type.
- Strength summary.
- Selected state.
- Moving/idle/besieging/in-battle state.
- Hostile/friendly/access relationship.
- Stack/overlap behaviour.
- Legible reduced representation at regional zoom.

**Done when**

- Multiple armies in a dense province cluster without hiding ownership.
- Unit movement remains smooth and selection hitboxes remain reliable.
- Markers do not force a label-layout rebuild every frame.

### MO-3.2 Present battle, siege, and occupation hierarchy — P1 / L

- Battle marker is urgent and clickable.
- Siege marker communicates progress without a full HUD panel on the map.
- Occupation remains a province-level semantic overlay with accessible pattern support.
- War goal and command target remain distinguishable from generic occupation.

### MO-3.3 Bound route and movement lines — P1 / M

Movement paths need stable screen width, direction, destination, valid/invalid feedback, and map-seam behaviour.

**Done when**

- Lines do not shimmer or disappear under water/country fills.
- Long paths are culled/batched and do not allocate unbounded geometry.

## Epic MO-4 — Zoom LOD and Culling

### MO-4.1 Create one LOD policy service — P1 / L

Labels, borders, terrain detail, vegetation, settlements, units, routes, effects, and atmosphere should read the same named zoom bands and hysteresis policy.

**Done when**

- No subsystem invents independent magic zoom thresholds without registration.
- Thresholds are data-driven and inspectable in a debug overlay.
- Continuous zoom does not cause repeated allocation/destruction thrash.

### MO-4.2 Define density budgets — P1 / M

Set maximum visible counts or clustering rules for:

- Country labels.
- Province/settlement labels.
- Army/navy markers.
- Settlement/port/fort objects.
- Vegetation instances.
- Ambient particles/clouds.
- Route segments and effects.

Budgets are measured per reference view and quality tier rather than guessed globally.

### MO-4.3 Implement screen-space clustering — P1 / L

Dense markers should merge, offset, or prioritise predictably.

**Done when**

- Clusters show count and allegiance context.
- Selection can reveal or cycle members.
- Clustering is deterministic for the same camera state.
- Re-clustering cost stays within camera-motion budget.

### MO-4.4 Cull before expensive layout/material work — P1 / M

Use map bounds, camera frustum/projected viewport, zoom band, mode, and importance before allocating or updating detailed nodes.

## Epic MO-5 — Atmosphere and Motion

### MO-5.1 Add a motion budget — P1 / S

List every animated visual: water, flags, unit idle, route flow, battle, siege, weather, clouds, selection pulse, notifications, and transitions.

**Rules**

- Motion indicates change, importance, or atmosphere—not every object at once.
- Reduced-motion mode removes nonessential animation and replaces essential animation with a static state cue.
- Paused gameplay retains sufficient state clarity.

### MO-5.2 Add clouds/weather only after LOD and hierarchy pass — P3 / L

Clouds/weather may add world scale but cannot obscure selected regions, labels, borders, or markers. Use broad low-frequency forms, aggressive culling, and a user setting.

### MO-5.3 Add ambient ships/roads/trade motion only when supported by gameplay — P3 / L

Ambient routes should derive from real trade/movement data where possible. Fake motion that implies nonexistent mechanics should not ship.

### MO-5.4 Add restrained screen/post presentation — P2 / M

Vignette, colour grading, bloom, shadow, or atmospheric haze require explicit before/after readability and performance review. Political colours and labels must remain stable across settings.

## Epic MO-6 — Interaction and Accessibility

### MO-6.1 Preserve click and drag behaviour — P1 / M

Map objects must respect the existing click-versus-drag camera threshold, UI capture, and selection rules.

**Done when**

- Camera drag does not select a province, marker, or label.
- Clicking a visible marker selects the intended entity.
- Hover state does not add panning lag.
- UI panels do not allow map clicks through them.

### MO-6.2 Add clutter and animation controls — P1 / M

Suggested settings:

- Map detail quality.
- Marker scale.
- Label scale/toggle.
- Ambient objects on/off.
- Weather/clouds on/off.
- Reduced motion.
- High-contrast selection/borders.

### MO-6.3 Support keyboard and focus navigation for essential map actions — P2 / L

Map presentation cannot be the only way to locate urgent battles, armies, capitals, or selected provinces. Outliner/search/notifications must provide alternative navigation.

## Presentation Alpha Gate

- Every gameplay-critical object has an approved, non-placeholder representation.
- Strategic, regional, and close LOD are coherent across all layers.
- Dense armies, settlements, and labels remain readable in Europe and other stress regions.
- Panning, dragging panels, zooming, and marker movement meet performance budgets.
- Selection and command feedback are never ambiguous.
- Colour-blind, high-contrast, clutter, and reduced-motion alternatives pass.
- Decorative atmosphere can be disabled without losing gameplay information.

