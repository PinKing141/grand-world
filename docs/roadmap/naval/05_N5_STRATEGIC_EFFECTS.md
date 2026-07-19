# 05 - N5 Strategic Naval Effects

**Status:** Validation - blockade eligibility/power, target resistance, contested zones, transition events, economy, war score, coastal siege, repair/construction effects, peace/extinction lifecycle, HUD/map feedback, and global-coast stress checks pass. The stable trade-protection output and final release evidence remain open.
**Depends on:** N1 ports/zones, N2 fleet missions/logistics, N4 hostile naval control  
**Unlocks:** complete maritime war loop and stable trade-network hooks

## Objective

Make naval presence matter outside naval battles through blockades, coastal siege assistance, economic pressure, port denial, and stable trade-protection outputs.

## Blockade Assignment

A fleet can contribute blockade power when:

- It is at sea in a zone adjacent to an eligible hostile coastal province/port.
- Its mission permits blockade.
- It is at war with the target owner/war side.
- It is not retreating, in port, destroyed, or otherwise inactive.
- Supply, maintenance, morale, and damage remain above defined minimum effectiveness.

Blockade is calculated from fleet/zone/target state, not written directly by UI. A fleet may affect multiple adjacent provinces, but power distribution and caps must prevent one small fleet from fully blockading an unlimited coastline.

## Blockade Power

Ship definitions provide base blockade power. Effective fleet power may include:

- Active eligible ships.
- Hull/crew effectiveness.
- Naval maintenance and morale.
- Admiral/blockade modifiers.
- Supply status.
- Mission efficiency.
- Sea-zone/port relationship.
- Enemy naval contest in the zone.

Target resistance may include:

- Coastal development/port importance.
- Harbour/fort/shipyard level.
- Defending fleet presence.
- Country, technology, building, and modifier hooks.
- Occupation/controller state.

The result is an integer blockade basis-point value with a breakdown. Values are clamped to `[0, 10000]`.

## Province and Port Effects

Approved minimum effects:

- Local coastal tax/production pressure through an explicit economy modifier.
- Reduced port repair/construction effectiveness at high blockade.
- Optional sailor recovery reduction.
- Port status and warning presentation.
- Contribution to war blockade score.

The economy ledger must show blockade losses as a named source. The modifier must be applied once; it cannot be baked into both province output and country aggregation.

## Coastal Siege Support

A coastal siege receives blockade assistance only when:

- The province is genuinely coastal and linked to the blockading zone.
- The fleet and besieger are on compatible war sides.
- Effective blockade meets the configured threshold.
- The port is not already controlled in a way that makes blockade irrelevant.

Possible bounded effects:

- Daily siege progress bonus.
- Removal/reduction of a coastal resupply penalty.
- Garrison recovery reduction if that mechanic exists.

The land warfare system remains siege authority. Naval publishes a blockade contribution query; it does not directly complete or occupy provinces.

## Contested Zones

- Opposing eligible fleets reduce or eliminate blockade contribution.
- An active naval battle pauses/contests power according to one explicit rule.
- Fleets cannot simultaneously provide full blockade while retreating or repairing.
- Multiple friendly fleets combine in stable fleet-ID order with any diminishing-return/cap rule applied once.
- Allies/subjects contribute according to war-side rules, while score attribution remains explainable.

## Blockade War Score

War state gains an explicit blockade component separate from battle and occupation score.

Requirements:

- Uses bounded daily/monthly accumulation rather than frame time.
- Attributes affected provinces and contributing fleets/sides.
- Cannot grow after peace or without an active eligible blockade.
- Releasing a blockade updates score according to approved retention/decay policy.
- Peace UI shows blockade contribution independently.

## Trade Protection Hook

N5 defines stable outputs for the later global trade system:

- Country.
- Fleet/mission.
- Sea zone or future trade-node mapping input.
- Effective light-ship protection power.
- Supply/maintenance/damage modifier.
- Active day/month.

Until the trade network exists, this output does not create fabricated trade income. The UI labels it as a future/strategic mission or limits the mission to test/debug contexts if no current benefit exists.

## Port Denial and Basing Interaction

- Fully hostile/occupied/blockaded ports must follow explicit docking, repair, and construction restrictions.
- Fleets already docked when access/ownership changes receive a forced-departure or internment rule.
- Blockade does not alter legal province ownership or controller directly.
- Basing rights do not protect a neutral host from consequences that diplomacy/war rules explicitly apply.

## Events and Queries

Minimum signals/queries:

- Blockade started/ended.
- Province blockade level changed across meaningful thresholds.
- Port fully blockaded/unblocked.
- War blockade score changed.
- Coastal siege support changed.
- Trade-protection output changed on monthly/mission boundaries.
- Query breakdown for UI, AI, economy, siege, and debug use.

Thresholded events avoid daily notification spam. Simulation may calculate daily while presentation updates only when materially changed.

## UI and Map Feedback

- Blockaded-port icon and sea-zone fleet mission marker.
- Coastal overlay or outline showing no/partial/full blockade.
- Fleet panel blockade power and affected targets.
- Province/port tooltip with required versus supplied power and economic/siege effects.
- War panel blockade score and top contributing areas.
- Economy ledger blockade-loss line.
- Alerts for important home ports, ongoing ship construction, or coastal sieges affected by blockade.

Colour is paired with icon, label, pattern, or percentage for accessibility.

## AI Requirements Introduced in N5

- Value blockades by war goal, development, port, siege, and economic impact.
- Avoid assigning blockade missions where enemy threat overwhelms the fleet.
- Contest blockades of important friendly ports.
- Prefer repairing or preserving transport capability over low-value blockade score.
- Reassign when target control/war/access changes.
- Produce a reason trace listing expected blockade value, danger, distance, and supply.

## Work Packets

- **N5A:** blockade eligibility/power query and reverse indexes.
- **N5B:** war score, contested-zone, and peace lifecycle.
- **N5C:** coastal siege integration.
- **N5D:** economy, repair/construction, sailor, and port-status effects.
- **N5E:** trade-protection contract, AI valuation API, UI, overlays, and alerts.
- **N5F:** accounting, replay, stress, balance, and global coast validation.

## Required Tests

- No/partial/full blockade thresholds and exact breakdown.
- Multiple friendly and opposing fleets.
- Damage, maintenance, morale, supply, mission, battle, retreat, and docking transitions.
- Coastal versus inland/non-port province eligibility.
- Siege bonus applies once and disappears correctly.
- Economy ledger reconciles before/during/after blockade.
- War score stops/updates correctly on battle, occupation, peace, and fleet departure.
- Save/load with active blockades preserves or deterministically rebuilds indexes.
- Trade hook output is stable and creates no income before trade activation.
- Full-coast calculation meets approved budget without all-country/all-zone scans.

## Exit Gate

N5 is complete when an English or French fleet can establish, contest, and lift a Channel blockade; the blockade changes a coastal siege and named economic ledger value, contributes bounded war score, survives save/load, and exposes a stable trade-protection interface without implementing the trade network prematurely.
