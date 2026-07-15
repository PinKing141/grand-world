# UI Asset Register and Completion Checklist

## Status legend

- **Grey-box:** functional Godot controls exist, but production art/layout is not approved.
- **Not started:** no production component/screen exists.
- **In progress:** assigned and actively being produced.
- **Review:** in-engine and awaiting art/UX/accessibility/performance approval.
- **Approved:** source, runtime asset, implementation, provenance, and QA evidence are complete.
- **Placeholder:** deliberately temporary and registered for replacement; never count as approved final art.

Update this file whenever an asset enters the project. Do not rely on memory or filenames to communicate status.

## A. Foundation decisions

| ID | Deliverable | Current status | Completion evidence |
|---|---|---|---|
| UI-FND-001 | Original visual-direction board | Not started | Approved actual-size board covering HUD, province, ledger, event, states, scales |
| UI-FND-002 | Font family and redistribution licences | Not started | Font files, licence files, glyph/number/localisation test |
| UI-FND-003 | Colour and semantic token sheet | Not started | Normal and colour-vision review; contrast results |
| UI-FND-004 | Spacing, sizing, and scale tokens | Not started | 1152×648 through 1920×1080 examples |
| UI-FND-005 | Project-wide Godot Theme | Grey-box | Shared resource replaces scattered one-off styling |
| UI-FND-006 | Source/runtime folder and naming policy | Documented | Enforced folder structure and review checklist |
| UI-FND-007 | Attribution/licence register | Not started | Every third-party asset has source, author, licence, modifications |

## B. Core component art

| ID | Component | Required variants/states | Status |
|---|---|---|---|
| UI-CMP-001 | Major window frame | 9-slice, title integration, active/inactive | Not started |
| UI-CMP-002 | Utility window frame | 9-slice, dense content | Not started |
| UI-CMP-003 | Recessed sub-panel | light/dark/dense | Not started |
| UI-CMP-004 | Parchment/document panel | 9-slice, text-safe | Not started |
| UI-CMP-005 | Tooltip frame | compact/wide/error | Grey-box |
| UI-CMP-006 | Modal frame and backdrop | confirm/warning/error | Not started |
| UI-CMP-007 | Header plate/divider | major/section/table | Not started |
| UI-CMP-008 | Primary button | normal/hover/pressed/focus/disabled | Grey-box |
| UI-CMP-009 | Secondary/icon/danger button | full state set | Grey-box |
| UI-CMP-010 | Tab | active/inactive/hover/focus/disabled | Grey-box |
| UI-CMP-011 | Text/search field | normal/focus/disabled/error | Grey-box |
| UI-CMP-012 | Dropdown/list row | normal/hover/selected/focus/disabled | Grey-box |
| UI-CMP-013 | Checkbox/radio/toggle | off/on/mixed/focus/disabled | Not started |
| UI-CMP-014 | Slider/value control | normal/focus/disabled | Not started |
| UI-CMP-015 | Scroll bar | normal/hover/drag/focus/disabled | Grey-box |
| UI-CMP-016 | Progress bar | normal/paused/blocked/complete/indeterminate | Grey-box |
| UI-CMP-017 | Sortable table header/row | normal/hover/selected/sort up/down | Not started |
| UI-CMP-018 | Status chip/badge/counter | neutral/positive/warning/critical | Not started |
| UI-CMP-019 | Notification card/toast | info/action/warning/critical | Not started |
| UI-CMP-020 | Empty/loading/error states | compact/window/modal | Not started |
| UI-CMP-021 | Country shield frame and mask | small/medium/large, selected | Placeholder |
| UI-CMP-022 | Portrait/dynasty frame and mask | ruler/character/dead/missing | Placeholder |
| UI-CMP-023 | Event image frame and mask | fixed crop, modal size | Not started |
| UI-CMP-024 | Focus ring | light/dark/critical-background proof | Not started |

## C. Persistent HUD

| ID | Deliverable | Existing foundation | Status |
|---|---|---|---|
| UI-HUD-001 | Country identity/shield control | Top-left placeholder frame, slot, and full country identity | Placeholder |
| UI-HUD-002 | Resource strip | Live treasury/balance/manpower/queue/debt row in final structural position | Placeholder |
| UI-HUD-003 | Date/pause/speed cluster | Compact top-right functional cluster | Placeholder |
| UI-HUD-004 | Alert strip and overflow | None | Not started |
| UI-HUD-005 | Major-window navigation | Unified `Gov / Eco / Mil / Dip / Rel` placeholder row | Placeholder |
| UI-HUD-006 | Map-mode tray and legend | Functional buttons/legend | Grey-box |
| UI-HUD-007 | Country/province search | Functional search | Grey-box |
| UI-HUD-008 | Province hover tooltip | Functional tooltip | Grey-box |
| UI-HUD-009 | Selection/context card system | Several independent panels | Grey-box |
| UI-HUD-010 | Contextual controls/help hint | Permanent hint bar | Grey-box |
| UI-HUD-011 | Collapsible outliner dock | None | Not started |
| UI-HUD-012 | Notification/toast dock | Limited event labels | Not started |
| UI-HUD-013 | Release removal of debug tick/tag/ID | Debug panels/IDs exist | Not started |

## D. Gameplay windows

| ID | Window | Required areas | Status |
|---|---|---|---|
| UI-WIN-001 | Province overview | Identity, ownership/control, terrain, economy, society, status | Grey-box |
| UI-WIN-002 | Province economy/buildings | Values, slots, buildings, queue, construct/cancel | Grey-box |
| UI-WIN-003 | Province military | Recruitment, present armies, fort/siege/occupation | Grey-box |
| UI-WIN-004 | Province society | Culture, religion, unrest, conversion/suppression | Grey-box |
| UI-WIN-005 | Country overview | Identity, ruler, economy, military, diplomacy, alerts | Grey-box |
| UI-WIN-006 | Country economy/ledger summary | Income/expense/debt/maintenance/queues | Grey-box |
| UI-WIN-007 | Government/reforms | Authority, stability, reforms, government change | Grey-box |
| UI-WIN-008 | Technology | Three tracks, cost breakdown, unlock preview | Grey-box |
| UI-WIN-009 | Ideas/national direction | Groups, progress, requirements, effects | Grey-box |
| UI-WIN-010 | Culture/religion/internal state | Accepted cultures, tolerance, conversion, unrest | Grey-box |
| UI-WIN-011 | Subjects | Types, liberty/loyalty, integrate/release/create | Grey-box |
| UI-WIN-012 | Decisions | Requirements, cost, effects, availability/history | Grey-box |
| UI-WIN-013 | Diplomacy country view | Relationship breakdown and action groups | Grey-box |
| UI-WIN-014 | Declare war/war goal | Coalitions, goals, consequences, confirmation | Grey-box |
| UI-WIN-015 | War overview | Sides, score, participants, battles/sieges | Grey-box |
| UI-WIN-016 | Peace negotiation | Structured demands/offers and preview | Grey-box |
| UI-WIN-017 | Army selection card | Identity, strength, morale, route, actions | Grey-box |
| UI-WIN-018 | Military overview | Armies, manpower, recruitment, commanders, wars | Not started |
| UI-WIN-019 | Battle result | Sides, losses, modifiers, focus/history | Not started |
| UI-WIN-020 | Siege status/result | Progress, strength, modifiers, result | Grey-box |
| UI-WIN-021 | Court overview | Ruler, heir, succession, realm | Grey-box |
| UI-WIN-022 | Character sheet | Identity, skills, traits, family, titles, claims | Grey-box |
| UI-WIN-023 | Dynasty/family tree | Visible tree, navigation, history | Not started |
| UI-WIN-024 | Succession | Ranked order, law, prediction, warnings | Grey-box |
| UI-WIN-025 | Marriage/claim action flow | Candidates, requirements, consequences | Grey-box |
| UI-WIN-026 | Event popup | Image, flavour text, choices, outcomes | Grey-box |
| UI-WIN-027 | AI inspector (developer) | Strategy, plans, resources, threat, history | Grey-box |

## E. Release shell and quality-of-life screens

| ID | Screen | Status | Required before |
|---|---|---|---|
| UI-REL-001 | Nation selection | Not started | First-session/onboarding gate |
| UI-REL-002 | Full ledger | Not started | Phase 9 UI completion |
| UI-REL-003 | Outliner configuration | Not started | Phase 9 UI completion |
| UI-REL-004 | Notification feed | Not started | Phase 9 UI completion |
| UI-REL-005 | Message settings | Not started | Phase 9 UI completion |
| UI-REL-006 | Main menu | Not started | Packaged release |
| UI-REL-007 | Pause menu | Not started | Packaged release |
| UI-REL-008 | Display/interface/accessibility settings | Not started | Beta |
| UI-REL-009 | Audio and controls settings | Not started | Beta |
| UI-REL-010 | Save/load browser | Not started | Beta |
| UI-REL-011 | Loading/error/recovery screen | Not started | Beta |
| UI-REL-012 | Tutorial/context coach | Not started | Onboarding gate |
| UI-REL-013 | Help/glossary/controls | Not started | Onboarding gate |
| UI-REL-014 | Shared confirmation/error dialogs | Not started | Alpha hardening |
| UI-REL-015 | Credits/attributions/licences | Not started | Release candidate |
| UI-REL-016 | End-game/campaign summary | Not started | 1.0 decision required |

## F. Icon batches

Every icon entry needs a unique semantic name, original/licensed source, master, runtime export, and 16/24/32 px review.

### Core resources and map navigation

- Treasury, balance, debt, interest, manpower, development, stability/authority, legitimacy, war status.
- Political, terrain, tax, production, manpower, development, construction, relations, war, access, occupation, unrest, control, culture, religion, technology map modes.
- Search, focus, pin, close, help, collapse, expand, overflow.

### Economy and construction

- Tax, production, trade value, maintenance, ledger, building slot, construction, recruitment.
- Tax Office, Workshop, Barracks, every Phase 8 building family and tier.
- All trade goods listed by approved content definitions plus an explicit unknown-data icon.

### Diplomacy and warfare

- Relations, improve, alliance, access, truce, declare war, war goal, peace offer, white peace, attacker, defender, ally, subject, claim, core.
- Regiment/unit families, army strength, morale, movement, commander, battle, siege, occupation, victory, defeat, draw, disband.

### Government and society

- Government types, reforms/laws, administrative/diplomatic/military technology, idea groups.
- Culture, accepted culture, religion groups, tolerance, conversion, unrest, rebels, separatism, centralisation, subject types, liberty desire, integration.

### Characters and events

- Ruler, heir, consort, regency, dynasty, family, marriage, birth, age, illness, death, succession, claim, title, commander.
- Character skill and trait families.
- Event categories, decision, expiry, uncertain outcome, notification severity.

### Shell/accessibility

- Save, load, autosave, settings, controls, display, interface, accessibility, audio, tutorial, glossary, warning, error, recovery, credits.
- Colour-vision, high-contrast, reduced-motion, text/UI scale indicators.

## G. Content art batches

| ID | Batch | Quantity direction | Status |
|---|---|---:|---|
| UI-ART-001 | Approved country emblems/flags | Every playable country; individually researched and registered | Placeholder/incomplete |
| UI-ART-002 | Neutral missing-emblem treatment | 1 system with sizes | Not started |
| UI-ART-003 | Character portraits | 30–60 initial plus scalable pipeline | Placeholder |
| UI-ART-004 | Neutral missing-portrait silhouettes | Age/status variants as needed | Not started |
| UI-ART-005 | Event paintings/illustrations | 12–20 reusable initial categories | Not started |
| UI-ART-006 | Main-menu/background art | 1–3 approved compositions | Not started |
| UI-ART-007 | Tutorial diagrams/callouts | Produced from final controls, not early mockups | Not started |

## H. Audio feedback batch

- Hover tick, primary click, disabled action, window open/close, tab switch.
- Notification levels, event sting, war declaration, battle result, peace signed, succession/death.
- Source recording licence must be checked even when the underlying composition is public domain.
- All cues require volume-category routing and muted-play verification.

## I. Per-item research record template

Copy this block beneath the relevant batch or into a linked research document for each emblem, icon set, painting, portrait, texture, font, or sound:

```markdown
### [Asset ID] — [Exact asset name]

- Gameplay meaning:
- Countries/characters/events/screens using it:
- Historical date range represented:
- Historical source/reference URLs:
- Art source URL and archive/museum record:
- Creator and creation/publication date:
- Licence/public-domain statement:
- Required attribution text:
- Modifications made:
- Editable source file:
- Runtime export file:
- Native/runtime dimensions:
- Alpha/colour-space/import settings:
- Placeholder or final:
- Replacement trigger if placeholder:
- Visual review screenshots:
- Accessibility review:
- In-engine reviewer/date:
- Known issues:
```

“Transparent,” “historic,” “free online,” or “found on Wikimedia” is not adequate provenance. Record the exact object page, rights statement, author where known, modifications, and in-project file.

## J. Screen completion record template

```markdown
### [Screen ID] — [Screen name]

- Scene path:
- Owner/system:
- Primary player question:
- Primary action:
- Components used:
- Assets used:
- Normal/empty/loading/disabled/warning/error states:
- Minimum resolution result:
- UI-scale result:
- Long-localisation result:
- Mouse/keyboard/focus result:
- Colour-vision/contrast result:
- Performance capture:
- Packaged-build result:
- Screenshot evidence:
- P0/P1 issues:
- Approval status/reviewer/date:
```

## Next production checkpoint

The first checkpoint should approve only:

1. UI-FND-001 through UI-FND-005.
2. UI-CMP-001, UI-CMP-003, UI-CMP-005, UI-CMP-008, UI-CMP-010, UI-CMP-016, UI-CMP-021, and UI-CMP-024.
3. UI-HUD-001 through UI-HUD-005 in one in-engine top-bar prototype.
4. UI-WIN-001 in one in-engine province-window prototype.

Do not produce the entire icon catalogue or every major window until this checkpoint proves the direction at minimum resolution, multiple scales, and real gameplay performance.
