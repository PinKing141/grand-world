class_name SimulationEventBus
extends Node

const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")

signal date_changed(day_count: int, date: Dictionary)
signal month_started(day_count: int, year: int, month: int)
signal year_started(day_count: int, year: int)
signal province_owner_changed(province_id: int, old_owner: String, new_owner: String)
signal player_country_changed(old_country: String, new_country: String)
signal command_rejected(command_id: int, command_type: String, reason: String)
signal pause_changed(paused: bool)
signal speed_changed(speed: int)
signal world_reloaded(checksum: String)
signal army_movement_ordered(army_id: String, path: PackedInt32Array, arrival_day: int)
signal army_moved(army_id: String, from_province: int, to_province: int)
signal army_movement_completed(army_id: String, province_id: int)
signal army_movement_blocked(army_id: String, province_id: int, reason: String)
signal army_movement_cancelled(army_id: String)
signal economy_month_processed(day_count: int)
signal building_started(construction_id: String, province_id: int, building_id: String)
signal building_cancelled(construction_id: String, province_id: int, refund: int)
signal building_completed(construction_id: String, province_id: int, building_id: String)
signal recruitment_started(recruitment_id: String, province_id: int, unit_id: String)
signal recruitment_completed(recruitment_id: String, army_id: String, province_id: int)
signal army_disbanded(army_id: String)
signal maintenance_changed(country_tag: String, maintenance_bp: int)
signal loan_taken(loan_id: String, country_tag: String, principal: int)
signal loan_repaid(loan_id: String, country_tag: String, principal: int)
signal relations_changed(country_tag: String, target_tag: String, opinion: int)
signal alliance_changed(country_tag: String, target_tag: String, allied: bool)
signal military_access_requested(country_tag: String, host_tag: String)
signal military_access_changed(country_tag: String, host_tag: String, granted: bool)
signal war_declared(war_id: String, attacker: String, defender: String, target_province_id: int)
signal battle_started(war_id: String, battle_id: String, province_id: int)
signal battle_reinforced(battle_id: String, army_id: String, side: String)
signal battle_round_resolved(battle_id: String, round: int, attacker_losses: int, defender_losses: int)
signal battle_ended(war_id: String, battle_id: String, winner_side: String)
signal army_retreat_started(army_id: String, destination_province_id: int)
signal army_recovered(army_id: String)
signal army_destroyed(army_id: String, battle_id: String)
signal province_controller_changed(province_id: int, old_controller: String, new_controller: String)
signal occupation_changed(war_id: String, province_id: int, controller: String)
signal war_score_changed(war_id: String, score: int)
signal peace_offered(war_id: String, offer_id: String, offerer: String, receiver: String)
signal peace_signed(war_id: String, attacker: String, defender: String, truce_until_day: int)
signal ai_decision_made(country_tag: String, category: String, action: String, score: int, reason: String)
signal ai_goal_changed(country_tag: String, goal: String, posture: String)
signal campaign_status_changed(status: String, summary: Dictionary)
signal character_born(character_id: String, mother_id: String, father_id: String)
signal character_came_of_age(character_id: String)
signal character_became_ill(character_id: String, illness: String, until_day: int)
signal character_arrived_at_court(character_id: String, country_tag: String)
signal character_married(first_id: String, second_id: String)
signal character_died(character_id: String, cause: String, day: int)
signal succession_resolved(country_tag: String, old_ruler_id: String, new_ruler_id: String, heir_id: String)
signal title_holder_changed(title_id: String, old_holder_id: String, new_holder_id: String)
signal commander_assigned(army_id: String, character_id: String)
signal claim_pressed(claim_id: String, title_id: String, new_holder_id: String)
signal character_ai_decision(country_tag: String, action: String, reason: String)


func publish_date(day_count: int) -> void:
	date_changed.emit(day_count, SimulationDate.day_to_date(day_count))


func publish_month(day_count: int, year: int, month: int) -> void:
	month_started.emit(day_count, year, month)


func publish_year(day_count: int, year: int) -> void:
	year_started.emit(day_count, year)


func publish_owner_change(province_id: int, old_owner: String, new_owner: String) -> void:
	province_owner_changed.emit(province_id, old_owner, new_owner)


func publish_player_change(old_country: String, new_country: String) -> void:
	player_country_changed.emit(old_country, new_country)


func publish_rejection(command_id: int, command_type: String, reason: String) -> void:
	command_rejected.emit(command_id, command_type, reason)
