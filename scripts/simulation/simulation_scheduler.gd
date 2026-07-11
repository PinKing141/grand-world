class_name SimulationScheduler
extends RefCounted

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationCommand = preload("res://scripts/simulation/commands/simulation_command.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")

var world: CampaignWorldState
var events: SimulationEventBus
var command_queue: Array[SimulationCommand] = []
var command_history: Array[Dictionary] = []
var daily_systems: Array[Callable] = []
var start_of_day_systems: Array[Callable] = []
var monthly_systems: Array[Callable] = []
var yearly_systems: Array[Callable] = []
var ai_hooks: Array[Callable] = []
var _next_command_id := 1


func _init(p_world: CampaignWorldState, p_events: SimulationEventBus) -> void:
	world = p_world
	events = p_events


func submit(command: SimulationCommand) -> int:
	command.command_id = _next_command_id
	_next_command_id += 1
	if command.scheduled_day < 0:
		command.scheduled_day = world.current_day
	command_queue.append(command)
	command_queue.sort_custom(_command_precedes)
	return command.command_id


func process_commands() -> int:
	var processed := 0
	while not command_queue.is_empty() and command_queue[0].scheduled_day <= world.current_day:
		var command: SimulationCommand = command_queue.pop_front() as SimulationCommand
		var failure_reason: String = command.validate(world)
		if failure_reason.is_empty():
			command.apply(world, events)
			command_history.append(command.history_record(world.current_day, true))
		else:
			command_history.append(command.history_record(world.current_day, false, failure_reason))
			events.publish_rejection(command.command_id, command.command_type(), failure_reason)
		processed += 1
	return processed


func advance_one_day() -> void:
	# Stable Phase 2 order: commands, daily rules, periodic rules, events, AI,
	# then presentation subscribers react to the published state changes.
	process_commands()
	for system in daily_systems:
		system.call(world)

	var previous_date := SimulationDate.day_to_date(world.current_day)
	world.current_day += 1
	var current_date := SimulationDate.day_to_date(world.current_day)
	for system in start_of_day_systems:
		system.call(world)

	if current_date["month"] != previous_date["month"] or current_date["year"] != previous_date["year"]:
		for system in monthly_systems:
			system.call(world)
		events.publish_month(world.current_day, current_date["year"], current_date["month"])
	if current_date["year"] != previous_date["year"]:
		for system in yearly_systems:
			system.call(world)
		events.publish_year(world.current_day, current_date["year"])

	for hook in ai_hooks:
		hook.call(world)
	events.publish_date(world.current_day)


func advance_days(day_count: int) -> void:
	for day in range(maxi(day_count, 0)):
		advance_one_day()


func clear_pending_commands() -> void:
	command_queue.clear()


func _command_precedes(a: SimulationCommand, b: SimulationCommand) -> bool:
	if a.scheduled_day != b.scheduled_day:
		return a.scheduled_day < b.scheduled_day
	return a.command_id < b.command_id
