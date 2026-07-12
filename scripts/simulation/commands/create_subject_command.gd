class_name CreateSubjectCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var overlord_tag := ""
var subject_tag := ""
var subject_type := "vassal"


func _init(p_overlord_tag: String, p_subject_tag: String, p_subject_type := "vassal", p_scheduled_day := -1) -> void:
	overlord_tag = p_overlord_tag
	subject_tag = p_subject_tag
	subject_type = p_subject_type
	issuer = p_overlord_tag
	scheduled_day = p_scheduled_day
	description = "%s establishes %s as a %s" % [overlord_tag, subject_tag, subject_type]


func command_type() -> String:
	return "CreateSubjectCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(overlord_tag) or not world.has_country(subject_tag) or overlord_tag == subject_tag:
		return "Subject creation requires two different existing countries."
	if subject_type not in CountryDepthSystemScript.VALID_SUBJECT_TYPES:
		return "The subject type is invalid."
	if world.get_country_provinces(overlord_tag).is_empty() or world.get_country_provinces(subject_tag).is_empty():
		return "Both countries must be active."
	if not CountryDepthSystemScript.overlord_of(world, subject_tag).is_empty():
		return "The target country already has an overlord."
	if _would_create_cycle(world):
		return "This subject relationship would create a cycle."
	if not DiplomacySystemScript.active_war_between(world, overlord_tag, subject_tag).is_empty():
		return "Countries at war cannot establish voluntary subject status."
	if int((world.country_runtime(overlord_tag).get("technology", {}) as Dictionary).get("diplomatic", 0)) < 1:
		return "Diplomatic technology 1 is required."
	if subject_type == "vassal" and (not DiplomacySystemScript.are_allied(world, overlord_tag, subject_tag) or DiplomacySystemScript.opinion(world, subject_tag, overlord_tag) < 100):
		return "Voluntary vassalage requires an alliance and the target's opinion of the overlord to be at least +100."
	if subject_type == "personal_union":
		return "Personal unions are established through dynastic claims and succession."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.create_subject(world, events, overlord_tag, subject_tag, subject_type)


func _would_create_cycle(world: CampaignWorldState) -> bool:
	var cursor := overlord_tag
	var visited := {}
	while not cursor.is_empty() and not visited.has(cursor):
		if cursor == subject_tag:
			return true
		visited[cursor] = true
		cursor = CountryDepthSystemScript.overlord_of(world, cursor)
	return false
