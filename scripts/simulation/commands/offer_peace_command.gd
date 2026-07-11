class_name OfferPeaceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const PeaceSystemScript = preload("res://scripts/simulation/peace_system.gd")

var war_id := ""
var offerer := ""
var receiver := ""
var terms: Array = []


func _init(p_war_id: String, p_offerer: String, p_receiver: String, p_terms: Array, p_scheduled_day := -1) -> void:
	war_id = p_war_id
	offerer = p_offerer
	receiver = p_receiver
	terms = p_terms.duplicate(true)
	issuer = p_offerer
	scheduled_day = p_scheduled_day
	description = "%s offers peace to %s in %s" % [offerer, receiver, war_id]


func command_type() -> String:
	return "OfferPeaceCommand"


func validate(world: CampaignWorldState) -> String:
	return PeaceSystemScript.validate_terms(world, war_id, offerer, receiver, terms)


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var war: Dictionary = world.war_registry[war_id]
	var offer_id := "peace_%06d" % world.take_counter("next_peace_offer_id")
	var cost := 0
	for term in terms:
		cost += PeaceSystemScript.term_cost(war, term)
	var offers: Dictionary = war.get("peace_offers", {})
	offers[offer_id] = {
		"offer_id": offer_id,
		"offerer": offerer,
		"receiver": receiver,
		"terms": terms.duplicate(true),
		"war_score_cost": cost,
		"ai_value_for_receiver": -cost,
		"created_day": world.current_day,
		"expires_day": world.current_day + 30,
	}
	war["peace_offers"] = offers
	world.war_registry[war_id] = war
	events.peace_offered.emit(war_id, offer_id, offerer, receiver)
