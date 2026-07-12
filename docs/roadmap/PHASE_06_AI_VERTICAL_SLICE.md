# Phase 6 — AI and Regional Vertical Slice

## Mission

Prove that the planned game can sustain a representative autonomous regional campaign at near-target quality.

## Production Gate

Vertical Slice.

## Current Status

**Validation.** The systemic Phase 6 implementation is integrated in build `0.6.0-phase6`. Automated gates pass for deterministic decision-making, economic/diplomatic/military commands, AI-state save/load replay, campaign UI, objective overlays, data validation, responsive layout, and the full 20-year unattended regional campaign.

The Vertical Slice gate is not labelled complete until hands-on balance, clarity, presentation, and packaged-build checks are approved.

## Implemented Foundation

- Data-driven profiles for Castile, Aragon, Portugal, Granada, and Navarre in `assets/ai_definitions.json`.
- Unique staggered scheduling slots for tactical, military, diplomacy, economy, and quarterly strategic reviews.
- Persistent goals, postures, target countries/provinces, reserve targets, force targets, recent orders, decision counts, and bounded histories.
- Economic AI for maintenance, reserve protection, recruitment, building investment, emergency borrowing, and debt repayment.
- Diplomatic AI for relations, alliances, military access, strength/risk-gated declarations, truces, offers, and peace acceptance.
- Military AI for capital defence, war-goal attack/defence, liberation, enemy engagement, route validation, retreat-aware caution, and anti-oscillation order memory.
- All autonomous actions pass through the existing authoritative player command API and its validation rules.
- Deterministic tie-breaking and replay; wall-clock profiling data is kept outside authoritative checksums.
- Country objectives, victory/defeat/completion states, observer completion, pause-on-player-finish, and an end summary.
- A Campaign & AI inspector showing goals, plans, threats, scored alternatives, rejection reasons, schedules, decision cost, deterministic seeds, and recent decisions.
- A military-objective map overlay for capitals, targets, and active destinations.
- Malformed AI profile validation and clear project-startup failure messages.

## Automated Evidence

- `tests/phase_6_ai_test.gd`: command coverage, player-country exclusion, rejection budget, malformed-data rejection, deterministic replay, save/load continuation, and bounded debug state.
- `tests/phase_6_integration_smoke.gd`: packaged main-scene integration, five-country UI, objectives, scheduled decisions, overlay restoration, and exact AI-state quick save/load.
- `tests/phase_6_regional_soak.gd`: full 7,305-day observer campaign, campaign summary, sustained decisions, warfare/peace/economy coverage, rejection budget, bounded AI caches, and second-half memory-growth budget.
- `tests/ui_layout_smoke.gd`: Campaign & AI panel containment at 1700×960 and 1152×648 windows.
- `tools/testing/run_all_tests.py`: unified Phase 1–6 regression, regional/global soaks, export-content verification, and exported-build startup.

## Adding a Sixth Regional AI Country

1. Ensure the country and its 1444 provinces exist in the scenario data.
2. Add one profile to `assets/ai_definitions.json` with a unique three-letter tag, owned capital, unused non-negative schedule slot, strategy, objective, targets/allies, and economic/military policy values.
3. Add any starting relationship records using tags that exist in the same profile file.
4. Run `tests/phase_6_ai_test.gd`; malformed tags, duplicate slots, missing capitals/strategies/objectives, and unknown country references fail validation.
5. Extend the controlled Iberian fixtures when the sixth country is required by the vertical-slice acceptance scenario.
6. Run `python tools/testing/run_all_tests.py` and complete a hands-on observer/player balance pass.

The planner, scheduler, debugger, campaign summary, and save system discover valid profiles from data; adding a country does not require a new AI code path.

## Remaining Validation Before Gate Approval

- Play complete campaigns as multiple Iberian countries and rate pressure, readability, pacing, and recovery.
- Tune country policy values, building returns, army targets, war thresholds, siege pacing, and peace behaviour from playtest evidence.
- Confirm AI decision cost and maximum-speed responsiveness on reference hardware with the graphical build.
- Review sound, music/ambience direction, icons, notifications, and final interaction feedback.
- Verify the Windows export using mouse/keyboard at supported resolutions and record known issues.
- Measure content-authoring throughput before committing to global AI/content production.

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
