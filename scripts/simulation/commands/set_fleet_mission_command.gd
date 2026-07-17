class_name SetFleetMissionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

## "Its mission permits blockade" (docs/roadmap/naval/05_N5_STRATEGIC_EFFECTS.md
## "Blockade Assignment") is the first thing this roadmap actually gates on
## fleet.mission - the field has existed since N2.1 (default "idle") but
## nothing previously read or wrote it. Only "idle" and "blockade" are valid
## for this first slice; transport/patrol/protect/etc. missions 05_N5 and
## later pillars describe are not modeled yet.
const VALID_MISSIONS := ["idle", "blockade"]

var country_tag := ""
var fleet_id := ""
var mission := ""


func _init(p_country_tag: String, p_fleet_id: String, p_mission: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	mission = p_mission
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s sets %s's mission to %s" % [country_tag, fleet_id, mission]


func command_type() -> String:
	return "SetFleetMissionCommand"


func validate(world: CampaignWorldState) -> String:
	if not VALID_MISSIONS.has(mission):
		return "Unknown fleet mission: %s" % mission
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "Unknown fleet: %s" % fleet_id
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return "%s does not own %s." % [country_tag, fleet_id]
	if String(fleet.get("location_status", "")) in [CampaignWorldState.FLEET_LOCATION_BATTLE, CampaignWorldState.FLEET_LOCATION_RETREATING]:
		return "The fleet cannot change mission in its current state."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var fleet := world.get_fleet(fleet_id)
	fleet["mission"] = mission
	world.fleet_registry[fleet_id] = fleet
	events.fleet_mission_changed.emit(fleet_id, mission)
