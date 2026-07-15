# HUD, Top Bar, Map Controls, and Tooltips

## Persistent HUD goal

The persistent HUD must keep the map dominant while exposing the country's condition, urgent decisions, time controls, current selection, and shortcuts. It must not permanently show every system panel.

At 1152×648, the HUD should reserve enough clear map area for play. Large windows should replace or collapse less important overlays rather than stacking over one another.

## Current placeholder implementation — 15 July 2026

The first functional composition is now integrated without final art:

- `EconomyHUD/ResourceBar` is anchored at the extreme top-left and contains the temporary shield slot, live resource row, full country name, country alerts, and `Gov / Eco / Mil / Dip / Rel` navigation.
- `SimulationHUD/TopBar` is a compact top-right date, pause, speed, quick-save, and quick-load cluster. Debug day/month stepping remains hidden from the normal bar.
- `Gov` opens the Government tab; `Rel` opens the Society tab containing culture and religion; `Eco` opens the economy; `Dip` opens diplomacy/war; `Mil` selects the first available player army or explains that one must be recruited. The temporary shield slot opens Court & Dynasty so the five-button row does not remove access to character gameplay.
- The old floating Diplomacy, Court, and Country & State entry buttons are hidden so the map does not carry duplicate navigation.
- Army map markers are composite markers: a reduced country emblem on the left and authoritative troop strength on the right. The former emblem-only presentation is no longer used. Both halves use `MultiMesh` batches; never replace the counter with one `Label3D` or `Control` node per global army, because the 1444 scenario creates hundreds of starting armies.

Replacement boundaries for future artwork:

- Replace `ShieldButton` and `CountryShieldLabel` with the approved frame, mask, and dynamic emblem while retaining the same clickable node role.
- Replace the `ResourceBar` panel style with approved nine-slice art; do not flatten its dynamic labels into an image.
- Apply final icons/textures through the shared Theme or component scenes. Keep the navigation signals and node names stable.
- Replace the army emblem and counter styling independently; troop values must remain authoritative text and must not be painted into marker artwork.

## Final HUD zones

```text
┌ Country + core resources ─────────────┐  ┌ alerts ┐  ┌ date/speed ┐
│ shield | money | manpower | authority │  │ ! ! !  │  │ 1444  ▶▶  │
└ major-system navigation ──────────────┘  └────────┘  └────────────┘

map modes / legend                                      outliner

selection card / contextual actions           minimised notifications

                  controls hint (only when useful)
```

The precise arrangement may change after minimum-resolution tests. The functional zones and priorities should remain stable.

## Top-left country and resource bar

### Purpose

- Identify the player country instantly.
- Show core scarce resources and their direction of change.
- Open the country overview and major systems.
- Carry high-priority state without turning into a decorative banner.

### Required components

- Country shield frame and replaceable emblem.
- Full country name in tooltip or expanded state.
- Treasury and monthly balance.
- Manpower current/capacity and change where useful.
- Debt/loan warning.
- Stability/authority/legitimacy when the system is relevant.
- War status and critical country condition.
- Major navigation buttons: government/country, economy, diplomacy, military, technology/ideas, society/religion, court/characters.

### Behaviour

- Clicking the shield opens the country overview.
- Hovering each resource explains the current value, cap, monthly change, and sources.
- Negative rates use a minus sign and semantic icon in addition to colour.
- If horizontal space is insufficient, lower-priority resources collapse into an expandable overflow without hiding alerts.
- No internal tag such as `ENG` replaces the visible name `England` in player-facing content.
- Resource numbers use tabular figures to prevent width jitter.

### Art package

- Left, middle, and right stretchable frame pieces or one correctly nine-sliced frame.
- Country shield frame and mask.
- Resource recess/slot.
- Major-navigation button family.
- Alert badge/count.
- Dividers and join caps.
- All required resource/system icons.

## Date, pause, and speed controls

### Required information

- Full campaign date.
- Paused/running state.
- Current speed 1–5.
- Pause/play control.
- Optional debug step-day/month actions only in development builds.

### Behaviour

- Spacebar pause must visibly match the control state.
- Speed shortcuts must show the selected speed without relying only on colour.
- Important modal choices pause according to game rules and explain whether time is stopped.
- Save/load shortcuts belong in a menu or restrained quick-access area, not among speed values if they make the bar crowded.

## Alert strip

Alerts are unresolved player decisions, not a scrolling event log.

Examples:

- Available technology/reform/idea.
- Unassigned commander or heir/succession danger.
- Empty construction/recruitment capacity where actionable.
- Loan due or dangerous deficit.
- Incoming diplomatic offer.
- War goal, occupation, siege, or peace opportunity.
- High unrest/rebellion.
- Subject disloyalty.

Each alert requires:

- Recognisable icon and severity shape.
- Short tooltip explaining cause, consequence, and action.
- Click action that opens or focuses the relevant screen.
- Dismiss/snooze rules where appropriate.
- Deduplication and a count for repeated instances.
- Accessible non-colour distinction.

Do not put debug warnings or routine monthly income messages in this strip.

## Map mode controls

The existing map HUD provides political, terrain, debug, colour-vision selection, and economic/war/internal overlays through other scenes. Consolidate these into one map-mode component.

Required groups by 1.0:

- Core: political, terrain, province IDs only in debug.
- Economy: tax, production, manpower, development, construction.
- Diplomacy/war: relations, war, access, occupation/goal.
- Internal state: unrest, control, culture, religion, technology.
- AI objective overlay only in developer/debug mode.

Requirements:

- Selected mode is unmistakable.
- Tooltip gives name, purpose, legend, and shortcut.
- Legend updates to the active mode and can collapse.
- Colour-vision presets affect relevant map encodings without altering unrelated UI art.
- Mode buttons remain usable at minimum resolution and high UI scale; overflow may use a drawer.

## Province hover tooltip

The hover tooltip is for rapid map reading, not the complete province database.

Show:

- Province name.
- Owner/controller with full country names.
- Terrain and coastal/landlocked state.
- One context-sensitive line for the active map mode.
- Occupation/siege or invalid/wasteland state where applicable.

Rules:

- Delay just enough to avoid flicker while panning; do not make routine inspection feel slow.
- Never block the province under the pointer or escape the safe screen rectangle.
- Hide while drag-panning.
- Use a stable width and wrap long names rather than resizing every frame.
- Pin/expanded help may be added later, but the normal tooltip should remain compact.

## Search

Search must find countries and provinces by player-visible names and aliases.

The search field needs:

- Clear focus state and keyboard shortcut `/`.
- Results grouped by type.
- Country emblem/colour and province owner context.
- Keyboard navigation and Enter to focus the map.
- Empty, no-result, and invalid-query states.
- Escape to clear/close without also triggering an unrelated map action.

Internal tags and numeric IDs can be optional debug metadata, never the primary result name.

## Selection and contextual action cards

Map selection should reveal one contextual card:

- Province selection opens/focuses province information.
- Country selection offers country/diplomacy actions.
- Army selection offers movement, cancel order, maintenance/strength, and disband confirmation.
- Siege/battle selection shows status and participants.

Do not leave army, province, country, economy, diplomacy, and debug cards stacked simultaneously. Establish ownership of the lower-left/lower-right selection zones and collapse displaced cards.

## Outliner preview

The outliner is fully specified in the release-screens document, but its persistent HUD placement must be reserved now. It should collapse to a narrow header and display user-selected categories such as armies, sieges, construction, recruitment, diplomats, and subjects.

## Controls hint bar

The existing permanent hint bar is useful during development but should become contextual onboarding:

- Show essential controls during the first session.
- Fade/collapse after demonstrated use.
- Reappear through Help or when input context changes.
- Display remapped bindings rather than hard-coded text.
- Avoid covering the map or overlapping selection panels at minimum resolution.

## HUD state checklist

Test the HUD with:

- Observer and player-controlled country.
- Very long country name.
- Zero, negative, and seven-digit resources.
- No alerts, one alert, and more alerts than fit.
- Paused at each speed state.
- Province, country, army, battle, siege, and no selection.
- Every map mode and legend size.
- Search open with long results.
- 100%, 125%, 150%, and 200% UI scale where supported.
- 1152×648, 1700×960, 1920×1080, ultrawide, and window resize.
- Keyboard-only flow and colour-vision presets.
