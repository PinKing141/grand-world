class_name TakeLoanCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""


func _init(p_country_tag: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Take a standard loan"


func command_type() -> String:
	return "TakeLoanCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country."
	if int(world.country_runtime(country_tag).get("debt", 0)) + EconomySystemScript.LOAN_PRINCIPAL > EconomySystemScript.MAXIMUM_DEBT:
		return "Maximum debt reached."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var loan_id := EconomySystemScript.take_loan(world, country_tag)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.loan_taken.emit(loan_id, country_tag, EconomySystemScript.LOAN_PRINCIPAL)
