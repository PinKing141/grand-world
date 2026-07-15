# Godot Handoff, Accessibility, Performance, and QA

## Handoff contract

Every art delivery must include:

- Editable source file.
- Transparent runtime export or SVG where the chosen Godot path supports it reliably.
- Asset name, component role, native dimensions, scale variants if any.
- Nine-slice margins where applicable.
- State names.
- Source/licence/provenance record.
- Screenshot at actual in-game size on light and dark map areas.

Do not merge artwork that still contains a checkerboard, flattened temporary text, unapproved watermark, unknown licence, or visible JPEG artefacts.

## Godot implementation rules

- Apply one project-wide `Theme` from a stable UI root.
- Use `ThemeVariation` for major/utility/parchment/danger variants instead of per-node duplication.
- Prefer containers, anchors, size flags, and minimum sizes over manually positioned controls.
- Use `NinePatchRect`/`StyleBoxTexture` for stretchable frames and controls.
- Keep dynamic text in `Label`/`RichTextLabel`, never in painted art.
- Keep country emblems, portraits, event art, and icons replaceable without editing frame scenes.
- UI scripts display state and submit commands; they do not reproduce simulation formulas.
- Release builds hide debug panels, tags, IDs, checksum/tick timings, and AI plans unless a developer mode is deliberately enabled.
- Centralise z-order/modal ownership so windows do not appear behind other overlays.
- Centralise tooltip and notification services to prevent inconsistent placement and timing.

## Responsive layout tiers

Minimum required checks:

| Tier | Reference | Expected adaptation |
|---|---|---|
| Minimum | 1152×648 | Compact HUD, overflow groups, single major window, scrollable content |
| Mid | 1700×960 | Normal production layout used by existing smoke tests |
| Standard HD | 1920×1080 | Full intended layout with comfortable map area |
| Ultrawide | 2560×1080 or similar | Anchored zones remain near useful edges; no excessive stretched bars |

Test 100%, 125%, 150%, and 200% scale where supported. At high scale, switch to full-screen windows or fewer columns instead of shrinking text.

Safe-area rules:

- No action below/behind the bottom hint area.
- Tooltips and dropdowns stay inside viewport bounds.
- Movable windows retain a reachable title/drag area.
- Modal backdrop covers all gameplay input.
- The map remains interactable only where UI does not capture input.

## Input and focus

- Every button, tab, list, slider, text field, and option must have visible keyboard focus.
- Establish predictable focus order and explicit focus neighbours where automatic order fails.
- Escape closes the topmost dismissible layer; it must not clear map selection simultaneously unless intended.
- Enter confirms only when the focused/default action is safe.
- Destructive dialogs default focus to cancel.
- Tooltips must be available through focus, not only mouse hover.
- Dragging windows or the map must not be interpreted as a click; movement threshold is preferred over an arbitrary time delay.
- Support remapped bindings in hint/help text.

## Accessibility requirements

### Readability

- Maintain sufficient text/background contrast across textured panels.
- Put a quiet solid/gradient backing under text; never use glow or highlight smears as a readability substitute.
- Avoid tiny all-caps body copy and excessive letter spacing.
- Disable or reduce texture behind dense tables.
- Full country/province names should remain crisp at supported UI scales.

### Colour vision

- Test common red–green and blue–yellow deficiencies.
- Reinforce states with icons, patterns, signs, labels, and shape.
- Keep map colour-vision presets separate from UI focus/selection semantics.
- Conduct hands-on review with colour-vision-deficient players; simulation filters are an early check, not final approval.

### Motion and sound

- Reduced-motion mode removes nonessential slides, pulses, and map-to-window travel.
- Avoid rapid flashing.
- Sound categories can be adjusted independently.
- Important results remain understandable with sound muted.

### Cognitive load

- Use consistent words for the same mechanic.
- Put consequences beside actions.
- Explain lock reasons and recovery.
- Avoid multiple simultaneous modal windows.
- Allow notification presets and pause-friendly interaction.

## Localisation and data formatting

- Allow at least 30–50% text expansion in layouts.
- Test long country, province, character, dynasty, government, and building names.
- Do not concatenate translated sentence fragments.
- Dates, decimals, percentages, signs, and thousands separators use a central formatter.
- Use full player-facing country names, never internal three-letter tags as fallback except clearly marked debug output.
- Fonts must contain all characters required by supported languages.
- Icons with letters or culturally specific metaphors require localisation review.

## Performance rules

UI performance is part of map performance because these layers render together.

- Update displayed values on state changes/events, not every frame.
- Avoid rebuilding large RichTextLabel strings continuously.
- Pool/virtualise ledger, outliner, notification, and character-tree rows.
- Keep global map markers batched. Army troop counters use one procedural digit shader and one `MultiMesh`; per-army `Label3D` nodes are prohibited because they exhaust memory and draw-call budgets at global scale.
- Avoid hundreds of independent animated materials or expensive blur effects.
- Use atlases only when they improve batching without creating unmaintainable imports.
- Limit full-screen translucent overdraw and multi-pass shadows.
- Pause hidden-window processing and animation.
- Profile map panning, zooming, menu dragging, opening/closing, large wars, large character lists, and long notification history.
- Ordinary 1080p movement should target 16.67 ms P95 on approved reference hardware; record CPU/GPU frame time separately.

Do not assume a visually small panel is cheap. Text shaping, repeated style boxes, transparency, layout churn, and frequently rebuilt lists can all cause stutter.

## Automated QA

Extend UI tests to cover:

- Every major scene loads in the packaged main scene.
- Bounds at 1152×648 and 1700×960; add 1920×1080 and high-scale coverage.
- No control is outside safe bounds or has negative size.
- Critical buttons are visible and enabled only under correct state.
- Save/load restores open/closed state only where intended, never stale temporary dialogs.
- Debug-only panels are absent/hidden in release configuration.
- Long fixture names and values do not overlap.
- Keyboard focus can reach primary actions and return safely.
- Notification/outliner row caps or virtualisation hold under stress.

Screenshot-based regression tests may catch unexpected layout or theme changes, but require controlled fonts, window size, renderer, and tolerance. They supplement—not replace—hands-on review.

## Hands-on QA matrix

For each production screen, perform:

1. Open/close repeatedly while paused and running.
2. Use mouse, keyboard, and remapped controls.
3. Resize the window and change UI scale.
4. Trigger normal, disabled, warning, empty, loading, and error states.
5. Test very long labels and maximum plausible numbers.
6. Drag/pan/zoom the map while persistent HUD elements are present.
7. Open the screen during a large war and at maximum simulation speed.
8. Save, load, export, and run the packaged Windows build.
9. Review contrast and colour-vision alternatives.
10. Record screenshot, build/version, hardware, result, and issue severity.

## Severity policy

- **P0:** crash, data loss, impossible progression, unusable export, major input capture, critical inaccessible action.
- **P1:** overlapping/clipped primary interface, wrong authoritative value, unreadable required text, severe frame-time regression, missing consequence/confirmation.
- **P2:** confusing hierarchy, inconsistent state, poor scaling in a non-primary case, minor accessibility failure.
- **P3:** cosmetic spacing, texture seam, small icon inconsistency, polish request.

No known P0 is acceptable at any playable milestone. Phase 9 release candidate requires zero P0/P1 UI defects and documented disposition for remaining P2/P3 issues.

## Approval evidence

Each completed screen should have:

- Approved mock-up and actual in-engine screenshot.
- Component and asset IDs from the register.
- Supported-resolution screenshots.
- Keyboard/accessibility review result.
- Performance capture for heavy screens.
- Packaged-build test result.
- Known issues and responsible milestone.
