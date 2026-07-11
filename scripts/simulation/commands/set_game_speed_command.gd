class_name SetGameSpeedCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var speed := 1


func _init(p_speed: int, p_issuer := "player", p_scheduled_day := -1) -> void:
	speed = p_speed
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Set game speed to %d" % speed


func command_type() -> String:
	return "SetGameSpeedCommand"


func validate(_world: CampaignWorldState) -> String:
	return "" if speed >= 1 and speed <= 5 else "Game speed must be between 1 and 5."


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var speed_changed := world.game_speed != speed
	var pause_changed := world.paused
	world.game_speed = speed
	world.paused = false
	if speed_changed:
		events.speed_changed.emit(speed)
	if pause_changed:
		events.pause_changed.emit(false)
