# 01 - N1 Maritime Graph Authority

**Status:** Validation - N1.1-N1.4 implemented and test-backed; see [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) and its evidence/ folder. Cache/invalidation deferred (no cacheable state exists yet).  
**Depends on:** N0 architecture lock (approved 2026-07-17)  
**Unlocks:** fleet movement, basing, supply, transport, interception, exploration, and trade-route hooks

## Objective

Turn existing coast and water metadata into one validated, deterministic runtime graph for ports and fleets. N1 contains no combat and no economic fleet loop. Its product is trusted geography plus explainable path and access results.

## Inputs

- `assets/province_graph.json` water classification, anchors, bounding boxes, sea neighbours, land neighbours, coast flags, and straits.
- Stable province IDs and names.
- Country ownership/controller state.
- Existing military access, alliance, subject, and war relationships.
- Map graph build and override pipeline.

## Planned Runtime Responsibilities

The maritime graph API must provide:

- `is_sea_zone(id)` and sorted `sea_zone_ids()`.
- Sorted `sea_neighbors(id)` with integer travel weights.
- `is_port_province(id)` and sorted `port_province_ids()`.
- `port_exits(port_id)` returning adjacent sea zones.
- `sea_zone_ports(zone_id)` returning adjacent ports.
- `is_coastal_land(id)` without treating water or impassable records as ports.
- Sea-zone and port anchors for markers and route presentation.
- Strait metadata, water type, and authored movement modifiers.
- Stable connected-component and nearest-port queries.
- Deterministic route finding with access, range, and risk explanations.

The existing `ProvinceGraph` can expose raw topology while a `MaritimeGraph` or equivalent focused service owns naval path/access logic. There must still be only one baked topology authority.

## Port Derivation

A baseline port candidate must:

- Be a playable land province.
- Be marked coastal.
- Have at least one valid sea neighbour.
- Have a valid owner/controller entry in the campaign scenario when active.
- Not be marked impassable or excluded by an override.

Derived eligibility is not enough for release content. A versioned port-definition table will provide:

- Port enabled/disabled override.
- Primary sea exit when multiple exits exist.
- Harbour level.
- Shipyard capability.
- Repair and basing capacity modifiers.
- Supply-range contribution.
- Coastal/inland-sea classification.
- Historical/provenance/review status.

Port state uses the province ID. Definitions must reject duplicate port records and references to non-coastal or unknown provinces.

## Sea-Zone Classification

The first implementation needs a bounded classification set:

- `coastal_sea`: adjacent to land; normal galley and blockade rules.
- `inland_sea`: authored subset with stronger galley relevance.
- `open_ocean`: increased supply/attrition exposure and later exploration relevance.
- `closed_water`: lake or non-navigable water excluded from ordinary fleets.

Classification belongs in external data or generated metadata with overrides. It must not be guessed each campaign from country ownership.

## Movement Costs

Movement cost is an integer number of days per leg. It may include:

- Baked geographic distance or shared-boundary proxy.
- Origin/destination water class.
- Fleet slowest-ship speed.
- Admiral manoeuvre modifier.
- Supply or mission modifier where explicitly allowed.

N1 pathfinding receives an abstract fleet-speed profile so N2 can use it without changing the graph. Equal-cost routes choose the lowest stable zone ID at each tie.

## Access and Basing Rules

N1 must separate three questions:

1. **May the fleet sail through this sea zone?** Usually yes, unless closed water, a closed strait, or a future explicit restriction applies.
2. **May it enter this port?** Requires ownership, alliance/subject permission, explicit naval access, fleet basing rights, or wartime occupation rules.
3. **Does this port provide supply and repair?** Requires basing rights, not merely transit access.

Required relationship concepts:

- `naval_access`: permits defined naval transit/docking behaviour.
- `fleet_basing_rights`: permits supply, repair, and home-port use, normally with diplomatic/economic cost later.
- Allied/subject permissions derived through one central policy function.
- Hostile occupied ports handled explicitly; ownership and controller must not be conflated.

Access changes during movement do not teleport a fleet. Each next leg is revalidated. An invalid route becomes blocked at the last legal zone or begins a deterministic retreat if battle/war rules demand it.

## Supply Range Query

N1 provides the query; N2 applies attrition and repair rules.

For a country and sea zone, return:

- Whether supplied.
- Nearest legal supply port.
- Weighted range cost.
- Maximum allowed range.
- Route used for the result.
- Exact failure reason.

Owned, controlled, allied, subject, and basing-right ports must be evaluated in sorted order. Results may be cached by country/access revision and invalidated when ownership, control, diplomacy, port state, or technology changes.

## Route Result Contract

Every path query returns a structured result:

- `exists`.
- `path` including origin and destination.
- `total_days`.
- `origin_kind` and `destination_kind`.
- `uses_port_exit` / `uses_port_entry`.
- `supplied_at_destination`.
- `range_cost` and `range_limit`.
- `blocked_reason_code`.
- Human-readable `failure_reason`.

Presentation and commands must call the same route API. The UI must never preview a route the command system would reject.

## Build and Validation Tooling

The graph pipeline must report:

- Total navigable zones, closed water records, and ports.
- Connected components and isolated zones.
- Ports without exits and zones without reciprocal neighbours.
- Invalid land-water, water-water, and strait references.
- Duplicate or conflicting overrides.
- Port anchors outside the source province.
- Major scenario port-to-port path checks.
- Channel, Gibraltar, Baltic entrance, western Mediterranean, and Atlantic connectivity fixtures.
- A stable graph content hash included in test evidence.

Generated reports belong under `docs/data/` or the naval test-report folder and must be reproducible from source data.

## Debug and Presentation Tools

- Naval graph debug overlay with zone IDs, connections, port exits, and classifications.
- Route preview with supplied/unsupplied leg colouring.
- Selected sea-zone/port diagnostic card.
- Access explanation showing the exact relationship or restriction used.
- Console/test trace containing sorted path, cost, range, and tie-break decisions.

These are development tools; final art is not required for N1.

## Work Packets

### N1A - Data audit

- Inventory water, coastal, sea-neighbour, strait, lake, and isolated records.
- Approve classification/override format.
- Record known geography limitations and provenance risks.

### N1B - Runtime graph API

- Expose sorted maritime topology and anchors.
- Add deterministic port/sea pathfinder and structured result.
- Add central access and basing policy queries.

### N1C - Port/classification content

- Produce candidate ports.
- Add reviewed overrides for the Channel and Iberian test region.
- Mark lakes and non-navigable water closed.

### N1D - Tooling and presentation

- Add validator report, debug overlay, and route explanation.
- Verify route preview equals command validation.

### N1E - Gate tests

- Run determinism, malformed-data, save-independent graph, performance, and export-content checks.

## Required Tests

- Same path for repeated calls, frame rates, game speeds, and machines.
- Stable equal-cost tie handling.
- No asymmetric navigable edge.
- Every enabled port reaches at least one navigable sea zone.
- Closed water never appears in a normal route.
- Access/basing differences produce distinct, correct results.
- Ownership/control/access changes invalidate relevant caches.
- Unknown IDs and malformed overrides reject safely.
- England-France, Portugal-Channel, Gibraltar-Mediterranean, and representative long Atlantic paths resolve.
- Full graph path stress stays inside the approved N1 budget.

## Exit Gate

N1 is complete when the authored Channel/Iberian ports and all navigable sea zones validate, fleet-shaped route queries are deterministic and explainable, supply/basing queries are stable, preview and validation agree, and no known topology defect can strand a future fleet.
