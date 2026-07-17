# 07 - Data, Command, Event, and Save Contracts

**Status:** Approved as part of N0 (see [10 - Delivery sequence and checklist](10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N0.2, approved 2026-07-17). N1-N5 implementation has followed this contract's intent throughout, with specific, evidence-doc-recorded deviations noted inline below where a slice's actual decision diverged from what was originally proposed here (file ownership names, the blockade reverse-index question, save schema numbering). This document is not rewritten to match every actual decision after the fact - the individual N1-N5 evidence docs remain the authoritative record of what was actually built and why; this page records the original intent those decisions are judged against.  
**Purpose:** prevent N1-N6 from inventing incompatible IDs, records, mutations, or save behaviour

## Planned File Ownership

The exact filenames may change at architecture review, but responsibilities must remain separate:

| Resource | Responsibility |
|---|---|
| `assets/naval_definitions.json` | Ship families/variants, naval constants, mission parameters, port capability rules |
| `assets/naval_ports.json` | Port enablement, level, exits/overrides, water class, provenance/review |
| `assets/naval_starting_forces.json` or history-profile section | Initial fleets, ships, home ports, admirals, provenance |
| `scripts/simulation/maritime_graph.gd` | Runtime sea/port topology, access, range, path results |
| `scripts/simulation/naval_definitions.gd` | Versioned loader and validator |
| `scripts/simulation/fleet_movement_system.gd` | Arrival-day movement and route revalidation |
| `scripts/simulation/naval_logistics_system.gd` | Supply, attrition, repair, reinforcement, monthly costs |
| `scripts/simulation/naval_transport_system.gd` | Capacity reservations and transport state machine |
| `scripts/simulation/naval_warfare_system.gd` | Engagement, rounds, damage, retreat, capture, sinking |
| `scripts/simulation/naval_strategy_system.gd` | Blockade/trade outputs and wider-system queries |
| `scripts/simulation/naval_ai_system.gd` or bounded strategic-AI extension | Missions, threat, construction, transport planning |
| `scripts/ui/naval_hud.gd` and naval scenes | Player fleet/port/transport/battle surfaces |
| `scripts/ui/naval_layer.gd` | Map markers, clustering, selection, routes |

One large script must not own graph, economy, movement, transport, battle, AI, and UI together.

## Stable ID Policy

Suggested namespaces:

- Fleet: `f_<country>_<counter>`.
- Ship: `s_<country>_<counter>`; capture never changes the stable ID.
- Ship construction: `sc_<country>_<counter>`.
- Transport operation: `tr_<country>_<counter>`.
- Naval battle: `nb_<war-or-global>_<counter>`.
- Ship definition: semantic data ID such as `early_carrack`.
- Port: integer land province ID.
- Sea zone: integer water province ID.

Counters live in authoritative global/country counters and are included in checksum/save. IDs never use object instance IDs, array positions, display names, or current owner after creation.

## Proposed Fleet Record

Required fields:

- `fleet_id`, `owner_country_id`, `name`.
- `ship_ids` sorted or canonicalised for save/checksum.
- `commander_id`.
- `status`: docked, idle_at_sea, moving, battle, retreating, repairing, blocked.
- `location_kind`: port or sea_zone.
- `location_id`, `home_port_id`, `destination_kind`, `destination_id`.
- `remaining_path`, `path_index`, `movement_start_day`, `next_arrival_day`, `movement_progress_bp`.
- `movement_locked`, `blocked_reason`.
- `mission_id`, `mission_targets`, `mission_started_day`.
- `battle_id`, `transport_operation_ids`.
- `morale_bp`, `maximum_morale_bp` or a reproducible aggregate policy.
- `supply_status`, `supply_port_id`, `supply_range_cost`, `days_at_sea`.
- Cached aggregate revision/totals only if validation can rebuild and compare them.

## Proposed Ship Record

- `ship_id`, `owner_country_id`, `fleet_id`.
- `definition_id`, `display_name` or localisation/name seed.
- `built_day`, `built_port_id`.
- `hull`, `maximum_hull` if not entirely definition-derived.
- `crew`/`sailors`, `maximum_crew`.
- `morale_bp` only if morale is per ship; otherwise fleet morale remains authority.
- `disabled`, `captured_from_country_id`, `captured_battle_id`.
- `repair_priority` if player priorities are approved.

Derived attack, defence, speed, blockade, capacity, maintenance, and class values come from the definition plus current condition/modifiers. Saves do not duplicate static definition values unless migration policy requires a snapshot.

## Proposed Ship Construction Record

- `construction_id`, `country_id`, `port_province_id`, `ship_definition_id`.
- `start_day`, `completion_day`.
- `amount_paid`, `sailors_reserved`.
- `target_fleet_id` or explicit port reserve policy.
- `status`, `blocked_reason`, `paused_day`.
- Content/command sequence information only when required for deterministic order.

## Proposed Transport Operation Record

- `operation_id`, `country_id`, `army_id`, `fleet_id`.
- `origin_province_id`, `destination_province_id`.
- `reserved_capacity`, optional assigned `transport_ship_ids`.
- `state`, `state_started_day`, `state_completion_day`.
- `planned_sea_path`, `battle_id`, `recovery_target_id`.
- `strength_lost`, `regiments_lost`, `failure_reason`.

Terminal operations may be removed after an event/history record is produced, but active reverse references and reservations must clear in the same mutation.

## Proposed Naval Battle Record

- `battle_id`, `war_id`, `sea_zone_id`, `start_day`, `round`.
- `attacker_fleet_ids`, `defender_fleet_ids`.
- Side country IDs and leaders.
- `attacker_positioning_bp`, `defender_positioning_bp` and breakdown/revision.
- `minimum_retreat_day`.
- Initial/current class, ship, hull, crew, and morale totals.
- Per-side sunk/captured/withdrawn ship IDs.
- Reinforcement records.
- Retreat requests/destinations.
- `status`, `winner_side`, `ended_day`, `war_score_value`.
- Bounded battle-report data required after completion.

## Reverse Indexes

Authoritative or deterministically rebuilt indexes:

- Country -> fleets.
- Port/sea zone -> fleets.
- Fleet -> ships.
- Army -> transport operation.
- Fleet -> transport operations.
- Ship -> construction/capture/battle membership where applicable.
- Sea zone -> naval battle.
- Port/province -> active blockade contributors.

Load validation rebuilds indexes from primary records or confirms saved indexes exactly. Indexes cannot silently disagree with primary registries.

## Command Contract

Every command:

- Carries issuing country and issuer identity.
- Uses stable IDs only.
- Returns an immutable rejection reason from `validate`.
- Recomputes/reconfirms critical route/cost/capacity facts in `apply` to handle earlier queued commands.
- Applies atomically and emits events after state is valid.
- Has stable `command_type`, description, scheduled day, and queue ordering.

### Graph/access/diplomacy commands

- Request/grant/revoke naval access.
- Request/grant/revoke fleet basing rights.

### Logistics commands

- Construct/cancel ship.
- Create/merge/split fleet; transfer ships.
- Set home port, mission, and naval maintenance.
- Move/cancel fleet movement.
- Assign/remove admiral.
- Repair/scuttle if not covered by mission/automatic rules.

### Transport commands

- Create/cancel transport operation.
- Confirm/change disembark destination only if approved.

### Combat commands

- Request naval retreat.
- Optional join/reinforce order if ordinary movement is not sufficient.

Commands remain narrow. A convenience UI action may compose commands but cannot bypass their validations.

## Event Bus Contract

Event names should follow existing signal conventions. Minimum categories:

- Fleet created/removed/organised.
- Ship construction started/cancelled/completed.
- Naval maintenance changed.
- Fleet movement ordered/moved/completed/blocked/cancelled.
- Fleet supply/attrition/repair status changed.
- Admiral assigned.
- Transport planned/embark started/embarked/intercepted/disembark started/completed/cancelled/failed.
- Naval battle started/reinforced/round resolved/retreat started/ended.
- Ship damaged/disabled/captured/sunk only when event volume remains bounded; otherwise aggregate round/battle events carry lists.
- Blockade started/threshold changed/ended.
- War blockade score and coastal siege support changed.
- Naval AI decision made.

Presentation listens to events and queries current state. Events are not a second state store.

## Save Schema Policy

The current campaign schema was 5 when this document was proposed. In practice naval work has taken the next available schema number at each slice that needed one, exactly as this policy intends: 6 (N2.1 fleet/ship/naval-construction registries), 7 (N3.1 transport operations), 8 (N4.1 naval battles), 9 (N5.1 blockade-transition tracking) - see each slice's own evidence doc for its migration step. "It is expected to be schema 6" was this document's original, single-slice guess and is superseded by that actual sequence.

New save fields:

- Fleet, ship, ship-construction, transport-operation, and naval-battle registries.
- Naval access/basing relationship fields.
- Country sailor/naval economy values within runtime state.
- Naval global counters and RNG stream states.
- Naval mission/AI schedule state when authoritative.
- Any port dynamic state that cannot be derived.

Checksum adds every authoritative naval registry, counter, relationship, and RNG stream in canonical order.

## Migration Policy

Schema-5 campaigns migrate to:

- Empty valid naval registries.
- No retroactive free historical fleets.
- Initial/default sailor and naval-maintenance values derived through one migration function.
- No active transports, battles, blockades, or construction.
- New counters initialised without colliding with future IDs.

New campaigns receive scenario starting fleets from external content. Migration must be idempotent and preserve the old campaign checksum semantics only for pre-migration verification; the migrated checksum becomes the new authority.

## Load Validation

Reject or deterministically repair only documented cases. Validate:

- Known countries, provinces, sea zones, ports, definitions, armies, characters, and wars.
- One owner/fleet per ship.
- Fleet/ship reverse membership.
- Legal locations and paths.
- Valid status enum and required fields per status.
- Construction cost/date/port/definition references.
- Transport army/fleet/capacity/location references.
- Battle fleet/war/zone membership.
- Commander life/role/country rules.
- Reservation totals and nonnegative values.
- Bounds for hull, crew, morale, progress, blockade, maintenance, and supply.
- Counters greater than/equal to every allocated ID in their namespace.

Errors include the registry and stable ID so corrupted saves are actionable.

## Scheduler Contract

Naval systems are registered explicitly in `SimulationController`; they do not create independent `_process` simulation clocks. Command application remains scheduler authority. The order approved in N0 must be encoded in integration tests by constructing cases where a different order would produce a different outcome.

## Contract Exit Gate

This document exits proposal when record fields, identity, reverse indexes, commands, events, migration, validation, and scheduler ordering are approved and referenced by each N1-N6 implementation checklist. Any later incompatible change requires a recorded schema/API decision.
