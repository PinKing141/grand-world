# 03 — Existing-System Depth

These systems already have working foundations. The goal is to deepen them without destabilising the deterministic architecture or turning every mechanic into an unbounded simulation.

## Warfare

### Already present

Land movement, commanders, terrain inputs, morale, reinforcement, retreat, sieges, occupation, war score and peace form a working war loop.

### Remaining depth

- Combat width, front/reserve rules and era-dependent unit roles.
- Crossing, river, amphibious and defensible-terrain modifiers with clear previews.
- Attrition, supply limit, reinforcement access and winter/climate effects.
- Mercenary companies or a deliberately smaller mercenary abstraction.
- Fort zone-of-control and movement restrictions, if approved for the design.
- General/admiral skill effects that are visible and explainable.
- Army composition templates, detach siege and consolidate/regroup QoL.
- War participation, separate peace, call-to-arms reasons and richer peace terms.
- Large-war performance testing with hundreds of armies and multiple fronts.

### Exit gate

Players must be able to predict why a battle was won or lost from the battle interface, AI must respect supply and defensive terrain, and a large multi-country war must stay within simulation and UI frame budgets.

## Diplomacy

### Already present

Relations, alliances, military access, wars, peace, subjects and personal-union foundations exist.

### Remaining depth

- Royal marriage into succession/personal-union gameplay.
- Aggressive expansion or equivalent threat accumulation.
- Coalitions, guarantees and defensive responses.
- Trust, favours, debt willingness and reasons-based AI acceptance.
- Rivalry, sphere/interest logic and great-power interventions if in scope.
- Defensive, trade or religious leagues where historically/systemically appropriate.
- Better subject interactions, liberty pressure and integration rules.
- Diplomatic feedback that exposes every acceptance modifier.

### Exit gate

Expansion must create understandable regional responses, alliances must not be trivially exploitable, succession diplomacy must produce valid unions, and every diplomatic refusal must show a complete reasons breakdown.

## Estates and Internal Power

### Already present

A basic three-estate structure and country stability/unrest foundations exist.

### Remaining depth

- Estate influence, loyalty and equilibrium.
- Crownland or an approved state-versus-estate power abstraction.
- Privileges with benefits, costs and revocation conditions.
- Estate agendas, incidents and recurring political choices.
- Estate effects on tax, manpower, conversion, recruitment and reform.
- AI rules that avoid both permanent neglect and mechanical exploitation.

### Exit gate

Estates must create meaningful medium-term trade-offs, integrate with the economy/unrest/government systems, survive succession and save/load, and remain manageable through clear alerts and tooltips.

## Government and Internal Politics

### Already present

Government family/reform data, country stability, unrest, control and rebellion foundations exist.

### Remaining depth

- Distinct monarchy, republic, theocracy and horde mechanics.
- Legitimacy, republican tradition, devotion, tribal unity or approved equivalents.
- Parliaments, factions or councils for selected governments.
- Government-specific succession, reforms and crisis states.
- Reform progress/cost, respec rules and AI selection.
- Internal politics connected to estates, characters and provincial control.

### Exit gate

Playing two different government families must require meaningfully different decisions, and generated/fallback governments must still receive a coherent minimal loop.

## Economy

### Already present

Province income, production, manpower, buildings, recruitment, maintenance, loans and construction are connected.

### Remaining depth

- Manufactories and trade-network integration.
- Inflation, interest pressure, bankruptcy recovery and monetary decisions if retained.
- Subsidies, war reparations, transfer trade power and economic peace terms.
- Production efficiency and scarcity tuning by trade good.
- Development cost, devastation/prosperity and long-run regional recovery.
- Clear monthly-income ledger with explainable deltas.
- AI spending priorities that remain solvent across peace and war.

### Exit gate

Country budgets must remain strategically constrained through 100-year soaks, income changes must be explainable to the player, and dominant building/loan exploits must be addressed by repeatable balance tests.

## Technology, Ideas and Institutions

### Already present

Administrative, diplomatic and military technology tracks, national-direction data and idea-group foundations exist.

### Remaining depth

- Institutions or another approved mechanism controlling regional technology pace.
- Era-appropriate unit, building, government and mechanic unlock waves.
- Technology penalties/catch-up rules that do not produce permanent irrelevance.
- Idea-group choice, completion policies and AI strategy.
- Country-specific national ideas for worldwide content.
- Ahead-of-time, neighbour and ruler/advisor effects if retained.
- Clear tooltips explaining cost and next-level consequences.

### Exit gate

Technology pace must stay within the approved historical bands from 1444–1700, region gaps must be tunable rather than hard-coded, and unlocks must never invalidate existing saves or unit data.

## Cross-System Depth Gate

System depth is approved only when:

- mechanics interact through stable interfaces rather than direct hidden coupling;
- AI can use the same actions as the player;
- every modifier has an inspectable source;
- new state is covered by save migration and determinism tests;
- regional balance sessions confirm decisions are meaningful rather than merely numerous;
- complexity budgets prevent the UI from becoming unreadable.

