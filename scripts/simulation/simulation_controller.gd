class_name GrandWorldSimulationController
extends Node

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const CampaignScenarioDefinition = preload("res://scripts/simulation/campaign_scenario_definition.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationScheduler = preload("res://scripts/simulation/simulation_scheduler.gd")
const SimulationCommand = preload("res://scripts/simulation/commands/simulation_command.gd")
const SelectPlayerCountryCommand = preload("res://scripts/simulation/commands/select_player_country_command.gd")
const ChangeProvinceOwnerCommand = preload("res://scripts/simulation/commands/change_province_owner_command.gd")
const SetGameSpeedCommand = preload("res://scripts/simulation/commands/set_game_speed_command.gd")
const PauseCommand = preload("res://scripts/simulation/commands/pause_command.gd")
const CampaignSaveService = preload("res://scripts/simulation/campaign_save_service.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")
const MoveArmyCommandScript = preload("res://scripts/simulation/commands/move_army_command.gd")
const CancelArmyMovementCommandScript = preload("res://scripts/simulation/commands/cancel_army_movement_command.gd")
const ArmyMovementSystemScript = preload("res://scripts/simulation/army_movement_system.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ConstructBuildingCommandScript = preload("res://scripts/simulation/commands/construct_building_command.gd")
const CancelConstructionCommandScript = preload("res://scripts/simulation/commands/cancel_construction_command.gd")
const RecruitUnitCommandScript = preload("res://scripts/simulation/commands/recruit_unit_command.gd")
const DisbandArmyCommandScript = preload("res://scripts/simulation/commands/disband_army_command.gd")
const SetArmyMaintenanceCommandScript = preload("res://scripts/simulation/commands/set_army_maintenance_command.gd")
const TakeLoanCommandScript = preload("res://scripts/simulation/commands/take_loan_command.gd")
const RepayLoanCommandScript = preload("res://scripts/simulation/commands/repay_loan_command.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const ImproveRelationsCommandScript = preload("res://scripts/simulation/commands/improve_relations_command.gd")
const FormAllianceCommandScript = preload("res://scripts/simulation/commands/form_alliance_command.gd")
const BreakAllianceCommandScript = preload("res://scripts/simulation/commands/break_alliance_command.gd")
const RequestMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/request_military_access_command.gd")
const GrantMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/grant_military_access_command.gd")
const DeclareWarCommandScript = preload("res://scripts/simulation/commands/declare_war_command.gd")
const OfferPeaceCommandScript = preload("res://scripts/simulation/commands/offer_peace_command.gd")
const AcceptPeaceCommandScript = preload("res://scripts/simulation/commands/accept_peace_command.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const StrategicAISystemScript = preload("res://scripts/simulation/strategic_ai_system.gd")
const CampaignGoalSystemScript = preload("res://scripts/simulation/campaign_goal_system.gd")
const CharacterDefinitionsScript = preload("res://scripts/simulation/character_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const CharacterAISystemScript = preload("res://scripts/simulation/character_ai_system.gd")
const ArrangeMarriageCommandScript = preload("res://scripts/simulation/commands/arrange_marriage_command.gd")
const AssignCommanderCommandScript = preload("res://scripts/simulation/commands/assign_commander_command.gd")
const GrantTitleCommandScript = preload("res://scripts/simulation/commands/grant_title_command.gd")
const DeclareClaimWarCommandScript = preload("res://scripts/simulation/commands/declare_claim_war_command.gd")

signal simulation_ready(world: CampaignWorldState)
signal save_completed(success: bool, message: String)
signal load_completed(success: bool, message: String)

const GAME_VERSION := "0.7.0-phase7"
const QUICK_SAVE_PATH := "user://saves/quick_save.json"
const SPEED_DAYS_PER_SECOND: Array[float] = [0.0, 1.0, 3.0, 10.0, 30.0, 90.0]

@export_group("Scenario")
@export var scenario_id := CampaignWorldState.DEFAULT_SCENARIO_ID
@export var campaign_seed := 14441111
@export var country_data: CountryData

@export_group("Presentation Mirrors")
@export var map_render: Node
@export var province_selector: ProvinceSelector
@export var map_hud: MapHUD

@export_group("Clock")
@export_range(1, 32, 1) var maximum_ticks_per_frame := 8
@export_range(1000, 16000, 250) var simulation_frame_budget_usec := 5000

var world := CampaignWorldState.new()
var scenario_definition: CampaignScenarioDefinition
var event_bus: SimulationEventBus
var scheduler: SimulationScheduler
var ai_definitions: AIDefinitions
var ai_system: StrategicAISystem
var character_definitions: CharacterDefinitions
var character_ai_system: CharacterAISystem
var initialized := false
var last_tick_cost_usec := 0
var last_frame_tick_count := 0
var _day_accumulator := 0.0


func _ready() -> void:
	event_bus = SimulationEventBus.new()
	event_bus.name = "SimulationEventBus"
	add_child(event_bus)
	event_bus.province_owner_changed.connect(_on_province_owner_changed)
	event_bus.province_controller_changed.connect(_on_province_controller_changed)
	event_bus.world_reloaded.connect(_on_world_reloaded)
	event_bus.player_country_changed.connect(_on_character_player_changed)
	_bootstrap_scenario()


func _exit_tree() -> void:
	# Break the scheduler <-> AI callable/reference cycle explicitly so campaign
	# reloads and repeated headless runs release every Phase 6 object.
	if scheduler != null:
		scheduler.ai_hooks.clear()
		scheduler.monthly_systems.clear()
	ai_system = null
	character_ai_system = null


func _process(delta: float) -> void:
	if not initialized:
		return
	scheduler.process_commands()
	if world.paused:
		_day_accumulator = 0.0
		last_frame_tick_count = 0
		return
	var days_per_second := SPEED_DAYS_PER_SECOND[world.game_speed]
	_day_accumulator = minf(
		_day_accumulator + delta * days_per_second,
		float(maximum_ticks_per_frame * 2)
	)
	var ticks_due := mini(floori(_day_accumulator), maximum_ticks_per_frame)
	if ticks_due <= 0:
		return
	var started_usec := Time.get_ticks_usec()
	var processed_ticks := 0
	for tick in range(ticks_due):
		scheduler.advance_one_day()
		processed_ticks += 1
		if processed_ticks < ticks_due and Time.get_ticks_usec() - started_usec >= simulation_frame_budget_usec:
			break
	_day_accumulator -= processed_ticks
	last_tick_cost_usec = Time.get_ticks_usec() - started_usec
	last_frame_tick_count = processed_ticks


func submit_command(command: SimulationCommand) -> int:
	if not initialized:
		return -1
	return scheduler.submit(command)


func choose_player_country(country_tag: String) -> int:
	return submit_command(SelectPlayerCountryCommand.new(country_tag))


func change_province_owner_for_testing(province_id: int, new_owner: String) -> int:
	return submit_command(ChangeProvinceOwnerCommand.new(province_id, new_owner))


func set_game_speed(speed: int) -> int:
	return submit_command(SetGameSpeedCommand.new(speed))


func order_army_move(army_id: String, destination_province_id: int, issuing_country: String) -> int:
	return submit_command(MoveArmyCommandScript.new(army_id, destination_province_id, issuing_country))


func cancel_army_movement(army_id: String, issuing_country: String) -> int:
	return submit_command(CancelArmyMovementCommandScript.new(army_id, issuing_country))


func construct_building(country_tag: String, province_id: int, building_id: String) -> int:
	return submit_command(ConstructBuildingCommandScript.new(country_tag, province_id, building_id))


func cancel_construction(country_tag: String, construction_id: String) -> int:
	return submit_command(CancelConstructionCommandScript.new(country_tag, construction_id))


func recruit_unit(country_tag: String, province_id: int, unit_id := "infantry_regiment") -> int:
	return submit_command(RecruitUnitCommandScript.new(country_tag, province_id, unit_id))


func disband_army(country_tag: String, army_id: String) -> int:
	return submit_command(DisbandArmyCommandScript.new(country_tag, army_id))


func set_army_maintenance(country_tag: String, maintenance_bp: int) -> int:
	return submit_command(SetArmyMaintenanceCommandScript.new(country_tag, maintenance_bp))


func take_loan(country_tag: String) -> int:
	return submit_command(TakeLoanCommandScript.new(country_tag))


func repay_loan(country_tag: String, loan_id: String) -> int:
	return submit_command(RepayLoanCommandScript.new(country_tag, loan_id))


func improve_relations(country_tag: String, target_tag: String) -> int:
	return submit_command(ImproveRelationsCommandScript.new(country_tag, target_tag))


func form_alliance(country_tag: String, target_tag: String) -> int:
	return submit_command(FormAllianceCommandScript.new(country_tag, target_tag))


func break_alliance(country_tag: String, target_tag: String) -> int:
	return submit_command(BreakAllianceCommandScript.new(country_tag, target_tag))


func request_military_access(country_tag: String, host_tag: String) -> int:
	return submit_command(RequestMilitaryAccessCommandScript.new(country_tag, host_tag))


func grant_military_access(host_tag: String, country_tag: String) -> int:
	return submit_command(GrantMilitaryAccessCommandScript.new(host_tag, country_tag))


func declare_war(attacker_tag: String, defender_tag: String, target_province_id: int) -> int:
	return submit_command(DeclareWarCommandScript.new(attacker_tag, defender_tag, target_province_id))


func offer_peace(war_id: String, offerer: String, receiver: String, terms: Array) -> int:
	return submit_command(OfferPeaceCommandScript.new(war_id, offerer, receiver, terms))


func accept_peace(war_id: String, offer_id: String, accepting_country: String) -> int:
	return submit_command(AcceptPeaceCommandScript.new(war_id, offer_id, accepting_country))


func arrange_marriage(first_character_id: String, second_character_id: String, issuing_country := "") -> int:
	return submit_command(ArrangeMarriageCommandScript.new(first_character_id, second_character_id, issuing_country))


func assign_commander(country_tag: String, army_id: String, character_id: String) -> int:
	return submit_command(AssignCommanderCommandScript.new(country_tag, army_id, character_id))


func grant_title(country_tag: String, title_id: String, character_id: String) -> int:
	return submit_command(GrantTitleCommandScript.new(country_tag, title_id, character_id))


func declare_claim_war(attacker_tag: String, defender_tag: String, claim_id: String) -> int:
	return submit_command(DeclareClaimWarCommandScript.new(attacker_tag, defender_tag, claim_id))


func relationship(country_tag: String, target_tag: String) -> Dictionary:
	return DiplomacySystemScript.relation(world, country_tag, target_tag) if initialized else {}


func country_wars(country_tag: String) -> Array[String]:
	return DiplomacySystemScript.country_wars(world, country_tag) if initialized else []


func ai_debug_snapshot(country_tag: String) -> Dictionary:
	return ai_system.debug_snapshot(world, country_tag) if initialized and ai_system != null else {}


func ai_objective_map_values(country_tag: String) -> Dictionary:
	return ai_system.objective_map_values(world, country_tag) if initialized and ai_system != null else {}


func campaign_summary() -> Dictionary:
	return CampaignGoalSystemScript.summary(world, ai_definitions) if initialized and ai_definitions != null else {}


func country_ruler(country_tag: String) -> Dictionary:
	return CharacterSystemScript.character_summary(world, CharacterSystemScript.ruler_id(world, country_tag)) if initialized else {}


func country_heir(country_tag: String) -> Dictionary:
	return CharacterSystemScript.character_summary(world, CharacterSystemScript.heir_id(world, country_tag)) if initialized else {}


func character_summary(character_id: String) -> Dictionary:
	return CharacterSystemScript.character_summary(world, character_id) if initialized else {}


func dynasty_summary(dynasty_id: String) -> Dictionary:
	return CharacterSystemScript.dynasty_summary(world, dynasty_id) if initialized else {}


func character_opinion(source_id: String, target_id: String) -> Dictionary:
	return CharacterSystemScript.opinion_breakdown(world, source_id, target_id) if initialized else {}


func character_ai_snapshot(country_tag: String) -> Dictionary:
	return character_ai_system.debug_snapshot(world, country_tag) if initialized and character_ai_system != null else {}


func set_ai_enabled(enabled: bool) -> void:
	if initialized:
		world.global_flags["ai_enabled"] = enabled


func country_economy(country_tag: String) -> Dictionary:
	return world.country_runtime(country_tag) if initialized and world.has_country(country_tag) else {}


func province_economy(province_id: int) -> Dictionary:
	if not initialized or not world.has_province(province_id):
		return {}
	return (world.province_states[province_id].get("economy", {}) as Dictionary).duplicate(true)


func economy_map_values(mode: String) -> Dictionary:
	var values := {}
	if not initialized:
		return values
	var definitions = EconomyDefinitionsScript.load_default()
	var construction_provinces := {}
	for raw_id in world.construction_registry:
		construction_provinces[int(world.construction_registry[raw_id].get("province_id", -1))] = 1
	var ids := world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var economy: Dictionary = world.province_states[raw_id].get("economy", {})
		if not bool(economy.get("economic_eligible", false)):
			continue
		var outputs: Dictionary = EconomySystemScript.province_outputs(economy, definitions)
		match mode:
			"tax": values[province_id] = int(outputs["tax"])
			"production": values[province_id] = int(outputs["production"])
			"manpower": values[province_id] = int(outputs["maximum_manpower"])
			"development": values[province_id] = int(economy.get("development", 0))
			"construction": values[province_id] = 2 if construction_provinces.has(province_id) else (1 if not (economy.get("buildings", []) as Array).is_empty() else 0)
	return values


func preview_army_route(army_id: String, destination_province_id: int) -> Dictionary:
	# Presentation-only: identical pathfinder call to what the command will
	# execute, so the previewed route and arrival date match the real order.
	if not initialized:
		return {"exists": false, "failure_reason": "Simulation is not ready."}
	var army := world.get_army(army_id)
	if army.is_empty():
		return {"exists": false, "failure_reason": "The army no longer exists."}
	var graph := ProvinceGraph.load_default()
	var owner_tag := String(army.get("owner_country_id", ""))
	var current := int(army.get("current_province_id", -1))
	var route := ProvincePathfinderScript.find_route(graph, world, owner_tag, current, destination_province_id)
	if bool(route["exists"]):
		var arrival := world.current_day
		var path: PackedInt32Array = route["path"]
		for index in range(path.size() - 1):
			arrival += ProvincePathfinderScript.leg_cost_days(graph, path[index], path[index + 1])
		route["arrival_day"] = arrival
		route["arrival_text"] = SimulationDate.format_day(arrival)
	return route


func day_fraction() -> float:
	# How far the current day has progressed in real time; presentation uses
	# this to interpolate army markers without touching authoritative state.
	return clampf(_day_accumulator, 0.0, 1.0) if initialized and not world.paused else 0.0


func set_paused(should_pause: bool) -> int:
	return submit_command(PauseCommand.new(should_pause))


func toggle_pause() -> int:
	return set_paused(not world.paused)


func debug_step_one_day() -> void:
	if not initialized:
		return
	set_paused(true)
	scheduler.process_commands()
	scheduler.advance_one_day()


func debug_jump_to_next_month() -> void:
	if not initialized:
		return
	set_paused(true)
	scheduler.process_commands()
	var starting_date := SimulationDate.day_to_date(world.current_day)
	while true:
		scheduler.advance_one_day()
		var date := SimulationDate.day_to_date(world.current_day)
		if date["month"] != starting_date["month"] or date["year"] != starting_date["year"]:
			break


func quick_save() -> Dictionary:
	if not initialized:
		var unavailable := {"ok": false, "message": "Simulation is not ready."}
		save_completed.emit(false, unavailable["message"])
		return unavailable
	var result := CampaignSaveService.save_world(world, QUICK_SAVE_PATH, GAME_VERSION)
	save_completed.emit(result["ok"], result["message"])
	return result


func quick_load() -> Dictionary:
	if not initialized:
		var unavailable := {"ok": false, "message": "Simulation is not ready."}
		load_completed.emit(false, unavailable["message"])
		return unavailable
	var result := CampaignSaveService.load_world(world, QUICK_SAVE_PATH)
	if result["ok"]:
		scheduler.clear_pending_commands()
		_day_accumulator = 0.0
		world.global_flags["enforce_military_access"] = true
		WarfareSystemScript.initialize_armies(world)
		if ai_system != null:
			ai_system.ensure_world(world)
		if ai_definitions != null:
			CampaignGoalSystemScript.ensure_world(world, ai_definitions)
		if character_definitions != null:
			CharacterSystemScript.ensure_world(world, character_definitions)
		_sync_all_owners_to_presentation()
		if String(result.get("message", "")).contains("migrated"):
			EconomySystemScript.recalculate_all(world)
		event_bus.world_reloaded.emit(world.checksum())
		event_bus.publish_date(world.current_day)
		event_bus.pause_changed.emit(world.paused)
		event_bus.speed_changed.emit(world.game_speed)
		if not world.player_country.is_empty():
			event_bus.publish_player_change("", world.player_country)
	load_completed.emit(result["ok"], result["message"])
	return result


func world_checksum() -> String:
	return world.checksum() if initialized else ""


func command_history() -> Array[Dictionary]:
	return scheduler.command_history.duplicate(true) if scheduler != null else []


func dump_province_state(province_id: int) -> Dictionary:
	if not initialized or not world.has_province(province_id):
		return {}
	return (world.province_states[province_id] as Dictionary).duplicate(true)


func dump_country_state(country_tag: String) -> Dictionary:
	if not initialized or not world.has_country(country_tag):
		return {}
	return {
		"runtime": (world.country_states[country_tag] as Dictionary).duplicate(true),
		"provinces": world.get_country_provinces(country_tag),
	}


func _bootstrap_scenario() -> void:
	if country_data == null:
		push_error("SimulationController requires CountryData.")
		return
	scenario_definition = CampaignScenarioDefinition.new()
	scenario_definition.initialize_from_country_data(country_data, scenario_id)
	world.initialize(
		scenario_definition.province_initial_owners(),
		scenario_definition.country_names(),
		scenario_definition.scenario_id(),
		campaign_seed
	)
	world.global_flags["enforce_military_access"] = true
	var economy_definitions = EconomyDefinitionsScript.load_default()
	if not economy_definitions.is_valid():
		push_error("SimulationController requires valid Phase 4 economy definitions.")
		return
	EconomySystemScript.initialize_world(world, economy_definitions)
	WarfareSystemScript.initialize_armies(world)
	character_definitions = CharacterDefinitionsScript.load_default()
	if not character_definitions.is_valid():
		push_error("SimulationController requires valid Phase 7 character definitions: %s" % character_definitions.error())
		return
	CharacterSystemScript.initialize_world(world, character_definitions)
	ai_definitions = AIDefinitionsScript.load_default()
	if not ai_definitions.is_valid():
		push_error("SimulationController requires valid Phase 6 AI definitions: %s" % ai_definitions.error())
		return
	scheduler = SimulationScheduler.new(world, event_bus)
	scheduler.daily_systems.append(
		func(day_world: CampaignWorldState) -> void:
			ArmyMovementSystemScript.advance_day(day_world, event_bus)
	)
	scheduler.daily_systems.append(
		func(day_world: CampaignWorldState) -> void:
			WarfareSystemScript.advance_day(day_world, event_bus)
	)
	scheduler.start_of_day_systems.append(
		func(day_world: CampaignWorldState) -> void:
			EconomySystemScript.process_day(day_world, event_bus, economy_definitions)
	)
	character_ai_system = CharacterAISystemScript.new(scheduler, event_bus)
	scheduler.monthly_systems.append(
		func(month_world: CampaignWorldState) -> void:
			CharacterSystemScript.process_month(month_world, event_bus)
			character_ai_system.process_month(month_world)
	)
	scheduler.monthly_systems.append(
		func(month_world: CampaignWorldState) -> void:
			EconomySystemScript.process_month(month_world, event_bus, economy_definitions)
	)
	ai_system = StrategicAISystemScript.new(scheduler, event_bus, ai_definitions)
	ai_system.initialize_world(world)
	CampaignGoalSystemScript.initialize_world(world, ai_definitions)
	scheduler.ai_hooks.append(
		func(ai_world: CampaignWorldState) -> void:
			CampaignGoalSystemScript.process_day(ai_world, event_bus, ai_definitions)
			ai_system.process_day(ai_world)
	)
	initialized = true
	_sync_all_owners_to_presentation()
	simulation_ready.emit(world)
	event_bus.publish_date(world.current_day)
	event_bus.pause_changed.emit(world.paused)
	event_bus.speed_changed.emit(world.game_speed)


func _on_province_owner_changed(province_id: int, old_owner: String, new_owner: String) -> void:
	_sync_owner_to_presentation(province_id, new_owner)
	if not old_owner.is_empty():
		EconomySystemScript.recalculate_country(world, old_owner)
	if not new_owner.is_empty():
		EconomySystemScript.recalculate_country(world, new_owner)
	if map_hud != null and map_hud.has_method("refresh_authoritative_ownership"):
		map_hud.refresh_authoritative_ownership(province_id)


func _on_world_reloaded(_checksum: String) -> void:
	if map_hud != null and map_hud.has_method("refresh_authoritative_ownership"):
		map_hud.refresh_authoritative_ownership(-1)


func _on_character_player_changed(_old_country: String, new_country: String) -> void:
	if initialized:
		CharacterSystemScript.mark_player_dynasty(world, new_country)


func _on_province_controller_changed(province_id: int, _old_controller: String, _new_controller: String) -> void:
	var owner := world.get_province_owner(province_id)
	if not owner.is_empty():
		EconomySystemScript.recalculate_country(world, owner)
	if map_hud != null and map_hud.has_method("refresh_authoritative_ownership"):
		map_hud.refresh_authoritative_ownership(province_id)


func _sync_owner_to_presentation(province_id: int, owner_tag: String) -> void:
	var presentation_owner := owner_tag if not owner_tag.is_empty() else "No Owner"
	country_data.province_id_to_owner[province_id] = presentation_owner
	if map_render == null or not map_render.has_method("update_color_map"):
		return
	var owner_color: Color = country_data.country_id_to_color.get(owner_tag, Color(0.0, 0.0, 0.0, 0.0))
	map_render.update_color_map(province_id, owner_color)


func _sync_all_owners_to_presentation() -> void:
	var presentation_owners := {}
	var province_ids := world.province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var owner_tag := world.get_province_owner(province_id)
		presentation_owners[province_id] = owner_tag
		country_data.province_id_to_owner[province_id] = owner_tag if not owner_tag.is_empty() else "No Owner"
	if map_render != null and map_render.has_method("apply_world_state_owners"):
		map_render.apply_world_state_owners(presentation_owners)
