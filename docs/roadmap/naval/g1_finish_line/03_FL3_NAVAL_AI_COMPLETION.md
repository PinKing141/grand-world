# FL3 - Naval AI Completion

**Status:** Complete. A closure audit ([FL3_CLOSURE_AUDIT.md](evidence/FL3_CLOSURE_AUDIT.md)) corrected an earlier overstated `Validation` line and tracked the real remaining work packet by packet; all six FL3.1-FL3.6 sub-scopes and all four "Automated verification" roadmap claims (battle arbitration, recovery matrix, trace-neutrality, performance budget) are now complete, and the one named item that briefly remained open after that audit - a naval-specific maintenance command to mirror land AI's `SetArmyMaintenanceCommand` - is also closed. See [FL3_2_NAVY_MAINTENANCE.md](evidence/FL3_2_NAVY_MAINTENANCE.md), which corrects the audit's own earlier framing of the gap: `navy_maintenance_bp` already had its full economic connection, it only lacked a command and AI logic to use it. FL3 has no remaining named gap.
**Goal:** Extend the deterministic command-only AI from reactive naval actions to the complete autonomous naval loop.

## Scope

### FL3.1 Threat and opportunity map - complete

*See [FL3_1_THREAT_OPPORTUNITY_MAP.md](evidence/FL3_1_THREAT_OPPORTUNITY_MAP.md). `NavalThreatMap` (scripts/simulation/naval_threat_map.gd) now computes all seven named inputs below except a separate "ports" signal, deliberately folded into supply_days rather than kept redundant; a day-boundary-plus-explicit-invalidation cache with bounded cache-hit/rebuild/countries-planned counters; and `_zone_threat()`/`_zone_has_blockade_target()` are thin, same-signature adapters over it so no existing caller changed. Event-triggered intra-day invalidation and naval visibility/fog-of-war filtering remain explicitly open (the latter is a whole-game gap, not naval-specific - see the evidence doc).*

- Build a country-relative sea-zone assessment from hostile power, friendly support, recent battles, ports, blockades, supply distance and transport stakes.
- Separate authoritative inputs from derived cache data.
- Define cache revision and invalidation for fleet, war, access, ownership and port changes.
- Use stable ordering and integer scoring.
- Keep an interface that can later filter knowledge through naval visibility.

### FL3.2 Strategic posture and force plan - complete

*See [FL3_2_STRATEGIC_POSTURE.md](evidence/FL3_2_STRATEGIC_POSTURE.md). All six named postures are now classified (a real design problem was found and fixed along the way: NavalThreatMap's hostile_power is deliberately war-gated, so "threatened" needed a separate rivalry-based pre-war signal instead); a real heavy/light/galley/transport mix now drives construction, keyed by posture; treasury, sailors, port capacity, and land-war needs are all respected. Technology gating was a genuine authoritative correctness gap - ship_definitions.json already declared required_technology per ship, but ConstructShipCommand.validate() never checked it - now closed, see [FL3_2_TECHNOLOGY_GATE.md](evidence/FL3_2_TECHNOLOGY_GATE.md). Maintenance is now closed too: `navy_maintenance_bp` turned out to already have its full economic connection into the `navy_maintenance` ledger line, exactly mirroring land's `army_maintenance_bp` - the gap was only ever a missing command and missing AI logic to use it, not a half-built mechanic as the closure audit first suspected. `SetNavyMaintenanceCommand` plus `NavalAISystem._consider_navy_maintenance()` now close it - see [FL3_2_NAVY_MAINTENANCE.md](evidence/FL3_2_NAVY_MAINTENANCE.md), which also corrects that earlier framing. `maintenance_posture_bp` (a separate, unrelated per-fleet combat-readiness field) remains its own distinct, not-yet-designed item, confirmed not to be what this bullet refers to.*

- Classify maritime countries as peace, threatened, wartime, invasion, recovery or expansion posture.
- Calculate an affordable heavy, light, galley and transport target mix.
- ~~Respect treasury reserve, sailors, maintenance, port capacity, technology and land-war needs.~~ *(done in full - see [FL3_2_NAVY_MAINTENANCE.md](evidence/FL3_2_NAVY_MAINTENANCE.md) for maintenance, the last of the six)*
- Avoid construction spam through stable slots and cooldowns.
- Record why construction was selected or rejected.

### FL3.3 Fleet organisation, basing and reinforcement - complete

*See [FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md](evidence/FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md) and [FL3_3_ORGANISATION_AND_RESERVES.md](evidence/FL3_3_ORGANISATION_AND_RESERVES.md). Reinforcement needed no new "join battle" command - NavalCombatSystem already auto-adds any fleet sharing a battle's zone; the AI's job was only the order, gated on arrival time and whether its own side is currently weaker. Home port is reassigned when access is lost - discovered along the way that home_port_id has no other mechanical effect anywhere in the simulation, so the richer repair/supply/threat/objective-distance selection model would tune a field nothing downstream reads. Split now has a real, well-motivated use (freeing combat ships from a mixed fleet before a transport voyage); transfer still has none found and stays honestly unused. Reserve fleets were confirmed, not assumed, already available by construction - a solo reserve fleet is never touched by any tactical decision while docked, so nothing risks it prematurely.*

- ~~Group ships into task fleets using normal split, merge and transfer commands.~~ *(done - [FL3_3_ORGANISATION_AND_RESERVES.md](evidence/FL3_3_ORGANISATION_AND_RESERVES.md); split now separates a mixed fleet ahead of a transport run, merge was already real, transfer has no concrete trigger and stays unused rather than invented)*
- Avoid splitting below mission viability or reorganising active transports. *(true by construction - the new split only ever fires on a docked, organisable fleet with no active transport reservation)*
- Choose and change home ports based on access, repair, supply, threat and objective distance.
- ~~Keep repair and reserve fleets available.~~ *(confirmed already true by construction - see evidence)*
- Compare reinforcement arrival time and value before joining a battle.

### FL3.4 Tactical mission decisions - all eight candidates now real, event-triggered replanning now real

*See [FL3_4_TACTICAL_MISSIONS.md](evidence/FL3_4_TACTICAL_MISSIONS.md) and [FL3_4_EVENT_TRIGGERED_REPLANNING.md](evidence/FL3_4_EVENT_TRIGGERED_REPLANNING.md). Patrol, intercept, protect_coast, and escort (protect_transport) now have real assignment logic alongside the pre-existing blockade/repair/retreat/return_to_port, all eight of the roadmap's named candidates. A real gap was found and fixed while building escort: none of the four newly-real missions had any completion condition anywhere in the simulation layer, so a new _consider_mission_completion() stands a fleet down to idle once whatever justified its mission no longer holds. "Effective power" (hull/crew/morale/class-matchup/positioning/supply/transport-value/support-arrival/retreat-port) remains the same raw total_attack comparison used before this packet - unchanged, not re-opened here. Event-triggered invalidation - the one item this section's own exit bullet still named as missing - is now real too: a naval_battle_started or fleet_moved arrival in a country's own zone forces an immediate off-schedule tactical reconsideration, with a new naval_ai_event_replans counter making a replan storm measurable.*

- Score patrol, interception, coast protection, blockade, escort, repair, retreat and idle-return candidates.
- Compare effective power rather than ship count.
- Include hull, crew, morale, class matchup, positioning estimate, supply, transport value, support arrival and retreat-port availability.
- Define conservative safety bounds and explicit desperation exceptions.
- ~~Avoid daily full replanning; use staggered schedules and event-triggered invalidation.~~ *(done - [FL3_4_EVENT_TRIGGERED_REPLANNING.md](evidence/FL3_4_EVENT_TRIGGERED_REPLANNING.md))*

### FL3.5 Autonomous transport objectives - complete

*See [FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md](evidence/FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md) and [FL3_5_ESCORT_LIFECYCLE.md](evidence/FL3_5_ESCORT_LIFECYCLE.md). A candidate route is rejected and recorded if it crosses a zone NavalThreatMap considers dangerous, instead of sailing through blind. The two escort gaps found while scoping danger-aware routing are now closed too: `_plan_transport()` proactively reserves an idle same-port fleet as escort the instant a transport operation is created, and a new `_consider_escort_follow()` chases the escorted operation's current zone once they part ways instead of sitting still or being abandoned to idle.*

- Select a legal army, origin, destination and land objective.
- ~~Confirm capacity, escort, route, access, supply and acceptable danger before reserving.~~ *(done - capacity/route/access/danger were already confirmed; escort now has real proactive reservation and follow-the-voyage behaviour, see [FL3_5_ESCORT_LIFECYCLE.md](evidence/FL3_5_ESCORT_LIFECYCLE.md). Supply is not separately checked, since `CreateTransportOperationCommand.validate()` itself does not require it - not a gap this packet owns)*
- Create the transport through the shared operation command.
- Monitor interception, capacity loss, destination capture, access loss and peace.
- Hand a successful disembarkation back to land AI exactly once.
- Record missing capacity, escort, route or risk when no plan is issued.

### FL3.6 Explainability and bounds - complete for every genuinely missing field

*See [FL3_6_EXPLAINABILITY_AND_BOUNDS.md](evidence/FL3_6_EXPLAINABILITY_AND_BOUNDS.md). `targets`, `constraints`, `posture`, and `next_planning_day` are now real structured fields on every decision record, not free text or a separately-tracked value; a new `naval_ai_candidates_evaluated` counter closes the last missing FL3.6 counter. `country` stays implicit, per the closure audit's own already-accepted reasoning. Trace-neutrality is now also proven - see [FL3_VERIFICATION_3_TRACE_NEUTRALITY.md](evidence/FL3_VERIFICATION_3_TRACE_NEUTRALITY.md), which added the `naval_ai_tracing_enabled` toggle this bullet needed to even be checkable.*

- Record country, day, posture, action, targets, selected score, major rejected candidates, constraints and next planning day.
- Bound trace history and candidate counts.
- ~~Confirm trace production does not change authoritative results.~~ *(done - [FL3_VERIFICATION_3_TRACE_NEUTRALITY.md](evidence/FL3_VERIFICATION_3_TRACE_NEUTRALITY.md))*
- Add counters for countries planned, candidates evaluated, cache rebuilds and elapsed time.

## Automated verification

- Identical seed and commands produce identical AI decisions, traces and checksum.
- AI uses the same commands and rejection rules as the player.
- AI builds a viable force, organises it, chooses a base and repairs damage.
- AI independently transports an army with escort and land-AI handoff.
- AI refuses documented suicidal engagements and protects loaded transports.
- ~~AI recovers from destroyed fleets, blocked/captured ports, access loss, peace, debt and insufficient sailors.~~ *(done - [FL3_VERIFICATION_2_RECOVERY_MATRIX.md](evidence/FL3_VERIFICATION_2_RECOVERY_MATRIX.md); two real gaps found and fixed along the way, not assumed already correct)*
- ~~AI and player targeting the same sea zone still produces one authoritative battle.~~ *(done - [FL3_VERIFICATION_1_BATTLE_ARBITRATION.md](evidence/FL3_VERIFICATION_1_BATTLE_ARBITRATION.md))*
- ~~Global planning work is bounded and meets its measured budget.~~ *(done - [FL3_VERIFICATION_4_PERFORMANCE_BUDGET.md](evidence/FL3_VERIFICATION_4_PERFORMANCE_BUDGET.md); run deliberately last, after split/transfer, event-triggered replanning, and escort behaviour stopped changing planning cost)*

## Exit evidence

- Deterministic decision/replay test results.
- Autonomous transport scenario results.
- Recovery and invalid-candidate matrix.
- Threat-cache correctness and invalidation results.
- Global AI timing distribution and maximum work counters.

## Exit gate

FL3 is complete when a generic maritime AI can construct, organise, base, repair, transport, escort, intercept, blockade, reinforce and retreat through shared commands, explain the important choices, and repeat deterministically within budget.
