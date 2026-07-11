class_name SimulationCommand
extends RefCounted

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")

var command_id := 0
var issuer := "system"
var scheduled_day := -1
var description := ""


func command_type() -> String:
	return "SimulationCommand"


func validate(_world: CampaignWorldState) -> String:
	return "Base simulation commands cannot be applied."


func apply(_world: CampaignWorldState, _events: SimulationEventBus) -> void:
	pass


func history_record(applied_day: int, accepted: bool, failure_reason := "") -> Dictionary:
	return {
		"command_id": command_id,
		"type": command_type(),
		"issuer": issuer,
		"scheduled_day": scheduled_day,
		"applied_day": applied_day,
		"accepted": accepted,
		"failure_reason": failure_reason,
		"description": description,
	}
