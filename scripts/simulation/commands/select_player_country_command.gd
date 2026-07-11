class_name SelectPlayerCountryCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var country_tag := ""


func _init(p_country_tag: String, p_issuer := "player", p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Play as %s" % country_tag


func command_type() -> String:
	return "SelectPlayerCountryCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country tag: %s" % country_tag
	if world.get_country_provinces(country_tag).is_empty():
		return "%s does not control any provinces in this scenario." % country_tag
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var old_country := world.player_country
	world.player_country = country_tag
	if old_country != country_tag:
		events.publish_player_change(old_country, country_tag)
