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
