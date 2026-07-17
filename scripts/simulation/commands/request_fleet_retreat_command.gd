class_name RequestFleetRetreatCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")

var country_tag := ""
var fleet_id := ""


func _init(p_country_tag: String, p_fleet_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s requests retreat for %s" % [country_tag, fleet_id]


func command_type() -> String:
	return "RequestFleetRetreatCommand"


## "Player/AI may request retreat; command validates leader/side/fleet
## ownership" (04_N4_NAVAL_COMBAT.md "Retreat and Pursuit"). A side already
## destroyed/collapsed does not need this command - NavalCombatSystem
## already retreats a defeated side's survivors automatically; this is only
## for a still-fighting fleet choosing to withdraw early.
func validate(world: CampaignWorldState) -> String:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "The fleet does not exist."
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return "%s does not control this fleet." % country_tag
	var battle_id := String(fleet.get("battle_id", ""))
	if battle_id.is_empty():
		return "The fleet is not in a battle."
	var battle := world.get_naval_battle(battle_id)
	if String(battle.get("status", "")) != "active":
		return "The battle is no longer active."
	if int(battle.get("round", 0)) < NavalCombatSystemScript.MIN_RETREAT_ROUNDS:
		return "The fleet cannot retreat until the battle has lasted at least %d rounds." % NavalCombatSystemScript.MIN_RETREAT_ROUNDS
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	NavalCombatSystemScript.withdraw_fleet(world, events, fleet_id)
