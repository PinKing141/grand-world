class_name AssignCommanderCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")

var country_tag := ""
var army_id := ""
var character_id := ""


func _init(p_country_tag: String, p_army_id: String, p_character_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	army_id = p_army_id
	character_id = p_character_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Assign %s to command %s" % [character_id, army_id]


func command_type() -> String:
	return "AssignCommanderCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.army_registry.has(army_id):
		return "The country or army does not exist."
	if String((world.army_registry[army_id] as Dictionary).get("owner_country_id", "")) != country_tag:
		return "%s does not control this army." % country_tag
	if not world.character_registry.has(character_id):
		return "The commander does not exist."
	var character: Dictionary = world.character_registry[character_id]
	if not bool(character.get("alive", false)) or String(character.get("employer_country", "")) != country_tag:
		return "The commander must be a living member of this country's court."
	if CharacterSystemScript.age_years(world, character_id) < CharacterSystemScript.ADULT_AGE:
		return "A commander must be an adult."
	var existing := String(character.get("commander_army_id", ""))
	if not existing.is_empty() and existing != army_id:
		return "The character already commands another army."
	var existing_fleet := String(character.get("admiral_fleet_id", ""))
	if not existing_fleet.is_empty():
		return "The character already commands a fleet."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CharacterSystemScript.assign_commander(world, events, army_id, character_id)
