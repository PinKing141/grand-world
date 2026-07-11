class_name AcceptPeaceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const PeaceSystemScript = preload("res://scripts/simulation/peace_system.gd")

var war_id := ""
var offer_id := ""
var accepting_country := ""


func _init(p_war_id: String, p_offer_id: String, p_accepting_country: String, p_scheduled_day := -1) -> void:
	war_id = p_war_id
	offer_id = p_offer_id
	accepting_country = p_accepting_country
	issuer = p_accepting_country
	scheduled_day = p_scheduled_day
	description = "%s accepts peace offer %s" % [accepting_country, offer_id]


func command_type() -> String:
	return "AcceptPeaceCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.war_registry.has(war_id):
		return "The war no longer exists."
	var war: Dictionary = world.war_registry[war_id]
	var offers: Dictionary = war.get("peace_offers", {})
	if not offers.has(offer_id):
		return "The peace offer no longer exists."
	var offer: Dictionary = offers[offer_id]
	if String(offer.get("receiver", "")) != accepting_country:
		return "Only the addressed country can accept this offer."
	if world.current_day > int(offer.get("expires_day", -1)):
		return "The peace offer has expired."
	return PeaceSystemScript.validate_terms(world, war_id, String(offer["offerer"]), accepting_country, offer.get("terms", []))


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var failure := PeaceSystemScript.apply_offer(world, events, war_id, offer_id)
	if not failure.is_empty():
		push_error("Validated peace application failed: %s" % failure)
