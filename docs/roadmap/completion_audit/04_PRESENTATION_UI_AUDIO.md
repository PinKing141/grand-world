# 04 — Presentation, UI and Audio

The project has a functional interface and a much stronger strategic map than at the start of development. The remaining work is the difference between a powerful prototype and a readable, coherent commercial presentation.

## UI Theme and Asset Production

### Current state

The interface has a main menu, nation selection, top-left country shell, top-right date controls, campaign panels and functional flat styling. An art-direction and AI-prompt specification exists, but the full production asset set is not finished.

### Remaining work

- Create the approved top-bar frames, shields, panel corners, dividers, tabs, buttons, scrollbars, alert badges and icon families.
- Establish a reusable nine-slice component library rather than embedding unique artwork in each screen.
- Define typography roles for display, headings, numbers, body, tooltips and compact labels.
- Finish hover, pressed, selected, disabled, warning and critical states.
- Provide UI scaling at supported resolutions and safe layouts at 16:9, 16:10 and ultrawide.
- Remove all short-tag leakage where a full player-facing country name is required.
- Create asset-source/licence metadata for every external or generated image.

### Exit gate

The component library must reproduce all common windows without custom one-off code, remain legible at approved UI scales and pass contrast/keyboard/focus review.

## Strategic Map Presentation

### Current state

Political colours, terrain/water, shared borders, screen-space labels, orthographic/strategic camera work, armies and map modes exist. Performance has reached a recorded 1080p P95 of 15.748 ms in a map-motion test.

### Remaining work

- Finish the approved border hierarchy for province, subject, sovereign and coast edges.
- Complete neighbour-colour tooling and reduce political “confetti” without erasing political identity.
- Finalise zoom-dependent country/province label size, collision, curvature and sharpness.
- Validate marker clustering/clicking at high unit density.
- Finish terrain biome materials, mountains, forests, deserts, snow and climate transitions.
- Remove temporary/coarse coastline treatments and validate water import/source settings.
- Add rivers with an approved schema, source and combat/movement integration.
- Add seasons/winter if retained by the final design and performance budget.
- Resolve province-map, definition-map and water-source provenance before commercial release.
- Approve hardware budgets and repeat GPU/CPU profiling on target low/mid/high configurations.

### Exit gate

The Visual Greenlight must pass approved benchmark scenes, labels must remain readable without highlights or blur, borders must be solid and correctly prioritised, and representative movement at 1080p must approach a 16.67 ms P95 target on the selected minimum hardware.

## Character Portraits and Heraldry

### Current state

Characters can exist mechanically, but portraits are placeholders. Historical shield research is tracked; only 39 shields are currently approved across a 1,007-entry registry, with 968 missing or unapproved.

### Remaining work

- Choose illustrated, modular, generated-with-review or hybrid portrait architecture.
- Define period, region, age, rank, clothing, background and pose rules.
- Add portrait caching, fallbacks and deterministic character appearance IDs.
- Complete historical shield research by country and date.
- Keep unapproved/fake shields hidden rather than presenting invented history as authoritative.
- Record provenance, transformation and usage rights for every final asset.

### Exit gate

Every active country and visible major character must have an approved asset or an explicitly approved neutral fallback, with no fake historical claim and no missing-texture state.

## Information Architecture and Quality of Life

### Current state

Core country, province, economy, diplomacy, war, character and nation-selection panels exist, plus campaign shell/outliner/minimap/alerts foundations.

### Remaining work

- Full notification centre and event history.
- Message settings by event type and delivery level.
- Complete outliner for armies, fleets, construction, diplomats, colonists and key subjects.
- Macro-builder for construction and recruitment.
- Full ledger and searchable statistical views.
- Save browser, bookmark management and campaign metadata.
- Complete options: audio, graphics, resolution, UI scale, accessibility, input remapping and reset.
- Nested tooltips and consistent modifier-source explanations.
- Controller support only if explicitly added to the platform scope.

### Exit gate

A new player must be able to find any active task, explain any major number and recover from an interrupted campaign without consulting developer documentation.

## Audio

### Current state

No production music or sound-effect files are currently present.

### Minimum 1.0 scope

- Period-appropriate soundtrack with legally clear provenance.
- Map/camera ambience and restrained environmental loops.
- UI hover, click, confirm, warning and error sounds.
- War declaration, battle, siege, peace and major event cues.
- Separate music, ambience, interface and effects volume controls.
- Music scheduling that avoids rapid repetition and respects campaign context.
- Accessibility options for reducing startling or repetitive sounds.

### Exit gate

Every critical player action must have optional non-visual feedback, all audio must have rights metadata, and volume/mute settings must persist correctly through save-independent configuration.

## Accessibility and Localisation

- Colour-vision-deficiency testing with real players, not shader simulation alone.
- Contrast and non-colour cues for political/war/selection states.
- UI scaling and large-text validation.
- Keyboard focus order and shortcut discoverability.
- Remappable controls and reduced-motion options where relevant.
- Localisation keys for all player-facing text; no hard-coded English in final UI.
- Label architecture capable of different name lengths and scripts.
- Captions/text equivalents for critical audio information.

