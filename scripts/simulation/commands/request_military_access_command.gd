class_name RequestMilitaryAccessCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var country_tag := ""
var host_tag := ""


func _init(p_country: String, p_host: String, p_scheduled_day := -1) -> void:
	country_tag = p_country
	host_tag = p_host
	issuer = p_country
	scheduled_day = p_scheduled_day
	description = "Request military access from %s" % host_tag


func command_type() -> String:
	return "RequestMilitaryAccessCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_country(host_tag) or country_tag == host_tag:
		return "Select a different existing host country."
	if DiplomacySystemScript.are_at_war(world, country_tag, host_tag):
		return "Military access cannot be requested from an enemy."
	if DiplomacySystemScript.has_access(world, country_tag, host_tag):
		return "Military access is already granted."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record := DiplomacySystemScript.relation(world, country_tag, host_tag)
	var requests: Dictionary = record["access_requests"]
	requests[country_tag] = true
	record["access_requests"] = requests
	DiplomacySystemScript.set_relation(world, country_tag, host_tag, record)
	events.military_access_requested.emit(country_tag, host_tag)
