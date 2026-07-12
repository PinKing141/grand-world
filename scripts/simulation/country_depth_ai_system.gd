class_name CountryDepthAISystem
extends RefCounted

## Deterministic monthly AI for Phase 8 country-depth systems. It only submits
## the same validated commands available to the player and stores a bounded
## explanation history in authoritative country runtime state.

const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")
const IncreaseStabilityCommandScript = preload("res://scripts/simulation/commands/increase_stability_command.gd")
const AdvanceTechnologyCommandScript = preload("res://scripts/simulation/commands/advance_technology_command.gd")
const SelectIdeaGroupCommandScript = preload("res://scripts/simulation/commands/select_idea_group_command.gd")
const EnactGovernmentReformCommandScript = preload("res://scripts/simulation/commands/enact_government_reform_command.gd")
const StartProvinceConversionCommandScript = preload("res://scripts/simulation/commands/start_province_conversion_command.gd")
const FabricateProvinceClaimCommandScript = preload("res://scripts/simulation/commands/fabricate_province_claim_command.gd")
const SuppressRebelsCommandScript = preload("res://scripts/simulation/commands/suppress_rebels_command.gd")
const StartSubjectIntegrationCommandScript = preload("res://scripts/simulation/commands/start_subject_integration_command.gd")
const ChooseCountryEventOptionCommandScript = preload("res://scripts/simulation/commands/choose_country_event_option_command.gd")
const EnactCountryDecisionCommandScript = preload("res://scripts/simulation/commands/enact_country_decision_command.gd")

const HISTORY_LIMIT := 16

var scheduler: SimulationScheduler
var events: SimulationEventBus
var definitions: CountryDepthDefinitions
var graph: ProvinceGraph


func _init(p_scheduler: SimulationScheduler, p_events: SimulationEventBus, p_definitions: CountryDepthDefinitions) -> void:
	scheduler = p_scheduler
	events = p_events
	definitions = p_definitions
	graph = ProvinceGraphScript.load_default()


func process_month(world: CampaignWorldState) -> void:
	if not bool(world.global_flags.get("ai_enabled", true)):
		return
	for tag in definitions.country_tags():
		if tag == world.player_country or world.get_country_provinces(tag).is_empty() or not CountryDepthSystemScript.overlord_of(world, tag).is_empty():
			continue
		_review_country(world, tag)


func debug_snapshot(world: CampaignWorldState, country_tag: String) -> Dictionary:
	if not world.has_country(country_tag):
		return {}
	return (world.country_runtime(country_tag).get("country_depth_ai", {}) as Dictionary).duplicate(true)


func _review_country(world: CampaignWorldState, country_tag: String) -> void:
	var runtime := world.country_runtime(country_tag)
	var state: Dictionary = runtime.get("country_depth_ai", {"history": [], "last_action": "", "last_reason": ""})
	state["last_review_day"] = world.current_day
	var pending := CountryDepthSystemScript.pending_event_for_country(world, country_tag)
	if not pending.is_empty() and _resolve_event(world, country_tag, pending, state):
		_save(world, country_tag, state)
		return
	if int(runtime.get("stability", 0)) < 0 and _submit(world, IncreaseStabilityCommandScript.new(country_tag), state, "increase_stability", "Recovered negative national stability before pursuing expansion."):
		_save(world, country_tag, state)
		return
	for track in CountryDepthDefinitions.TECHNOLOGY_TRACKS:
		if _submit(world, AdvanceTechnologyCommandScript.new(country_tag, track), state, "advance_%s" % track, "Invested accumulated points in the next affordable technology level."):
			_save(world, country_tag, state)
			return
	if String(runtime.get("idea_group_id", "")).is_empty():
		var preferred := String(runtime.get("preferred_idea_group_id", "administrative"))
		if _submit(world, SelectIdeaGroupCommandScript.new(country_tag, preferred), state, "select_idea", "Selected the country's configured strategic direction."):
			_save(world, country_tag, state)
			return
	if _enact_reform(world, country_tag, runtime, state):
		_save(world, country_tag, state)
		return
	if _suppress_dangerous_rebels(world, country_tag, state):
		_save(world, country_tag, state)
		return
	if _start_conversion(world, country_tag, runtime, state):
		_save(world, country_tag, state)
		return
	if _integrate_subject(world, country_tag, state):
		_save(world, country_tag, state)
		return
	if _enact_decision(world, country_tag, state):
		_save(world, country_tag, state)
		return
	if _fabricate_border_claim(world, country_tag, state):
		_save(world, country_tag, state)
		return
	_record(state, world.current_day, "hold", "No valid country-depth action passed its authoritative command validation.")
	_save(world, country_tag, state)


func _resolve_event(world: CampaignWorldState, country_tag: String, pending: Dictionary, state: Dictionary) -> bool:
	var definition := definitions.event(String(pending.get("definition_id", "")))
	var options: Array = definition.get("options", [])
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("ai_weight", 0)) > int(b.get("ai_weight", 0)) if int(a.get("ai_weight", 0)) != int(b.get("ai_weight", 0)) else String(a.get("id", "")) < String(b.get("id", "")))
	for option in options:
		var command := ChooseCountryEventOptionCommandScript.new(country_tag, String(pending.get("instance_id", "")), String((option as Dictionary).get("id", "")))
		if _submit(world, command, state, "resolve_event", "Selected the highest weighted valid option for %s." % String(pending.get("definition_id", ""))):
			return true
	return false


func _enact_reform(world: CampaignWorldState, country_tag: String, runtime: Dictionary, state: Dictionary) -> bool:
	var government := definitions.government(String(runtime.get("government_id", "")))
	var reforms: Array = government.get("reforms", [])
	reforms.sort()
	for raw_reform in reforms:
		if _submit(world, EnactGovernmentReformCommandScript.new(country_tag, String(raw_reform)), state, "enact_reform", "Enacted the first affordable reform allowed by the current government."):
			return true
	return false


func _suppress_dangerous_rebels(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	var candidates: Array[Dictionary] = []
	for raw_id in world.rebel_faction_registry:
		var faction: Dictionary = world.rebel_faction_registry[raw_id]
		if String(faction.get("country_tag", "")) == country_tag and int(faction.get("progress_bp", 0)) >= 7500:
			candidates.append(faction)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("progress_bp", 0)) > int(b.get("progress_bp", 0)) if int(a.get("progress_bp", 0)) != int(b.get("progress_bp", 0)) else String(a.get("faction_id", "")) < String(b.get("faction_id", "")))
	for faction in candidates:
		if _submit(world, SuppressRebelsCommandScript.new(country_tag, String(faction.get("faction_id", ""))), state, "suppress_rebels", "Spent reserves to interrupt a rebel faction nearing uprising."):
			return true
	return false


func _start_conversion(world: CampaignWorldState, country_tag: String, runtime: Dictionary, state: Dictionary) -> bool:
	var target_religion := String(runtime.get("state_religion", "unknown"))
	var provinces := world.get_country_provinces(country_tag)
	provinces.sort()
	for province_id in provinces:
		var economy: Dictionary = world.province_states[province_id].get("economy", {})
		if String(economy.get("religion", "unknown")) == target_religion:
			continue
		if _submit(world, StartProvinceConversionCommandScript.new(country_tag, province_id, "religion", target_religion), state, "convert_religion", "Started conversion in the first stable-order province outside the state religion."):
			return true
	return false


func _integrate_subject(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	var ids := world.subject_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.subject_registry[raw_id]
		if String(record.get("overlord", "")) != country_tag:
			continue
		if _submit(world, StartSubjectIntegrationCommandScript.new(country_tag, String(raw_id)), state, "integrate_subject", "Began integrating a loyal subject after unlocking diplomatic administration."):
			return true
	return false


func _enact_decision(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	var ids := definitions.decisions().keys()
	ids.sort()
	for raw_id in ids:
		if _submit(world, EnactCountryDecisionCommandScript.new(country_tag, String(raw_id)), state, "enact_decision", "Enacted the first valid deterministic national decision."):
			return true
	return false


func _fabricate_border_claim(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	var provinces := world.get_country_provinces(country_tag)
	provinces.sort()
	var candidates: Array[int] = []
	for province_id in provinces:
		for neighbor_id in graph.land_neighbors(province_id):
			var owner := world.get_province_owner(neighbor_id)
			if not owner.is_empty() and owner != country_tag and not candidates.has(neighbor_id):
				candidates.append(neighbor_id)
	candidates.sort()
	for province_id in candidates:
		if _submit(world, FabricateProvinceClaimCommandScript.new(country_tag, province_id), state, "fabricate_claim", "Fabricated a claim on the first eligible bordering province."):
			return true
	return false


func _submit(world: CampaignWorldState, command: SimulationCommand, state: Dictionary, action: String, reason: String) -> bool:
	if not command.validate(world).is_empty():
		return false
	scheduler.submit(command)
	_record(state, world.current_day, action, reason)
	return true


func _record(state: Dictionary, day: int, action: String, reason: String) -> void:
	state["last_action"] = action
	state["last_reason"] = reason
	var history: Array = state.get("history", [])
	history.append({"day": day, "action": action, "reason": reason})
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	state["history"] = history


func _save(world: CampaignWorldState, country_tag: String, state: Dictionary) -> void:
	var runtime := world.country_runtime(country_tag)
	runtime["country_depth_ai"] = state
	world.set_country_runtime(country_tag, runtime)
	events.country_depth_ai_decision.emit(country_tag, String(state.get("last_action", "")), String(state.get("last_reason", "")))
