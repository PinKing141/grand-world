class_name GrantTitleCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")

var country_tag := ""
var title_id := ""
var new_holder_id := ""


func _init(p_country_tag: String, p_title_id: String, p_new_holder_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	title_id = p_title_id
	new_holder_id = p_new_holder_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s grants %s to %s" % [country_tag, title_id, new_holder_id]


func command_type() -> String:
	return "GrantTitleCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.title_registry.has(title_id) or not world.character_registry.has(new_holder_id):
		return "The title or intended holder does not exist."
	var runtime := world.country_runtime(country_tag)
	if String(runtime.get("ruler_character_id", "")) != String((world.title_registry[title_id] as Dictionary).get("holder_id", "")):
		return "Only the ruling holder can grant this title."
	if String(runtime.get("primary_title_id", "")) == title_id:
		return "The country's primary title cannot be granted away."
	var character: Dictionary = world.character_registry[new_holder_id]
	if not bool(character.get("alive", false)) or String(character.get("employer_country", "")) != country_tag:
		return "The recipient must be a living member of this country's court."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CharacterSystemScript.grant_title(world, events, title_id, new_holder_id)
