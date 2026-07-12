class_name StartSubjectIntegrationCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var overlord_tag := ""
var subject_id := ""


func _init(p_overlord_tag: String, p_subject_id: String, p_scheduled_day := -1) -> void:
	overlord_tag = p_overlord_tag
	subject_id = p_subject_id
	issuer = p_overlord_tag
	scheduled_day = p_scheduled_day
	description = "%s begins integrating %s" % [overlord_tag, subject_id]


func command_type() -> String:
	return "StartSubjectIntegrationCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.subject_registry.has(subject_id):
		return "The subject relationship does not exist."
	var record: Dictionary = world.subject_registry[subject_id]
	if String(record.get("status", "active")) != "active" or String(record.get("overlord", "")) != overlord_tag:
		return "Only the active overlord can integrate this subject."
	if bool(record.get("integration_active", false)):
		return "Subject integration is already active."
	if int(record.get("liberty_desire_bp", 0)) >= 5000:
		return "Liberty desire must be below 50%."
	if int((world.country_runtime(overlord_tag).get("technology", {}) as Dictionary).get("diplomatic", 0)) < 3:
		return "Diplomatic technology 3 is required."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.start_subject_integration(world, events, subject_id)
