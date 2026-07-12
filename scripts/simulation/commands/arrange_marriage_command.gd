class_name ArrangeMarriageCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")

var first_id := ""
var second_id := ""


func _init(p_first_id: String, p_second_id: String, p_issuer := "", p_scheduled_day := -1) -> void:
	first_id = p_first_id
	second_id = p_second_id
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Arrange marriage between %s and %s" % [first_id, second_id]


func command_type() -> String:
	return "ArrangeMarriageCommand"


func validate(world: CampaignWorldState) -> String:
	if not issuer.is_empty() and issuer != "system":
		if not world.has_country(issuer):
			return "The issuing country does not exist."
		var first_country := String((world.character_registry.get(first_id, {}) as Dictionary).get("employer_country", ""))
		var second_country := String((world.character_registry.get(second_id, {}) as Dictionary).get("employer_country", ""))
		if issuer != first_country and issuer != second_country:
			return "The issuing country must represent one marriage participant."
	return CharacterSystemScript.can_marry(world, first_id, second_id)


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CharacterSystemScript.arrange_marriage(world, events, first_id, second_id)
