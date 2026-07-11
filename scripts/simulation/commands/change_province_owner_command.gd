class_name ChangeProvinceOwnerCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var province_id := -1
var new_owner := ""


func _init(p_province_id: int, p_new_owner: String, p_issuer := "debug", p_scheduled_day := -1) -> void:
	province_id = p_province_id
	new_owner = p_new_owner
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Transfer province %d to %s" % [province_id, new_owner]


func command_type() -> String:
	return "ChangeProvinceOwnerCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_province(province_id):
		return "Unknown province ID: %d" % province_id
	if not world.has_country(new_owner):
		return "Unknown destination country: %s" % new_owner
	if world.get_province_owner(province_id) == new_owner:
		return "Province %d is already owned by %s." % [province_id, new_owner]
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var old_owner := world.set_province_owner(province_id, new_owner)
	events.publish_owner_change(province_id, old_owner, new_owner)
