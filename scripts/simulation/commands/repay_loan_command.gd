class_name RepayLoanCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var loan_id := ""


func _init(p_country_tag: String, p_loan_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	loan_id = p_loan_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Repay loan %s" % loan_id


func command_type() -> String:
	return "RepayLoanCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.loan_registry.has(loan_id):
		return "Unknown loan."
	var loan: Dictionary = world.loan_registry[loan_id]
	if String(loan.get("country_tag", "")) != country_tag:
		return "This country does not own the loan."
	if int(world.country_runtime(country_tag).get("treasury", 0)) < int(loan.get("principal", 0)):
		return "Insufficient treasury to repay this loan."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var loan: Dictionary = world.loan_registry[loan_id]
	var principal := int(loan["principal"])
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - principal
	runtime["debt"] = maxi(0, int(runtime.get("debt", 0)) - principal)
	world.set_country_runtime(country_tag, runtime)
	world.loan_registry.erase(loan_id)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.loan_repaid.emit(loan_id, country_tag, principal)
