# Grand World UI Production Handbook

## Purpose

This handbook is the durable source of truth for designing, creating, integrating, and approving the complete *Grand World* interface. It covers the current playable HUD and every major window planned for the 1.0 roadmap.

The project may borrow the information density and strategic clarity of games such as *Europa Universalis IV*, but it must not copy, extract, trace, or redistribute their artwork. Every frame, icon, heraldic element, texture, sound, and layout must be project-owned or carry a recorded compatible licence.

The supplied `Granstat_top_bar_SVG_202607151513.jpeg` is a visual reference only. Despite its filename, it is a flattened JPEG, not an SVG. Its checkerboard is baked into the image and it has no usable transparency or separate interactive layers. Rebuild the design as modular original assets.

## How to use this handbook

Read the files in this order when beginning the UI art pass:

1. [Toolchain and learning path](./00_TOOLCHAIN_AND_LEARNING_PATH.md)
2. [Visual language and component system](./01_VISUAL_LANGUAGE_AND_COMPONENT_SYSTEM.md)
3. [HUD, top bar, map controls, and tooltips](./02_HUD_TOP_BAR_AND_MAP_CONTROLS.md)
4. [Province, country, economy, and internal-state windows](./03_PROVINCE_COUNTRY_ECONOMY_WINDOWS.md)
5. [Diplomacy, war, military, characters, events, and AI windows](./04_DIPLOMACY_WAR_CHARACTER_EVENT_WINDOWS.md)
6. [Release screens, menus, ledger, onboarding, and notifications](./05_RELEASE_SCREENS_AND_FUTURE_WINDOWS.md)
7. [Godot integration, accessibility, performance, and QA](./06_GODOT_HANDOFF_ACCESSIBILITY_QA.md)
8. [Asset register and completion checklist](./07_ASSET_REGISTER.md)

Related planning documents remain useful:

- [UI art requirements](../roadmap/UI_ART_REQUIREMENTS.md) is the high-level asset estimate.
- [UI art AI prompts](../roadmap/UI_ART_AI_PROMPTS.md) contains optional ideation prompts, not final art specifications.
- [Phase 9 global release](../roadmap/PHASE_09_GLOBAL_RELEASE.md) defines the release gate.
- [Map visual production](../roadmap/map_visual_production/README.md) owns map rendering, labels, borders, and map objects rather than screen UI.

If documents disagree, use this order of authority:

1. Current gameplay and accessibility requirements.
2. This handbook's approved component and screen specifications.
3. Phase roadmap acceptance criteria.
4. Reference images and inspiration.

## Current implementation inventory

The following scenes are functional foundations, not final visual art:

| Scene | Existing interface | Production state |
|---|---|---|
| `scenes/ui/map_hud.tscn` | Province tooltip/panel, country panel, map modes, colour-vision option, search, controls hint | Functional debug UI; needs themed components and responsive hierarchy |
| `scenes/ui/simulation_hud.tscn` | Date, pause/speed, save/load, country selection, army panel, performance debug | Functional debug UI; top bar must be rebuilt and debug data hidden in release |
| `scenes/ui/economy_hud.tscn` | Resources, economy ledger summary, loans, maintenance, construction/recruitment | Functional debug UI; must become a coherent economy window and province tab |
| `scenes/ui/war_hud.tscn` | Diplomacy actions, war selection, overlays, basic peace actions | Functional debug UI; needs full declare-war, war overview, and peace layouts |
| `scenes/ui/ai_debug_hud.tscn` | Campaign status, strategy, plan, resources, threats, decision history | Developer tool; visually subordinate and excluded from normal player flow |
| `scenes/ui/character_hud.tscn` | Court, ruler/heir, portrait placeholder, character data, marriage and claims | Functional debug UI; needs portrait, dynasty, succession, and relationship presentation |
| `scenes/ui/country_depth_hud.tscn` | Government, technology, reforms, society, subjects, events and decisions | Functional debug UI; should be divided into player-readable dedicated windows/tabs |

There is currently no `assets/ui/` production-art library. The asset register treats existing controls as grey-box components until approved art is created and integrated.

## Complete screen inventory for 1.0

| Family | Required interfaces |
|---|---|
| Persistent HUD | Country crest, resources, alerts, date/speed, quick actions, outliner, minimised notifications, map modes, search, tooltips |
| Province | Hover tooltip, province overview, economy/buildings, military/recruitment, culture/religion, occupation/siege |
| Country | Overview, economy, government, technology, ideas/direction, culture/religion, subjects, decisions |
| Diplomacy | Country diplomacy, relation breakdown, diplomatic action list, declare war, war goal, treaty/access, peace negotiation |
| Military | Army card, army list, route, recruitment, battle summary, siege, war overview |
| Characters | Court, character sheet, family/dynasty, succession, marriage, claims, death/succession notices |
| Events | Event popup, choice outcomes, decisions list, notification history |
| Reference/QoL | Ledger, outliner, map-mode legend, search results, glossary, tutorial/help |
| Shell | Main menu, nation selection, loading, pause, settings, controls, accessibility, save/load browser, confirmations, error/recovery |
| Development only | AI inspector, checksum/tick profiler, data-validation reports, debug overlays |

## Production order

Do not start by painting every window. Build a reusable system in this order:

1. Approve the visual-direction board, fonts, colour tokens, spacing, and scale targets.
2. Build one 64×64 button through all interaction states.
3. Build the nine-slice window frame, recessed sub-panel, header, tab, tooltip, progress bar, scroll bar, and input-field family.
4. Rebuild the persistent top-left HUD using those components.
5. Apply the same system to province and country windows.
6. Complete diplomacy, military, economy, characters, and events.
7. Build the ledger, outliner, nation picker, menus, settings, and save/load shell.
8. Perform resolution, localisation, accessibility, input, performance, and packaged-build reviews.

## Definition of done

A screen is not finished because it looks attractive in a mock-up. It is finished only when:

- Its purpose and primary action are obvious within five seconds.
- Every value has a clear label, unit, state, and explanatory tooltip.
- Normal, hover, pressed, selected, focused, disabled, loading, empty, warning, and error states are handled where relevant.
- It remains usable at 1152×648, 1700×960, and 1920×1080 with the supported UI scales.
- Long country/province names and expanded localisation do not overlap controls.
- Keyboard focus is visible and all required actions are reachable without precise mouse movement.
- Meaning is not communicated through colour alone.
- Art sources and licences are recorded.
- The screen uses shared components instead of one-off copies.
- It passes UI layout smoke tests and a hands-on rendered-build review.
- It does not materially reduce map-pan, zoom, menu-drag, or maximum-speed performance.

