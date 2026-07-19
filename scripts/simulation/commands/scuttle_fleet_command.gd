class_name ScuttleFleetCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

## FL2.5: a deliberate, permanent, player-issued fleet loss - see
## docs/roadmap/naval/g1_finish_line/evidence/FL2_5_SCUTTLE_COMMAND.md for the
## full safety-rule design this command implements. Deliberately as
## unforgiving as an in-battle sinking: no treasury/manpower/sailor refund,
## matching how naval_combat_system.gd and fleet_logistics_system.gd already
## treat a ship lost in combat - scuttling is not meant to be a cheaper or
## more rewarding way to lose a ship than losing it in battle.

const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var country_tag := ""
var fleet_id := ""


func _init(p_country_tag: String, p_fleet_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s scuttles %s" % [country_tag, fleet_id]


func command_type() -> String:
	return "ScuttleFleetCommand"


## Reuses FleetSystem.is_docked_and_organisable() - the exact same gate
## SplitFleetCommand/MergeFleetsCommand/TransferShipsCommand already validate
## through - for ownership, "must be docked" (which excludes moving,
## retreating, and in-battle by construction, since those are mutually
## exclusive location statuses), and "no active transport reservation"
## (which covers both "carrying armies" and "holding a reservation", since a
## fleet only carries an army via an active transport operation). The one
## check that function does not cover is "intercepting", a mission tag
## rather than a location status - added explicitly here.
func validate(world: CampaignWorldState) -> String:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "Unknown fleet: %s" % fleet_id
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return "%s does not own %s." % [country_tag, fleet_id]
	if not FleetSystemScript.is_docked_and_organisable(world, fleet_id, country_tag):
		return "The fleet must be docked, unlocked, and free of any active transport reservation to be scuttled."
	if String(fleet.get("mission", "idle")) == "intercept":
		return "An intercepting fleet cannot be scuttled."
	return ""


## Admiral cleanup: character.admiral_fleet_id is explicitly cleared before
## the fleet record disappears, mirroring the reverse cleanup
## CharacterSystem's own death-handling code already performs when an
## *admiral* dies (character_system.gd's admiral_fleet_id clearing on the
## fleet side). No other fleet-destruction path in this codebase currently
## does this for the erased fleet's own admiral - a real, pre-existing
## dangling-reference gap in combat-driven destruction, out of scope to fix
## here (see the evidence doc), but not one this command repeats.
## Mission cleanup needs no separate step: mission/mission_target_ids/
## mission_started_day are fields on the fleet record itself, which is being
## erased entirely - there is no external per-fleet mission registry to
## reconcile (BlockadeSystem reads fleet state live, not a separate table).
func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var fleet := world.get_fleet(fleet_id)
	var ship_ids := world.fleet_ships(fleet_id)
	var admiral_id := String(fleet.get("admiral_id", ""))
	if not admiral_id.is_empty() and world.character_registry.has(admiral_id):
		var admiral: Dictionary = world.character_registry[admiral_id]
		admiral["admiral_fleet_id"] = ""
		world.character_registry[admiral_id] = admiral
	for ship_id in ship_ids:
		world.ship_registry.erase(ship_id)
	world.fleet_registry.erase(fleet_id)
	events.fleet_scuttled.emit(fleet_id, country_tag, ship_ids.size())
