# 06 - N6 Naval AI and UX

**Status:** Not started  
**Depends on:** complete N1-N5 player/API loop  
**Unlocks:** G1 Maritime First Playable and downstream global pillars

## Objective

Make the complete naval loop usable, explainable, performant, and autonomous. N6 does not hide missing simulation behind automation; it exposes approved N1-N5 commands to player and AI through stable decision and presentation layers.

## Fleet Missions

Minimum mission set:

- `none` / player-directed movement.
- `patrol`: maintain presence across an approved zone set.
- `intercept`: seek hostile fleets meeting risk rules.
- `protect_transport`: escort a carrier fleet/operation.
- `transport`: execute or remain assigned to transport operations.
- `blockade`: project power against selected war targets.
- `protect_coast`: contest threats near high-value friendly ports.
- `return_to_port`: forced/safe return.
- `repair`: remain docked until repair threshold is met.
- `trade_protection`: publish future trade power through N5 hooks.

Mission parameters, target IDs, legal states, cancellation, and completion conditions are saved. AI and player use the same mission command.

## AI Planning Layers

### Strategic naval posture

Per country, periodically determine:

- Whether the country is maritime-capable.
- Peace, threatened, wartime, invasion, recovery, or expansion posture.
- Affordable naval maintenance and construction budget.
- Desired heavy/light/galley/transport mix.
- Critical home ports/coasts and overseas objectives.
- Current transport deficit.

### Force construction

- Compare existing/queued ships with desired composition.
- Respect treasury reserve, sailors, technology, ports, and land-war needs.
- Prioritise transports only when an executable objective exists or a baseline reserve is justified.
- Avoid queue spam through cooldowns and stable construction slots.

### Operational allocation

- Group compatible ships into task fleets.
- Assign missions based on ports, war goals, blockades, transport operations, and threat.
- Maintain escorts and repair reserves.
- Avoid splitting below mission viability.

### Tactical daily decisions

- Continue, cancel, reinforce, evade, or retreat.
- Revalidate destination, access, supply, and danger.
- Protect carried armies.
- Do not recompute full strategy every day.

## Sea-Zone Threat Map

Threat evaluation uses cached, country-relative data:

- Known/eligible hostile fleet effective power.
- Recent battles and sightings if visibility depth is enabled later.
- Enemy ports and likely reinforcement.
- Blockades and transport stakes.
- Distance and supply from friendly base.
- Friendly support arrival time.

The first implementation may use complete information if fog-of-war naval visibility is deferred, but the API must allow later visibility filtering. Threat maps update on staggered schedules and material fleet/war events.

## Engagement Safety

AI must compare conservative effective power, not raw ship count. Decisions consider:

- Class matchup and sea class.
- Morale, hull, maintenance, and supply.
- Admirals and positioning estimate.
- Transport burden/value.
- Reinforcement arrival.
- Retreat destination availability.
- Objective value.

Hard safety bounds prevent routine attacks at overwhelmingly negative ratios unless a documented high-value desperation rule applies.

## Transport Planning

AI transport planning is an atomic objective chain:

1. Select legal origin army and destination objective.
2. Confirm strategic value and land-access consequence.
3. Find sufficient transports and escort.
4. Find supplied route and acceptable threat.
5. Reserve operation through the normal command.
6. Monitor interruption, loss, destination invalidation, and recovery.
7. Disembark and hand the army back to land AI.

The AI cannot issue movement to an overseas province and assume transports appear. Failed candidates record the missing capacity, access, route, escort, or risk reason.

## Explainable AI Traces

Each naval decision record includes:

- Country, day, category, posture, action, and target IDs.
- Candidate score and selected score.
- Treasury/sailor/maintenance constraints.
- Friendly/enemy effective power.
- Distance, supply, and route danger.
- Objective value.
- Rejection reason for major alternatives.
- Next planning day/cooldown.

Debug UI can show the last decision and bounded candidate list. Traces are deterministic and excluded from authoritative checksum only if they are purely derived; any saved AI schedule/state must be included.

## Player Information Architecture

### Campaign shell

- Add a Naval tab next to military/economy/diplomacy entry points.
- Add sailors and naval maintenance to the resource/ledger surfaces.
- Add fleets, construction, transport, damaged fleets, and blockades to the outliner/alerts.

### Fleet marker layer

- Use the existing original navy atlas icon and stable fleet anchor.
- Pool/batch markers; no node per ship.
- Cluster dense co-located fleets while preserving owner/war/mission cues.
- Marker click selects fleet or opens a deterministic cluster list.
- Zoom LOD retains strategic visibility without covering coastlines.

### Fleet panel

- Identity, owner, admiral, location/home port, mission, destination, and arrival.
- Total ships and class breakdown.
- Hull, morale, sailors/crew, speed, range, supply, blockade, transport capacity/reservation, and maintenance.
- Split, merge, transfer, move, mission, repair, home-port, admiral, scuttle, and transport controls as allowed.
- Exact disabled reason on unavailable controls.

### Port and construction panel

- Port level, exits, owner/controller/access, supply/repair capability.
- Ship definitions grouped by family with unlock, cost, sailors, time, maintenance, and role.
- Queue status, completion date, cancellation/refund explanation.
- Blockade/occupation impact.

### Transport workflow

- Select army/fleet or use a guided assignment modal.
- Required/available/reserved capacity.
- Origin/destination legality, route, days, supply, danger, escort, and landing penalty.
- Shared operation state visible from both army and fleet panels.

### Naval battle/report

- Participant fleets/countries/commanders.
- Positioning and major modifiers.
- Class counts, active/reserve ships, hull and morale.
- Daily and cumulative losses, captures, sinks, and carried-army casualties.
- Retreat timing/destination.
- Final war-score and strategic consequence summary.

### Map modes and overlays

- Naval range/supply.
- Sea-zone danger/control.
- Ports and shipyards.
- Blockades and affected coasts.
- Fleet mission/route preview.

These may be overlays within the existing map-mode architecture rather than permanent new full map modes where that is clearer.

## Accessibility and Input

- Never rely on colour alone for owner, danger, blockade, supply, or battle side.
- Provide icon/shape/text/percentage companions.
- Keyboard focus order for every panel and modal.
- Escape closes the top naval modal safely without issuing/cancelling an order.
- Tooltips have concise first line and expandable calculation breakdown.
- Layout passes 1366x768, 1920x1080, 16:10, and approved ultrawide targets.
- UI scaling does not hide confirmation/rejection text.
- Animations are presentation-only and respect reduced-motion settings when available.

## Notifications

Required grouped notifications:

- Ship construction complete/cancelled/blocked.
- Fleet arrived/blocked/unsupplied/attrition threshold.
- Fleet needs repair or lacks home port.
- Transport ready/intercepted/lost/destination invalid/completed.
- Naval battle started/ended.
- Important port blockaded/unblocked.
- Idle fleet or unused transport capacity only when actionable.

Notification rate limiting and severity prevent daily combat/attrition spam.

## AI Content Rollout

1. England and France Channel fixture.
2. Portugal, Castile, and Aragon integrated into the existing Iberian slice.
3. Representative Venice/Genoa/Ottoman Mediterranean fixture if approved for validation.
4. Generic maritime fallback for all countries with eligible ports.
5. Worldwide tuning only after performance and historical content gates.

## Work Packets

- **N6A:** mission command/state machine and shared evaluation APIs.
- **N6B:** strategic posture, force construction, and fleet organisation AI.
- **N6C:** threat map, tactical decisions, retreat/repair/blockade AI.
- **N6D:** atomic transport-objective AI and land-AI handoff.
- **N6E:** naval tab, fleet/port/transport/battle panels, outliner, and notifications.
- **N6F:** marker layer, overlays, accessibility, resolution matrix, and input polish.
- **N6G:** global fallback, soak, performance, balance, export, and G1 evidence.

## Required Tests

- AI uses only commands and produces stable traces.
- Same seed yields identical construction, mission, transport, battle, and retreat decisions.
- AI avoids documented suicidal thresholds and preserves transports appropriately.
- AI can recover from access loss, destroyed fleet, blocked port, insufficient sailors, debt, and invalidated objectives.
- Player preview and command validation agree on every naval action.
- All panels refresh after events/save load without mutating state.
- Marker clustering/clicks select the correct authoritative fleet.
- UI containment/focus/tooltips pass supported resolutions.
- Notification grouping/rate limits pass long battle and attrition fixtures.
- Full-world AI scheduling meets approved daily/monthly CPU budget.
- Exported build contains data, markers, UI, and can complete the Channel flow.

## Exit Gate

N6 and G1 complete when a player and AI can execute the Channel construction/movement/transport/interception/battle/blockade/repair loop, understand every result, save/load mid-operation, complete 100 seeded repetitions without invalid state or desync, and remain inside approved global simulation and rendering budgets.
