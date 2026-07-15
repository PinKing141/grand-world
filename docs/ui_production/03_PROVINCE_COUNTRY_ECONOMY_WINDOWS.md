# Province, Country, Economy, and Internal-State Windows

## Shared window rules

Every major gameplay window uses the same anatomy:

```text
identity/header + close/help
primary summary and urgent state
tabs or section navigation
scrollable content area
contextual actions
cost/consequence preview
confirmation only for destructive or irreversible actions
```

Windows must not expose raw database dumps. Present the decision first, then reveal breakdowns through tooltips and expanded sections.

## Province window

### Purpose

Answer: What is this place, who owns and controls it, what does it produce, what is happening here, and what can I do?

### Header

- Province name and optional province emblem/landscape thumbnail.
- Owner and controller with full country names and clickable identity.
- Capital marker, terrain, region, coastal/landlocked state.
- Occupied, besieged, wasteland, uncolonised, or invalid status when relevant.
- Focus-map and close controls.

### Overview tab

- Tax, production, manpower, development, control, devastation.
- Trade good and output.
- Culture and religion.
- Core/claim/subject relationship indicators.
- Current unrest and strongest contributing causes.
- Context-sensitive alert row.

### Economy/buildings tab

- Monthly tax and production with explainable breakdowns.
- Building slots used/total.
- Completed buildings with effects and removal rules.
- Construction queue with cost, start/end date, progress, pause/block state.
- Available building list grouped by purpose and technology requirement.
- Build/cancel actions with affordability and consequences shown before submission.

### Military/recruitment tab

- Manpower contribution and local modifiers.
- Recruitable unit types, money/manpower cost, time, and maintenance.
- Recruitment queue and progress.
- Fort/siege/occupation information when applicable.
- Armies present with selection shortcuts.

### Society tab

- Culture, culture group, accepted status, conversion progress/cost.
- Religion, tolerance, conversion progress/cost.
- Separatism, unrest, rebel faction, suppression/control actions.
- Clear locked reasons for unavailable actions.

### Required states

- Owned, allied/friendly, enemy, occupied, subject-owned, and observer views.
- Wasteland/non-playable land.
- Province with no available building slot.
- No construction/recruitment and full queues.
- Action blocked by money, manpower, technology, ownership, control, war, or cooldown.
- Province name and metadata longer than the normal width.

## Country overview window

### Purpose

Provide a readable strategic summary and navigation hub for the selected country.

### Header and identity

- Full country name, emblem/flag, country colour.
- Ruler/government summary.
- Capital, province count, subject/overlord state.
- At-war status and major warnings.
- Focus country, diplomacy, and close actions.

### Overview content

- Treasury, income/balance, manpower, debt.
- Stability/authority/legitimacy and technology summary.
- Government, primary culture, state religion.
- Military strength and active wars.
- Diplomatic relations and subjects.
- Current goals/decisions/alerts.

Player-owned and foreign-country versions should share structure but expose different actions. Never show controls that appear usable but secretly require player ownership; disable them with an exact explanation or omit them when they are irrelevant.

## Economy window

### Summary

- Treasury and monthly balance.
- Income and expense totals.
- Debt, interest, loan capacity, and repayment state.
- Manpower current/cap/change.
- Construction and recruitment queue counts.

### Ledger breakdown

Income groups may include tax, production, trade/future sources, events, reparations/future sources, and other adjustments. Expenses may include army maintenance, interest, construction/recruitment commitments, diplomatic/subject costs, events, and future systems.

Requirements:

- Signed amounts and subtotals must reconcile with the displayed monthly balance.
- Hover/click reveals source rows and modifiers.
- Tabular figures and decimal alignment are mandatory.
- Clearly distinguish current monthly flow from one-time reserved/paid costs.
- Cache/display the authoritative ledger; do not recalculate simulation rules in the UI.

### Controls

- Maintenance setting with projected effect.
- Take-loan and repay-loan actions with terms and confirmation where appropriate.
- Queue navigation to affected provinces.
- Economic map-mode shortcuts.

### Empty/error states

- No debt.
- Cannot take another loan.
- No owned provinces.
- No construction or recruitment.
- Ledger data unavailable or save data invalid: display a recovery message, never blank values that resemble zero.

## Government and internal-state window

The existing Country Depth panel combines several systems. The final interface may retain tabs within a single Country window or open dedicated windows, but it must maintain consistent navigation and avoid one enormous scrolling page.

### Government tab

- Government type and reform path.
- Ruler, legitimacy/authority, stability, and centralisation-related values.
- Current modifiers with source/duration.
- Available reforms with requirements, cost, preview, and lock reasons.
- Change-government action with consequences and confirmation.

### Technology tab

- Administrative, diplomatic, and military levels.
- Current cost and every modifier.
- Ahead-of-time or date-sensitive penalty.
- Unlock preview: buildings, units, reforms, formations, actions.
- Buy action and insufficient-resource explanation.
- Technology history/timeline where it improves understanding.

### Ideas or national-direction tab

- Available groups/paths.
- Progress and unlocked effects.
- Requirements, opportunity cost, and mutually exclusive choices.
- AI choice explanation only in debug/observer tools, not normal player presentation.

### Culture and religion tab

- Accepted cultures and capacity/rules.
- Religious composition and tolerance.
- Conversion actions and progress.
- Unrest and stability interactions.
- Map-mode shortcuts and province focus from affected lists.

### Subjects tab

- Overlord and subject type.
- Subject list with liberty desire/loyalty, strength, income, relations, integration state.
- Integrate, release, create/vassalise, and subject-management actions where valid.
- Exact requirements, progress, cancellation consequences, and diplomatic effects.
- French appanages and comparable historical subjects must remain separate owners while their subject relationship is visibly communicated.

### Events and decisions tab

- Active event, expiry date, choices, and predicted/known effects.
- Available, potentially available, and completed decisions.
- Requirements represented as labelled pass/fail rows.
- Cooldowns, one-time status, AI use, and historical-review status where relevant.

## Building and unit selection components

Do not use an unstructured dropdown as the final selection experience when entries need comparison. Use cards or a compact list with:

- Icon and full name.
- Purpose/category.
- Cost and build/recruit time.
- Resulting effect or unit statistics.
- Technology and province requirements.
- Lock reason.
- Current/queued marker.

For large lists, support category filters, sorting, and tooltips. Do not hide essential cost information only on hover.

## Data density rules

- Show at most one primary value per visual cell.
- Use labels; do not rely on icon memorisation for rare mechanics.
- Put formula breakdowns in tooltips or expandable sections, not tiny paragraphs.
- Use graphs only when a trend over time affects decisions and real history data exists.
- Use tables for comparison; use cards for identity and a small number of consequential choices.
- Keep action buttons close to the state they change.

## Art requirements for this family

- Major and utility window frames.
- Province and country header treatments.
- Emblem, trade-good, building, unit, government, technology, idea, culture, religion, core/claim, subject, unrest, and rebel icons.
- Tab family and section headers.
- Construction/recruitment/integration/conversion progress bars.
- Passed/failed requirement markers.
- Ledger row, table header, sorting arrows, positive/negative change glyphs.
- Empty-state illustrations or restrained icons where useful.

## Acceptance checklist

- Player can identify the province/country and its owner without relying on colour.
- Country name is never replaced by its internal tag.
- Ledger totals reconcile with source rows.
- All costs, durations, requirements, and lock reasons are visible before an action.
- Queue progress has an end date and blocked/cancelled state.
- Tabs preserve or intentionally reset selection.
- Lists scroll without moving the entire window off screen.
- Window fits supported minimum resolution and scale or switches to an approved full-screen layout.
- Every actionable value has a tooltip or visible breakdown.
- Foreign/observer/subject/occupied states have been tested.

