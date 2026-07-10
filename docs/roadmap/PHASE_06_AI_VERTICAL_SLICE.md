# Phase 6 — AI and Regional Vertical Slice

## Mission

Prove that the planned game can sustain a representative autonomous regional campaign at near-target quality.

## Production Gate

Vertical Slice.

## Recommended Slice

Iberia beginning on 11 November 1444:

- Castile.
- Aragon.
- Portugal.
- Granada.
- Navarre.

The exact roster may change after content and map validation, but the slice should remain approximately five countries and a controlled province count.

## Player Outcome

The player can choose one country and play a complete regional campaign involving economy, recruitment, movement, diplomacy, war, occupation, peace, and AI opponents.

## Entry Conditions

- War Loop Gate passes.
- Economy, movement, warfare, diplomacy, saves, and map UX are integrated.
- AI can issue the same commands as the player.

## Major Deliverables

### Strategic AI Framework

Pipeline:

~~~text
Observe
→ Evaluate
→ Select goal
→ Build plan
→ Score actions
→ Submit commands
→ Review outcome
~~~

### Economic AI

- Maintain reserve target.
- Recruit within maintenance budget.
- Construct buildings based on return and strategy.
- Take or avoid loans according to policy.
- Recover after war.

### Diplomatic AI

- Score alliances.
- Score military access.
- Select rivals or threats.
- Evaluate war declarations.
- Evaluate peace offers.
- Respect truces.

### Military AI

- Estimate relative strength.
- Group nearby forces.
- Define defensive and offensive objectives.
- Protect capital and war goal.
- Avoid clearly losing battles.
- Siege valuable provinces.
- Retreat and recover.

### AI Scheduling

- Tactical updates every few days.
- Strategic military planning weekly.
- Diplomacy monthly.
- Economy monthly.
- Long-term goal review quarterly.
- Countries distributed across schedule slots.

### AI Debugging

Provide:

- Current goal.
- Current plan.
- Scored alternatives.
- Rejected command reason.
- Per-country decision cost.
- Military objective overlay.
- Deterministic AI seed information.

### Representative UX

The slice should include representative quality for:

- Main HUD.
- Date and speed controls.
- Province and country panels.
- Army selection.
- Diplomacy.
- War overview.
- Peace screen.
- Economy ledger.
- Notifications.
- Map-mode bar.

### Representative Content

- Five countries.
- Province economy values.
- Capitals.
- Relationships.
- One or more historical tensions.
- Basic government and ruler placeholders.
- Representative buildings and unit definitions.
- Enough localisation to validate pipelines.

### Representative Presentation

- Approved map visual direction.
- Readable borders and highlights.
- Basic sound feedback.
- Music or ambience direction placeholder.
- Representative icons.
- Consistent interaction feedback.

### Campaign Goals

Provide:

- Country selection.
- Clear short-term objectives.
- At least one victory or campaign-completion condition.
- Defeat handling.
- End-of-campaign summary.

## Vertical Slice Exit Criteria

### Gameplay

- A player can complete the regional campaign.
- AI countries recruit, move, fight, occupy, negotiate, and recover.
- The economic and military loops create meaningful trade-offs.
- The player can understand important outcomes from UI explanations.

### Stability

- Repeated campaign runs do not corrupt state.
- Save and load work throughout the loop.
- A long unattended AI-only soak completes without a crash.
- No P0 or P1 defect remains open.

### Performance

- Reference hardware meets frame and simulation budgets.
- Maximum speed remains responsive.
- AI scheduling has no recurring major hitch.
- Memory does not grow continuously during soak tests.

### Pipeline

- A sixth country can be added through documented content steps.
- A new building, unit, event, and province value can be added without changing unrelated code.
- Data validation catches deliberate malformed test content.

### Production

- The team can estimate global content cost using measured slice throughput.
- Major design risks have evidence-based decisions.
- Alpha scope is updated using slice results.
- Deferred features remain explicitly deferred.

## Vertical Slice Review Questions

1. Is the country loop enjoyable without character depth?
2. Are economic decisions understandable?
3. Does war require meaningful planning?
4. Does AI create believable pressure?
5. Is the map easy to read at relevant zoom levels?
6. Can content be produced fast enough?
7. Can the game simulate decades without major degradation?
8. Which planned systems should be cut, simplified, or expanded?

## Primary Risks

- AI appears active but cannot pursue coherent long-term plans.
- UI is technically complete but does not explain the simulation.
- Content creation is too slow for global scale.
- The slice is polished with special-case code that cannot generalise.
- Character work begins before slice problems are resolved.

## Explicitly Out of Scope

- Full world content.
- Complete character and dynasty simulation.
- Final naval warfare.
- Complete technology and religion systems.
- Final balance.
- 1700–1821.
- Multiplayer.

