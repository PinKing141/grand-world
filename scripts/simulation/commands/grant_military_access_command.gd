class_name GrantMilitaryAccessCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var host_tag := ""
var country_tag := ""


func _init(p_host: String, p_country: String, p_scheduled_day := -1) -> void:
	host_tag = p_host
	country_tag = p_country
	issuer = p_host
	scheduled_day = p_scheduled_day
	description = "Grant military access to %s" % country_tag


func command_type() -> String:
	return "GrantMilitaryAccessCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_country(host_tag) or country_tag == host_tag:
		return "Select two different existing countries."
	if DiplomacySystemScript.are_at_war(world, country_tag, host_tag):
		return "Military access cannot be granted to an enemy."
	if DiplomacySystemScript.has_access(world, country_tag, host_tag):
		return "Military access is already granted."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record := DiplomacySystemScript.relation(world, country_tag, host_tag)
	var access: Dictionary = record["military_access"]
	access[country_tag] = true
	record["military_access"] = access
	var requests: Dictionary = record["access_requests"]
	requests.erase(country_tag)
	record["access_requests"] = requests
	DiplomacySystemScript.set_relation(world, country_tag, host_tag, record)
	events.military_access_changed.emit(country_tag, host_tag, true)
