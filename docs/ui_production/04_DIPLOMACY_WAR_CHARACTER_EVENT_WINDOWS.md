# Diplomacy, War, Military, Characters, Events, and AI Windows

## Diplomacy country window

### Purpose

Explain the relationship between two countries and make legal diplomatic actions understandable before submission.

### Header

- Player and target emblems with full country names.
- Relationship score and attitude/status in words.
- War, alliance, subject, access, truce, royal/dynastic, and rival/threat markers.
- Focus target and return controls.

### Relationship breakdown

- Base relation and named modifiers.
- Modifier value, source, duration/expiry, and trend.
- Opinion should not be represented by a single unexplained number.

### Action list

Group actions into relations, agreements, subjects, covert/claims, and war/peace. Each action needs:

- Icon and full verb phrase.
- Availability and exact lock reason.
- Cost, duration, acceptance prediction, and consequence preview.
- Confirmation for war declarations, subject release, treaty-breaking, or other high-impact actions.

The existing improve relations, alliance, access, and conquest-war actions are the functional seed, not the complete production layout.

## Declare-war and war-goal window

Show:

- Attacker and defender coalitions.
- Chosen target and legal war goals.
- Goal province/claim/core context.
- Allies likely to join, decline, or be unable to join, with reasons.
- Truce/stability/relationship consequences.
- Relative military/economic estimate with uncertainty where appropriate.
- Confirmation action phrased explicitly: `Declare Conquest War` rather than `OK`.

Do not colour a dangerous declaration button like a normal navigation button.

## War overview

- War name, goal, start date, attacker/defender leaders.
- Participants grouped by side with emblem, strength, losses, occupation contribution, and participation.
- War score total and source breakdown.
- Battles, sieges, occupations, and goal control.
- Call/leave/peace status where systems support it.
- Focus-map shortcuts for significant battles, sieges, and target provinces.

## Peace negotiation

The production peace screen must replace one-click debug actions with a structured offer:

- Offer sender/receiver and current war score.
- Demand/concession categories.
- Province list/map selection with owner/controller/goal context.
- Cost, acceptance, overextension/relations/truce or equivalent consequences.
- Offer summary in plain language.
- Send, clear, white peace, accept, decline, and confirmation states.
- Incoming offers must show exactly what changes before acceptance.

No peace result should require the player to infer ownership changes from the map afterward.

## Army and military windows

### Army selection card

- Army name and country emblem.
- Location and current order.
- Regiment count, strength, morale, maintenance, commander.
- Route/destination and arrival estimate.
- Set/cancel destination, attach/split/merge where implemented, and disband with confirmation.
- Battle/siege/retreat/blocked states.

### Military overview

- Army list and totals.
- Manpower, force/capacity information, maintenance.
- Recruitment queues and unit definitions.
- Commanders and assignment.
- Active battles/sieges.
- Navigation to province recruitment and map focus.

### Battle result and siege popup

- Participants and side identity beyond red/blue alone.
- Starting/remaining strength, morale, losses, date/location, result.
- Important modifiers and commander effect.
- Focus map, dismiss, history access.
- Large-war stress state with many armies/battles must aggregate rather than create overlapping popups.

## Court and character window

### Realm summary

- Ruler portrait, full name, age, dynasty, title, health/status.
- Heir/succession summary and warning.
- Government/realm identity link.

### Character sheet

- Portrait and frame.
- Identity: name, birth/age, sex/gender representation as defined by the design, culture, religion, dynasty/house.
- Skills and traits with explainable effects.
- Family and close relationships.
- Titles, claims, command role, health.
- Opinion toward selected character with source breakdown.
- Marriage, claim, commander, or other valid actions with requirements.

### Dynasty/family and succession

- Succession order as a readable ranked list.
- Relationship lines or family tree loaded only for visible nodes.
- Current law/rule explanation.
- Legitimacy, short-reign, claim, and cadet-house effects.
- Predicted successor and clearly labelled uncertainty/conditions.
- Dead characters visually distinct but still inspectable where history requires it.

Portraits and heraldry must be replaceable content. A missing portrait uses a deliberate silhouette, never the word `PORTRAIT` in the release build.

## Event popup

### Anatomy

- Event category and title.
- Period-appropriate image with registered licence/provenance.
- Date/location/characters/countries as relevant.
- Readable flavour text.
- One or more choice buttons.
- Outcome preview according to the game's information policy.
- Expiry/automatic-choice state if applicable.
- History/log link.

### Rules

- Choice buttons use descriptive text, not `Option 1`.
- Known costs and effects must be visible before selection.
- If effects are intentionally uncertain, state that explicitly.
- Long event text scrolls inside the content area; choices remain reachable.
- Event art has one crop ratio, border treatment, and colour grade.
- Modal events obey pause rules and do not appear underneath other windows.

## Decisions list

- Available decisions first, then potentially available, then completed/history.
- Name, summary, requirements, cost, result, and one-time/repeat status.
- Pass/fail requirement rows.
- Focus relevant province/country/person where applicable.
- Search/filter if the content volume grows.

## Notifications and history

Events, battles, completed construction, recruitment, diplomatic offers, successions, and decisions should feed a common notification model. Each category may present differently, but should share title, timestamp, involved entities, body, severity, action, dismissal, and history retention rules.

## AI inspector: development only

The existing AI panel shows objective, strategy, plan, resources, threat, decisions, scheduling, and history. Keep it as a separate utility window with:

- Strong `DEVELOPER` marking.
- Searchable country selector.
- Copy/export diagnostics where useful.
- Objective map overlay.
- No ornamental production-art priority beyond legibility.
- Exclusion or secure hiding in normal release flow.

Never expose hidden AI knowledge to the player through a production diplomacy tooltip unless the design deliberately allows that information.

## Art requirements for this family

- Diplomacy action and relationship icons.
- Attacker, defender, ally, subject, truce, access, claim, core, war-goal icons.
- Army/regiment, strength, morale, movement, commander, battle, siege, occupation icons.
- War-score and peace-demand component art.
- Character portrait and dynasty frames; skill, trait, family, title, claim, marriage, illness/death/succession icons.
- Event parchment frame, image mask, choice buttons, requirement markers.
- Battle result victory/defeat/draw treatments that remain readable without colour.

## Acceptance checklist

- Every diplomatic action explains availability, cost, acceptance, and consequences.
- Declare war and peace cannot be confirmed accidentally.
- Both sides of a war are identifiable without attacker/defender colour alone.
- Army movement and blocked orders are understandable.
- A battle result does not require reading raw debug history.
- Succession order and predicted heir are clear.
- Missing portraits/heraldry have intentional neutral placeholders.
- Event choices remain accessible with long text and high UI scale.
- Large wars aggregate alerts and markers without destroying frame rate or readability.
- AI-only information remains in development tools.

