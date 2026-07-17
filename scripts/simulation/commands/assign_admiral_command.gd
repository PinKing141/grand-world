class_name AssignAdmiralCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")

var country_tag := ""
var fleet_id := ""
var character_id := ""


func _init(p_country_tag: String, p_fleet_id: String, p_character_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	character_id = p_character_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Assign %s to command %s" % [character_id, fleet_id]


func command_type() -> String:
	return "AssignAdmiralCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.fleet_registry.has(fleet_id):
		return "The country or fleet does not exist."
	if String((world.fleet_registry[fleet_id] as Dictionary).get("owner_country_id", "")) != country_tag:
		return "%s does not control this fleet." % country_tag
	if not world.character_registry.has(character_id):
		return "The admiral does not exist."
	var character: Dictionary = world.character_registry[character_id]
	if not bool(character.get("alive", false)) or String(character.get("employer_country", "")) != country_tag:
		return "The admiral must be a living member of this country's court."
	if CharacterSystemScript.age_years(world, character_id) < CharacterSystemScript.ADULT_AGE:
		return "An admiral must be an adult."
	var existing_fleet := String(character.get("admiral_fleet_id", ""))
	if not existing_fleet.is_empty() and existing_fleet != fleet_id:
		return "The character already commands another fleet."
	var existing_army := String(character.get("commander_army_id", ""))
	if not existing_army.is_empty():
		return "The character already commands an army."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CharacterSystemScript.assign_admiral(world, events, fleet_id, character_id)
