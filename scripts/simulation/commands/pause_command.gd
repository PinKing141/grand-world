class_name PauseCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var should_pause := true


func _init(p_should_pause: bool, p_issuer := "player", p_scheduled_day := -1) -> void:
	should_pause = p_should_pause
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Pause campaign" if should_pause else "Resume campaign"


func command_type() -> String:
	return "PauseCommand"


func validate(_world: CampaignWorldState) -> String:
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	if world.paused == should_pause:
		return
	world.paused = should_pause
	events.pause_changed.emit(should_pause)
