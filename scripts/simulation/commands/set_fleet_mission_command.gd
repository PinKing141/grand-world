class_name SetFleetMissionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

## Shared player/AI mission contract from 06_N6_AI_AND_UX.md. `idle` remains
## accepted as the pre-N6 save-compatible alias for `none`.
const VALID_MISSIONS := [
	"none", "idle", "patrol", "intercept", "protect_transport", "transport",
	"blockade", "protect_coast", "return_to_port", "repair", "trade_protection",
]

var country_tag := ""
var fleet_id := ""
var mission := ""
var target_ids: Array = []


func _init(p_country_tag: String, p_fleet_id: String, p_mission: String, p_scheduled_day := -1, p_target_ids: Array = []) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	mission = p_mission
	target_ids = p_target_ids.duplicate()
	target_ids.sort()
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
	fleet["mission_target_ids"] = target_ids.duplicate()
	fleet["mission_started_day"] = world.current_day
	world.fleet_registry[fleet_id] = fleet
	events.fleet_mission_changed.emit(fleet_id, mission)
