class_name CountryDepthSystem
extends RefCounted

const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")

const BASIS_POINTS := 10000
const CLAIM_DURATION_DAYS := 3650
const CONVERSION_PROGRESS_PER_MONTH := 500
const INTEGRATION_MONTHS := 120
const VALID_SUBJECT_TYPES := ["vassal", "personal_union"]


static func initialize_world(world: CampaignWorldState, definitions: CountryDepthDefinitions) -> void:
	world.subject_registry.clear()
	world.country_event_registry.clear()
	world.rebel_faction_registry.clear()
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var source := definitions.country(tag)
		var runtime := world.country_runtime(tag)
		var provinces := world.get_country_provinces(tag)
		provinces.sort()
		if source.is_empty():
			runtime.merge({
				"government_id": "feudal_monarchy", "government_reforms": [],
				"primary_culture": "unknown", "accepted_cultures": [], "state_religion": "unknown",
				"capital_province_id": provinces[0] if not provinces.is_empty() else -1,
				"stability": 0, "authority_bp": int(runtime.get("legitimacy_bp", 8000)), "centralisation_bp": 1000,
				"war_exhaustion_bp": 0, "religious_unity_bp": BASIS_POINTS, "average_unrest_bp": 0,
				"technology": {"administrative": 0, "diplomatic": 0, "military": 0},
				"technology_points": {"administrative": 0, "diplomatic": 0, "military": 0},
				"country_depth_modifiers": {}, "country_status": "active" if not provinces.is_empty() else "dormant",
			}, false)
			world.set_country_runtime(tag, runtime)
			continue
		runtime.merge({
			"government_id": String(source.get("government", "feudal_monarchy")),
			"government_reforms": [], "primary_culture": String(source.get("primary_culture", "unknown")),
			"accepted_cultures": (source.get("accepted_cultures", []) as Array).duplicate(),
			"state_religion": String(source.get("state_religion", "unknown")),
			"capital_province_id": int(source.get("capital_province_id", provinces[0] if not provinces.is_empty() else -1)),
			"stability": 0, "authority_bp": int(runtime.get("legitimacy_bp", 8000)), "centralisation_bp": 1000,
			"war_exhaustion_bp": 0, "religious_unity_bp": BASIS_POINTS, "average_unrest_bp": 0,
			"tolerance_own": 2, "tolerance_heretic": 0, "tolerance_heathen": -1,
			"technology": (source.get("technology", {"administrative": 0, "diplomatic": 0, "military": 0}) as Dictionary).duplicate(true),
			"technology_points": {"administrative": 0, "diplomatic": 0, "military": 0},
			"idea_group_id": "", "preferred_idea_group_id": String(source.get("preferred_idea", "administrative")),
			"country_depth_modifiers": {}, "temporary_modifiers": [],
			"event_cooldowns": {}, "event_history": [], "enacted_decisions": [],
			"factions": {"nobility": {"influence_bp": 4000, "loyalty_bp": 5000}, "clergy": {"influence_bp": 3000, "loyalty_bp": 5000}, "burghers": {"influence_bp": 3000, "loyalty_bp": 5000}},
			"country_status": "active" if not provinces.is_empty() else "dormant", "formed_from": "", "formed_into": "",
		}, false)
		world.set_country_runtime(tag, runtime)
	var province_ids := world.province_states.keys()
	province_ids.sort()
	for raw_id in province_ids:
		var province_id := int(raw_id)
		var state: Dictionary = world.province_states[raw_id]
		var economy: Dictionary = state.get("economy", {})
		var source := definitions.province(province_id)
		var owner := world.get_province_owner(province_id)
		var owner_runtime := world.country_runtime(owner) if world.has_country(owner) else {}
		economy.merge({
			"culture": String(source.get("culture", owner_runtime.get("primary_culture", "unknown"))),
			"religion": String(source.get("religion", owner_runtime.get("state_religion", "unknown"))),
			"cores": (source.get("cores", [owner] if not owner.is_empty() else []) as Array).duplicate(),
			"claims": (source.get("claims", []) as Array).duplicate(true),
			"separatism_bp": 0, "recently_conquered_until_day": -1,
			"conversion": {}, "unrest_sources": {}, "last_revolt_day": -1,
		}, false)
		state["economy"] = economy
		world.province_states[province_id] = state
	world.global_flags["country_depth_enabled"] = true
	world.global_flags["country_depth_version"] = 1
	world.global_flags["content_version"] = definitions.content_version()
	world.global_flags["country_depth_active_countries"] = _current_land_country_tags(world)
	world.global_flags["country_depth_simulated_countries"] = definitions.country_tags()
	world.global_flags["war_exhaustion_countries"] = []
	for counter in ["next_subject_id", "next_country_event_id", "next_rebel_faction_id"]:
		world.global_counters[counter] = maxi(1, int(world.global_counters.get(counter, 1)))
	for raw_tag in definitions.country_tags():
		recalculate_country_modifiers(world, String(raw_tag), definitions)
	_rebuild_dynamic_province_index(world)


static func ensure_world(world: CampaignWorldState, definitions: CountryDepthDefinitions) -> void:
	if int(world.global_flags.get("country_depth_version", 0)) != 1:
		initialize_world(world, definitions)


static func process_month(world: CampaignWorldState, events: SimulationEventBus, definitions: CountryDepthDefinitions) -> void:
	ensure_world(world, definitions)
	_expire_pending_events(world, events, definitions)
	_process_country_month_start(world, definitions)
	_process_provinces(world, events, definitions)
	_process_subjects(world, events, definitions)
	_process_war_exhaustion(world)
	_reconcile_personal_unions(world, events)
	_reconcile_country_status(world, events)
	_trigger_country_events(world, events, definitions)


static func recalculate_country_modifiers(world: CampaignWorldState, country_tag: String, definitions: CountryDepthDefinitions) -> Dictionary:
	if not world.has_country(country_tag):
		return {}
	var runtime := world.country_runtime(country_tag)
	var result := {"tax_modifier_bp": 0, "production_modifier_bp": 0, "manpower_modifier_bp": 0, "unrest_modifier_bp": 0, "control_growth_bp": 0, "conversion_speed_bp": 0, "army_power_bp": 0, "stability_cost_modifier_bp": 0, "subject_liberty_modifier_bp": 0, "diplomatic_reputation": 0, "tolerance_own": 0, "tolerance_heretic": 0, "tolerance_heathen": 0}
	_merge_modifiers(result, definitions.government(String(runtime.get("government_id", "feudal_monarchy"))).get("base_modifiers", {}))
	for raw_reform in runtime.get("government_reforms", []):
		_merge_modifiers(result, definitions.reform(String(raw_reform)).get("modifiers", {}))
	var idea_id := String(runtime.get("idea_group_id", ""))
	if not idea_id.is_empty():
		_merge_modifiers(result, definitions.idea_group(idea_id).get("modifiers", {}))
	for raw_modifier in runtime.get("temporary_modifiers", []):
		_merge_modifiers(result, (raw_modifier as Dictionary).get("modifiers", {}))
	runtime["country_depth_modifiers"] = result
	world.set_country_runtime(country_tag, runtime)
	return result


static func technology_cost(world: CampaignWorldState, country_tag: String, track: String, definitions: CountryDepthDefinitions) -> int:
	if track not in CountryDepthDefinitions.TECHNOLOGY_TRACKS or not world.has_country(country_tag):
		return -1
	var runtime := world.country_runtime(country_tag)
	var current := int((runtime.get("technology", {}) as Dictionary).get(track, 0))
	var track_definition := definitions.technology_track(track)
	var levels: Array = track_definition.get("levels", [])
	if current + 1 >= levels.size():
		return -1
	var next: Dictionary = levels[current + 1]
	var current_year := int(SimulationDateScript.day_to_date(world.current_day)["year"])
	var year_delta := int(next.get("year", current_year)) - current_year
	var cost := int(track_definition.get("base_cost", 600))
	if year_delta > 0:
		cost += year_delta * 20
	else:
		cost = maxi(300, cost + year_delta * 5)
	return cost


static func advance_technology(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, track: String, definitions: CountryDepthDefinitions) -> void:
	var runtime := world.country_runtime(country_tag)
	var technology: Dictionary = runtime.get("technology", {})
	var points: Dictionary = runtime.get("technology_points", {})
	var cost := technology_cost(world, country_tag, track, definitions)
	points[track] = int(points.get(track, 0)) - cost
	technology[track] = int(technology.get(track, 0)) + 1
	runtime["technology"] = technology
	runtime["technology_points"] = points
	world.set_country_runtime(country_tag, runtime)
	recalculate_country_modifiers(world, country_tag, definitions)
	events.technology_advanced.emit(country_tag, track, int(technology[track]))


static func enact_reform(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, reform_id: String, definitions: CountryDepthDefinitions) -> void:
	var reform := definitions.reform(reform_id)
	var runtime := world.country_runtime(country_tag)
	var reforms: Array = runtime.get("government_reforms", [])
	reforms.append(reform_id)
	reforms.sort()
	runtime["government_reforms"] = reforms
	runtime["authority_bp"] = int(runtime.get("authority_bp", 0)) - int(reform.get("authority_cost_bp", 0))
	runtime["treasury"] = int(runtime.get("treasury", 0)) - int(reform.get("treasury_cost", 0))
	world.set_country_runtime(country_tag, runtime)
	recalculate_country_modifiers(world, country_tag, definitions)
	events.government_reformed.emit(country_tag, reform_id)


static func change_government(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, government_id: String, definitions: CountryDepthDefinitions) -> void:
	var runtime := world.country_runtime(country_tag)
	var old_government_id := String(runtime.get("government_id", "feudal_monarchy"))
	runtime["government_id"] = government_id
	runtime["government_reforms"] = []
	runtime["stability"] = clampi(int(runtime.get("stability", 0)) - 1, -3, 3)
	runtime["authority_bp"] = maxi(0, int(runtime.get("authority_bp", 0)) - 2000)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - 100000
	world.set_country_runtime(country_tag, runtime)
	recalculate_country_modifiers(world, country_tag, definitions)
	events.government_changed.emit(country_tag, old_government_id, government_id)
	events.stability_changed.emit(country_tag, int(runtime["stability"]))


static func select_idea_group(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, idea_id: String, definitions: CountryDepthDefinitions) -> void:
	var runtime := world.country_runtime(country_tag)
	runtime["idea_group_id"] = idea_id
	world.set_country_runtime(country_tag, runtime)
	recalculate_country_modifiers(world, country_tag, definitions)
	events.idea_group_selected.emit(country_tag, idea_id)


static func start_conversion(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, province_id: int, conversion_type: String, target: String) -> void:
	var state: Dictionary = world.province_states[province_id]
	var economy: Dictionary = state.get("economy", {})
	economy["conversion"] = {"type": conversion_type, "target": target, "progress_bp": 0, "country_tag": country_tag, "start_day": world.current_day}
	state["economy"] = economy
	world.province_states[province_id] = state
	mark_province_dynamic(world, province_id)
	events.conversion_started.emit(country_tag, province_id, conversion_type, target)


static func fabricate_claim(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, province_id: int) -> void:
	var state: Dictionary = world.province_states[province_id]
	var economy: Dictionary = state.get("economy", {})
	var claims: Array = economy.get("claims", [])
	claims.append({"country_tag": country_tag, "created_day": world.current_day, "expires_day": world.current_day + CLAIM_DURATION_DAYS})
	economy["claims"] = claims
	state["economy"] = economy
	world.province_states[province_id] = state
	var runtime := world.country_runtime(country_tag)
	var points: Dictionary = runtime.get("technology_points", {})
	points["diplomatic"] = int(points.get("diplomatic", 0)) - 100
	runtime["technology_points"] = points
	world.set_country_runtime(country_tag, runtime)
	events.province_claim_created.emit(country_tag, province_id, world.current_day + CLAIM_DURATION_DAYS)


static func has_valid_claim_or_core(world: CampaignWorldState, country_tag: String, province_id: int) -> bool:
	if not world.has_province(province_id):
		return false
	var economy: Dictionary = world.province_states[province_id].get("economy", {})
	if (economy.get("cores", []) as Array).has(country_tag):
		return true
	for raw_claim in economy.get("claims", []):
		var claim: Dictionary = raw_claim
		if String(claim.get("country_tag", "")) == country_tag and (int(claim.get("expires_day", -1)) < 0 or world.current_day <= int(claim.get("expires_day", -1))):
			return true
	return false


static func conquest_peace_cost(world: CampaignWorldState, country_tag: String, province_id: int) -> int:
	var economy: Dictionary = world.province_states.get(province_id, {}).get("economy", {})
	if (economy.get("cores", []) as Array).has(country_tag):
		return 10
	return 15 if has_valid_claim_or_core(world, country_tag, province_id) else 25


static func accept_culture(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, culture_id: String) -> void:
	var runtime := world.country_runtime(country_tag)
	var accepted: Array = runtime.get("accepted_cultures", [])
	accepted.append(culture_id)
	accepted.sort()
	runtime["accepted_cultures"] = accepted
	var points: Dictionary = runtime.get("technology_points", {})
	points["diplomatic"] = int(points.get("diplomatic", 0)) - 200
	runtime["technology_points"] = points
	world.set_country_runtime(country_tag, runtime)
	events.culture_accepted.emit(country_tag, culture_id)


static func suppress_rebels(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, faction_id: String) -> void:
	var faction: Dictionary = world.rebel_faction_registry[faction_id]
	faction["progress_bp"] = maxi(0, int(faction.get("progress_bp", 0)) - 5000)
	faction["status"] = "organizing"
	world.rebel_faction_registry[faction_id] = faction
	var runtime := world.country_runtime(country_tag)
	runtime["manpower"] = maxi(0, int(runtime.get("manpower", 0)) - 1000)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - 25000
	world.set_country_runtime(country_tag, runtime)
	events.rebels_suppressed.emit(country_tag, faction_id)


static func create_subject(world: CampaignWorldState, events: SimulationEventBus, overlord: String, subject_tag: String, subject_type: String, presentation := "") -> String:
	var subject_id := "subject_%06d" % world.take_counter("next_subject_id")
	world.subject_registry[subject_id] = {"subject_id": subject_id, "type": subject_type, "presentation": presentation, "overlord": overlord, "subject": subject_tag, "liberty_desire_bp": 2500, "income_bp": 1000 if subject_type == "vassal" else 0, "integration_progress_bp": 0, "integration_active": false, "created_day": world.current_day, "status": "active", "war_participation": true}
	var relation := DiplomacySystemScript.relation(world, overlord, subject_tag)
	relation["subject"] = {"overlord": overlord, "subject": subject_tag, "type": subject_type, "presentation": presentation}
	DiplomacySystemScript.set_relation(world, overlord, subject_tag, relation)
	events.subject_created.emit(subject_id, overlord, subject_tag, subject_type)
	return subject_id


static func start_subject_integration(world: CampaignWorldState, events: SimulationEventBus, subject_id: String) -> void:
	var record: Dictionary = world.subject_registry[subject_id]
	record["integration_active"] = true
	record["integration_start_day"] = world.current_day
	world.subject_registry[subject_id] = record
	events.subject_integration_started.emit(subject_id)


static func pending_event_for_country(world: CampaignWorldState, country_tag: String) -> Dictionary:
	for record in world.country_event_registry.values():
		var event: Dictionary = record
		if String(event.get("country_tag", "")) == country_tag and String(event.get("status", "")) == "pending":
			return event.duplicate(true)
	return {}


static func choose_event_option(world: CampaignWorldState, events: SimulationEventBus, event_instance_id: String, option_id: String, definitions: CountryDepthDefinitions) -> String:
	if not world.country_event_registry.has(event_instance_id):
		return "The event no longer exists."
	var instance: Dictionary = world.country_event_registry[event_instance_id]
	if String(instance.get("status", "")) != "pending":
		return "The event is no longer pending."
	var definition := definitions.event(String(instance.get("definition_id", "")))
	var selected := {}
	for raw_option in definition.get("options", []):
		if String((raw_option as Dictionary).get("id", "")) == option_id:
			selected = raw_option
			break
	if selected.is_empty():
		return "The selected event option is invalid."
	var country_tag := String(instance.get("country_tag", ""))
	apply_effects(world, events, country_tag, selected.get("effects", []), definitions)
	instance["status"] = "resolved"
	instance["option_id"] = option_id
	instance["resolved_day"] = world.current_day
	world.country_event_registry[event_instance_id] = instance
	var runtime := world.country_runtime(country_tag)
	var history: Array = runtime.get("event_history", [])
	history.append({"event_id": String(instance.get("definition_id", "")), "option_id": option_id, "day": world.current_day})
	while history.size() > 64:
		history.pop_front()
	runtime["event_history"] = history
	var cooldowns: Dictionary = runtime.get("event_cooldowns", {})
	cooldowns[String(instance.get("definition_id", ""))] = world.current_day + int(definition.get("cooldown_days", 365))
	runtime["event_cooldowns"] = cooldowns
	world.set_country_runtime(country_tag, runtime)
	events.country_event_resolved.emit(event_instance_id, country_tag, option_id)
	return ""


static func decision_validation(world: CampaignWorldState, country_tag: String, decision_id: String, definitions: CountryDepthDefinitions) -> String:
	if not world.has_country(country_tag):
		return "The country does not exist."
	var definition := definitions.decision(decision_id)
	if definition.is_empty():
		return "The decision does not exist."
	var runtime := world.country_runtime(country_tag)
	if (runtime.get("enacted_decisions", []) as Array).has(decision_id):
		return "This decision has already been enacted."
	var requirements: Dictionary = definition.get("requirements", {})
	if not (requirements.get("country_in", []) as Array).is_empty() and not (requirements.get("country_in", []) as Array).has(country_tag):
		return "This country cannot enact the decision."
	var technology: Dictionary = runtime.get("technology", {})
	for track in CountryDepthDefinitions.TECHNOLOGY_TRACKS:
		if int(technology.get(track, 0)) < int(requirements.get("%s_tech_gte" % track, 0)):
			return "%s technology is too low." % track.capitalize()
	if int(runtime.get("stability", 0)) < int(requirements.get("stability_gte", -3)):
		return "Stability is too low."
	if int(runtime.get("authority_bp", 0)) < int(requirements.get("authority_gte_bp", 0)):
		return "Government authority is too low."
	if int(runtime.get("treasury", 0)) < int(requirements.get("treasury_gte", 0)):
		return "The treasury is too low."
	for raw_province in requirements.get("owns_provinces", []):
		if world.get_province_owner(int(raw_province)) != country_tag:
			return "Required province %d is not owned." % int(raw_province)
	return ""


static func enact_decision(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, decision_id: String, definitions: CountryDepthDefinitions) -> void:
	var definition := definitions.decision(decision_id)
	apply_effects(world, events, country_tag, definition.get("effects", []), definitions)
	if world.has_country(country_tag):
		var runtime := world.country_runtime(country_tag)
		var enacted: Array = runtime.get("enacted_decisions", [])
		enacted.append(decision_id)
		runtime["enacted_decisions"] = enacted
		world.set_country_runtime(country_tag, runtime)
	events.country_decision_enacted.emit(country_tag, decision_id)


static func apply_effects(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, effects: Array, definitions: CountryDepthDefinitions) -> void:
	for raw_effect in effects:
		var effect: Dictionary = raw_effect
		var runtime := world.country_runtime(country_tag)
		match String(effect.get("type", "")):
			"treasury": runtime["treasury"] = int(runtime.get("treasury", 0)) + int(effect.get("amount", 0))
			"stability": runtime["stability"] = clampi(int(runtime.get("stability", 0)) + int(effect.get("amount", 0)), -3, 3)
			"authority": runtime["authority_bp"] = clampi(int(runtime.get("authority_bp", 0)) + int(effect.get("amount_bp", 0)), 0, BASIS_POINTS)
			"centralisation": runtime["centralisation_bp"] = clampi(int(runtime.get("centralisation_bp", 0)) + int(effect.get("amount_bp", 0)), 0, BASIS_POINTS)
			"tolerance_heathen": runtime["tolerance_heathen"] = int(runtime.get("tolerance_heathen", -1)) + int(effect.get("amount", 0))
			"conversion_speed":
				var modifier := {"id": "event_conversion_speed", "expires_day": world.current_day + 1825, "modifiers": {"conversion_speed_bp": int(effect.get("amount_bp", 0))}}
				var modifiers: Array = runtime.get("temporary_modifiers", [])
				modifiers.append(modifier)
				runtime["temporary_modifiers"] = modifiers
			"country_modifier":
				var modifiers: Array = runtime.get("temporary_modifiers", [])
				modifiers.append({"id": String(effect.get("id", "modifier")), "expires_day": -1 if int(effect.get("duration_days", -1)) < 0 else world.current_day + int(effect.get("duration_days", 0)), "modifiers": (effect.get("modifiers", {}) as Dictionary).duplicate(true)})
				runtime["temporary_modifiers"] = modifiers
			"province_unrest":
				for province_id in world.get_country_provinces(country_tag):
					var state: Dictionary = world.province_states[province_id]
					var economy: Dictionary = state.get("economy", {})
					economy["event_unrest_bp"] = int(economy.get("event_unrest_bp", 0)) + int(effect.get("amount_bp", 0))
					state["economy"] = economy
					world.province_states[province_id] = state
					mark_province_dynamic(world, province_id)
			"form_country":
				world.set_country_runtime(country_tag, runtime)
				form_country(world, events, country_tag, String(effect.get("new_tag", "")), definitions)
				continue
		world.set_country_runtime(country_tag, runtime)
	recalculate_country_modifiers(world, country_tag, definitions)


static func form_country(world: CampaignWorldState, events: SimulationEventBus, old_tag: String, new_tag: String, definitions: CountryDepthDefinitions) -> String:
	if not world.has_country(old_tag) or not world.has_country(new_tag) or old_tag == new_tag:
		return "The country formation has invalid tags."
	if not world.get_country_provinces(new_tag).is_empty():
		return "The target country already owns provinces."
	var old_runtime := world.country_runtime(old_tag)
	var new_runtime := old_runtime.duplicate(true)
	new_runtime["country_status"] = "active"
	new_runtime["formed_from"] = old_tag
	new_runtime["formed_into"] = ""
	world.set_country_runtime(new_tag, new_runtime)
	old_runtime["country_status"] = "formed"
	old_runtime["formed_into"] = new_tag
	world.set_country_runtime(old_tag, old_runtime)
	for province_id in world.get_country_provinces(old_tag):
		var old_owner := world.set_province_owner(province_id, new_tag)
		var old_controller := world.set_province_controller(province_id, new_tag)
		var state: Dictionary = world.province_states[province_id]
		var economy: Dictionary = state.get("economy", {})
		var cores: Array = economy.get("cores", [])
		if not cores.has(new_tag):
			cores.append(new_tag)
		economy["cores"] = cores
		state["economy"] = economy
		world.province_states[province_id] = state
		events.province_owner_changed.emit(province_id, old_owner, new_tag)
		events.province_controller_changed.emit(province_id, old_controller, new_tag)
	for army_id in world.country_armies(old_tag):
		var army: Dictionary = world.army_registry[army_id]
		army["owner_country_id"] = new_tag
		world.army_registry[army_id] = army
	for raw_id in world.character_registry:
		var character: Dictionary = world.character_registry[raw_id]
		if String(character.get("employer_country", "")) == old_tag:
			character["employer_country"] = new_tag
			world.character_registry[raw_id] = character
	for raw_id in world.title_registry:
		var title: Dictionary = world.title_registry[raw_id]
		if String(title.get("country_tag", "")) == old_tag:
			title["country_tag"] = new_tag
			world.title_registry[raw_id] = title
	if world.player_country == old_tag:
		world.player_country = new_tag
		events.player_country_changed.emit(old_tag, new_tag)
	_replace_country_references(world, old_tag, new_tag)
	world._rebuild_country_index()
	var simulated: Array = world.global_flags.get("country_depth_simulated_countries", [])
	if simulated.has(old_tag):
		simulated.erase(old_tag)
	if not simulated.has(new_tag):
		simulated.append(new_tag)
		simulated.sort()
	world.global_flags["country_depth_simulated_countries"] = simulated
	recalculate_country_modifiers(world, new_tag, definitions)
	events.country_formed.emit(old_tag, new_tag)
	return ""


static func release_country(world: CampaignWorldState, events: SimulationEventBus, releasing_tag: String, released_tag: String, province_ids: Array, definitions: CountryDepthDefinitions) -> String:
	if not world.has_country(releasing_tag) or not world.has_country(released_tag) or releasing_tag == released_tag:
		return "Release requires two valid countries."
	if province_ids.is_empty():
		return "At least one province must be released."
	for raw_id in province_ids:
		var province_id := int(raw_id)
		if world.get_province_owner(province_id) != releasing_tag or not (world.province_states[province_id].get("economy", {}).get("cores", []) as Array).has(released_tag):
			return "Province %d is not an owned core of %s." % [province_id, released_tag]
	for raw_id in province_ids:
		var province_id := int(raw_id)
		var old_owner := world.set_province_owner(province_id, released_tag)
		var old_controller := world.set_province_controller(province_id, released_tag)
		events.province_owner_changed.emit(province_id, old_owner, released_tag)
		events.province_controller_changed.emit(province_id, old_controller, released_tag)
	var runtime := world.country_runtime(released_tag)
	runtime["country_status"] = "active"
	world.set_country_runtime(released_tag, runtime)
	world._rebuild_country_index()
	recalculate_country_modifiers(world, released_tag, definitions)
	events.country_released.emit(releasing_tag, released_tag, province_ids.duplicate())
	return ""


static func _process_provinces(world: CampaignWorldState, events: SimulationEventBus, definitions: CountryDepthDefinitions) -> void:
	var country_totals := {}
	var country_counts := {}
	var matching_religion := {}
	var runtime_cache := {}
	var cultures := definitions.cultures()
	var religions := definitions.religions()
	var dynamic_lookup := {}
	for raw_id in world.global_flags.get("country_depth_dynamic_provinces", []):
		dynamic_lookup[int(raw_id)] = true
	# Country-wide pressure wakes every owned authored province; un-authored
	# global placeholders only enter this pass when a production command marks
	# one of their provinces dynamic.
	var processing_countries := {}
	for raw_tag in world.global_flags.get("country_depth_simulated_countries", []):
		processing_countries[String(raw_tag)] = true
	for raw_id in dynamic_lookup:
		var dynamic_owner := world.get_province_owner(int(raw_id))
		if not dynamic_owner.is_empty():
			processing_countries[dynamic_owner] = true
	var processing_tags := processing_countries.keys()
	processing_tags.sort()
	for raw_tag in processing_tags:
		var tag := String(raw_tag)
		if not world.has_country(tag) or (world.country_to_provinces.get(tag, []) as Array).is_empty():
			continue
		var runtime := world.country_runtime(tag)
		runtime_cache[tag] = runtime
		var provinces: Array = world.country_to_provinces.get(tag, [])
		country_counts[tag] = provinces.size()
		matching_religion[tag] = provinces.size()
		var modifiers: Dictionary = runtime.get("country_depth_modifiers", {})
		if int(runtime.get("stability", 0)) < 0 or int(runtime.get("war_exhaustion_bp", 0)) > 0 or int(modifiers.get("unrest_modifier_bp", 0)) > 0:
			for province_id in provinces:
				dynamic_lookup[int(province_id)] = true
	var ids := dynamic_lookup.keys()
	ids.sort()
	var retained_dynamic: Array[int] = []
	for raw_id in ids:
		var province_id := int(raw_id)
		if not world.has_province(province_id):
			continue
		var owner := world.get_province_owner(province_id)
		if owner.is_empty() or not world.has_country(owner):
			continue
		if not runtime_cache.has(owner):
			runtime_cache[owner] = world.country_runtime(owner)
		var runtime: Dictionary = runtime_cache[owner]
		var state: Dictionary = world.province_states[province_id]
		var economy: Dictionary = state.get("economy", {})
		# Separatism and one-off event unrest fade slowly instead of becoming
		# permanent invisible state. Only provinces carrying either value pay the
		# mutation cost.
		var decayed := false
		if int(economy.get("separatism_bp", 0)) > 0:
			economy["separatism_bp"] = maxi(0, int(economy.get("separatism_bp", 0)) - 25)
			decayed = true
		if int(economy.get("event_unrest_bp", 0)) > 0:
			economy["event_unrest_bp"] = maxi(0, int(economy.get("event_unrest_bp", 0)) - 50)
			decayed = true
		if _is_stable_province(world, owner, province_id, runtime, economy):
			if decayed:
				state["economy"] = economy
				world.province_states[province_id] = state
			continue
		var sources := _unrest_sources(world, owner, province_id, runtime, economy, cultures, religions)
		var unrest := 0
		for value in sources.values():
			unrest += int(value)
		economy["unrest_sources"] = sources
		economy["unrest_bp"] = clampi(unrest, 0, BASIS_POINTS)
		var modifiers: Dictionary = runtime.get("country_depth_modifiers", {})
		var growth := 100 + int(modifiers.get("control_growth_bp", 0)) - int(economy["unrest_bp"]) / 50
		if world.get_province_controller(province_id) != owner:
			growth = -200
		economy["control_bp"] = clampi(int(economy.get("control_bp", BASIS_POINTS)) + growth, 0, BASIS_POINTS)
		_process_conversion(world, events, owner, province_id, economy, runtime, definitions)
		state["economy"] = economy
		world.province_states[province_id] = state
		country_totals[owner] = int(country_totals.get(owner, 0)) + int(economy["unrest_bp"])
		if String(economy.get("religion", "unknown")) != String(runtime.get("state_religion", "unknown")):
			matching_religion[owner] = int(matching_religion.get(owner, 0)) - 1
		_process_rebel_faction(world, events, owner, province_id, economy)
		if not _is_stable_province(world, owner, province_id, runtime, economy):
			retained_dynamic.append(province_id)
	for raw_tag in country_counts:
		var tag := String(raw_tag)
		var runtime: Dictionary = runtime_cache[tag]
		var count := int(country_counts[tag])
		runtime["average_unrest_bp"] = int(country_totals.get(tag, 0)) / maxi(count, 1)
		runtime["religious_unity_bp"] = int(matching_religion.get(tag, 0)) * BASIS_POINTS / maxi(count, 1)
		world.set_country_runtime(tag, runtime)
	world.global_flags["country_depth_dynamic_provinces"] = retained_dynamic


static func _is_stable_province(world: CampaignWorldState, owner: String, province_id: int, runtime: Dictionary, economy: Dictionary) -> bool:
	if int(economy.get("unrest_bp", 0)) != 0 or int(economy.get("control_bp", BASIS_POINTS)) != BASIS_POINTS:
		return false
	if world.get_province_controller(province_id) != owner or not (economy.get("conversion", {}) as Dictionary).is_empty():
		return false
	if int(economy.get("separatism_bp", 0)) > 0 or world.current_day <= int(economy.get("recently_conquered_until_day", -1)) or int(economy.get("event_unrest_bp", 0)) > 0:
		return false
	if int(runtime.get("stability", 0)) < 0 or int(runtime.get("war_exhaustion_bp", 0)) > 0:
		return false
	if String(economy.get("culture", "unknown")) != String(runtime.get("primary_culture", "unknown")) or String(economy.get("religion", "unknown")) != String(runtime.get("state_religion", "unknown")):
		return false
	return int((runtime.get("country_depth_modifiers", {}) as Dictionary).get("unrest_modifier_bp", 0)) <= 0


static func _unrest_sources(world: CampaignWorldState, country_tag: String, province_id: int, runtime: Dictionary, economy: Dictionary, cultures: Dictionary, religions: Dictionary) -> Dictionary:
	var sources := {"stability": -int(runtime.get("stability", 0)) * 400, "low_control": (BASIS_POINTS - int(economy.get("control_bp", BASIS_POINTS))) / 10, "separatism": int(economy.get("separatism_bp", 0)), "recent_conquest": 1200 if world.current_day <= int(economy.get("recently_conquered_until_day", -1)) else 0, "events": int(economy.get("event_unrest_bp", 0)), "war_exhaustion": int(runtime.get("war_exhaustion_bp", 0)) / 5}
	var culture := String(economy.get("culture", "unknown"))
	var primary := String(runtime.get("primary_culture", "unknown"))
	if culture != primary and not (runtime.get("accepted_cultures", []) as Array).has(culture):
		sources["culture"] = 300 if String((cultures.get(culture, {}) as Dictionary).get("group", "")) == String((cultures.get(primary, {}) as Dictionary).get("group", "")) else 800
	else:
		sources["culture"] = 0
	var religion := String(economy.get("religion", "unknown"))
	var state_religion := String(runtime.get("state_religion", "unknown"))
	if religion != state_religion:
		var same_group := String((religions.get(religion, {}) as Dictionary).get("group", "")) == String((religions.get(state_religion, {}) as Dictionary).get("group", ""))
		var tolerance := int(runtime.get("tolerance_heretic" if same_group else "tolerance_heathen", 0))
		sources["religion"] = maxi(0, (600 if same_group else 1200) - tolerance * 200)
	else:
		sources["religion"] = -int(runtime.get("tolerance_own", 2)) * 100
	sources["country_modifiers"] = int((runtime.get("country_depth_modifiers", {}) as Dictionary).get("unrest_modifier_bp", 0))
	return sources


static func _process_conversion(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, province_id: int, economy: Dictionary, runtime: Dictionary, definitions: CountryDepthDefinitions) -> void:
	var conversion: Dictionary = economy.get("conversion", {})
	if conversion.is_empty():
		return
	if String(conversion.get("country_tag", "")) != country_tag:
		economy["conversion"] = {}
		return
	var speed := CONVERSION_PROGRESS_PER_MONTH + int((runtime.get("country_depth_modifiers", {}) as Dictionary).get("conversion_speed_bp", 0)) / 10
	for building_id in economy.get("buildings", []):
		speed += int(EconomyDefinitionsScript.load_default().building(String(building_id)).get("conversion_speed_bp", 0)) / 10
	conversion["progress_bp"] = mini(BASIS_POINTS, int(conversion.get("progress_bp", 0)) + maxi(speed, 100))
	if int(conversion["progress_bp"]) >= BASIS_POINTS:
		var conversion_type := String(conversion.get("type", ""))
		var target := String(conversion.get("target", ""))
		economy["religion" if conversion_type == "religion" else "culture"] = target
		economy["conversion"] = {}
		events.province_converted.emit(country_tag, province_id, conversion_type, target)
	else:
		economy["conversion"] = conversion


static func _process_rebel_faction(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, province_id: int, economy: Dictionary) -> void:
	if int(economy.get("unrest_bp", 0)) < 5000:
		return
	var faction_id := "rebel_%s_%d" % [country_tag, province_id]
	var faction: Dictionary = world.rebel_faction_registry.get(faction_id, {"faction_id": faction_id, "country_tag": country_tag, "province_id": province_id, "type": "separatists" if int(economy.get("separatism_bp", 0)) > 0 else "religious", "progress_bp": 0, "status": "organizing", "created_day": world.current_day})
	faction["progress_bp"] = mini(BASIS_POINTS, int(faction.get("progress_bp", 0)) + int(economy.get("unrest_bp", 0)) / 20)
	if int(faction["progress_bp"]) >= BASIS_POINTS and String(faction.get("status", "")) != "uprising":
		faction["status"] = "uprising"
		faction["uprising_day"] = world.current_day
		economy["control_bp"] = mini(int(economy.get("control_bp", BASIS_POINTS)), 2500)
		economy["devastation_bp"] = mini(BASIS_POINTS, int(economy.get("devastation_bp", 0)) + 1000)
		economy["last_revolt_day"] = world.current_day
		events.revolt_started.emit(faction_id, country_tag, province_id)
	world.rebel_faction_registry[faction_id] = faction


static func _process_subjects(world: CampaignWorldState, events: SimulationEventBus, definitions: CountryDepthDefinitions) -> void:
	var ids := world.subject_registry.keys()
	ids.sort()
	for raw_id in ids:
		var subject_id := String(raw_id)
		var record: Dictionary = world.subject_registry[raw_id]
		if String(record.get("status", "active")) != "active":
			continue
		var subject_tag := String(record.get("subject", ""))
		var overlord := String(record.get("overlord", ""))
		var subject_runtime := world.country_runtime(subject_tag)
		var overlord_runtime := world.country_runtime(overlord)
		var relative_strength := _country_strength(world, subject_tag) * BASIS_POINTS / maxi(_country_strength(world, overlord), 1)
		var modifiers: Dictionary = overlord_runtime.get("country_depth_modifiers", {})
		record["liberty_desire_bp"] = clampi(1500 + relative_strength / 2 + int(subject_runtime.get("average_unrest_bp", 0)) / 2 - int(modifiers.get("subject_liberty_modifier_bp", 0)), 0, BASIS_POINTS)
		if bool(record.get("integration_active", false)):
			record["integration_progress_bp"] = mini(BASIS_POINTS, int(record.get("integration_progress_bp", 0)) + BASIS_POINTS / INTEGRATION_MONTHS)
			if int(record["integration_progress_bp"]) >= BASIS_POINTS:
				_integrate_subject(world, events, subject_id, record, definitions)
				continue
		world.subject_registry[subject_id] = record


static func _process_war_exhaustion(world: CampaignWorldState) -> void:
	var candidates := {}
	for raw_tag in world.global_flags.get("war_exhaustion_countries", []):
		candidates[String(raw_tag)] = true
	for raw_war in world.war_registry.values():
		var war: Dictionary = raw_war
		if String(war.get("status", "")) != "active":
			continue
		for raw_tag in (war.get("attackers", []) as Array) + (war.get("defenders", []) as Array):
			candidates[String(raw_tag)] = true
	var tags := candidates.keys()
	tags.sort()
	var retained: Array[String] = []
	for raw_tag in tags:
		var tag := String(raw_tag)
		if not world.has_country(tag):
			continue
		var runtime := world.country_runtime(tag)
		var at_war := not DiplomacySystemScript.country_wars(world, tag).is_empty()
		var change := 100 if at_war else -75
		runtime["war_exhaustion_bp"] = clampi(int(runtime.get("war_exhaustion_bp", 0)) + change, 0, BASIS_POINTS)
		world.set_country_runtime(tag, runtime)
		if at_war or int(runtime["war_exhaustion_bp"]) > 0:
			retained.append(tag)
	world.global_flags["war_exhaustion_countries"] = retained


static func _integrate_subject(world: CampaignWorldState, events: SimulationEventBus, subject_id: String, record: Dictionary, definitions: CountryDepthDefinitions) -> void:
	var overlord := String(record.get("overlord", ""))
	var subject_tag := String(record.get("subject", ""))
	for province_id in world.get_country_provinces(subject_tag):
		var old_owner := world.set_province_owner(province_id, overlord)
		var old_controller := world.set_province_controller(province_id, overlord)
		var state: Dictionary = world.province_states[province_id]
		var economy: Dictionary = state.get("economy", {})
		economy["recently_conquered_until_day"] = world.current_day + 1825
		economy["separatism_bp"] = 2500
		state["economy"] = economy
		world.province_states[province_id] = state
		mark_province_dynamic(world, province_id)
		events.province_owner_changed.emit(province_id, old_owner, overlord)
		events.province_controller_changed.emit(province_id, old_controller, overlord)
	record["status"] = "integrated"
	record["integration_day"] = world.current_day
	world.subject_registry[subject_id] = record
	var relation := DiplomacySystemScript.relation(world, overlord, subject_tag)
	relation["subject"] = {}
	DiplomacySystemScript.set_relation(world, overlord, subject_tag, relation)
	var runtime := world.country_runtime(subject_tag)
	runtime["country_status"] = "integrated"
	world.set_country_runtime(subject_tag, runtime)
	for raw_id in world.character_registry:
		var character: Dictionary = world.character_registry[raw_id]
		if String(character.get("employer_country", "")) == subject_tag:
			character["employer_country"] = overlord
			world.character_registry[raw_id] = character
	world._rebuild_country_index()
	recalculate_country_modifiers(world, overlord, definitions)
	events.subject_integrated.emit(subject_id, overlord, subject_tag)


static func _reconcile_personal_unions(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var title_countries := {}
	for raw_title in world.title_registry.values():
		var title: Dictionary = raw_title
		var title_country := String(title.get("country_tag", ""))
		if not title_country.is_empty():
			title_countries[title_country] = true
	var tags := title_countries.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var senior := String(world.country_runtime(tag).get("personal_union_senior", ""))
		if senior.is_empty() or not world.has_country(senior) or not subject_between(world, senior, tag).is_empty():
			continue
		create_subject(world, events, senior, tag, "personal_union")


static func subject_between(world: CampaignWorldState, overlord: String, subject_tag: String) -> String:
	for raw_id in world.subject_registry:
		var record: Dictionary = world.subject_registry[raw_id]
		if String(record.get("status", "active")) == "active" and String(record.get("overlord", "")) == overlord and String(record.get("subject", "")) == subject_tag:
			return String(raw_id)
	return ""


static func direct_subjects(world: CampaignWorldState, overlord: String) -> Array[String]:
	var result: Array[String] = []
	for record in world.subject_registry.values():
		var subject: Dictionary = record
		if String(subject.get("status", "active")) == "active" and String(subject.get("overlord", "")) == overlord and bool(subject.get("war_participation", true)):
			result.append(String(subject.get("subject", "")))
	result.sort()
	return result


static func overlord_of(world: CampaignWorldState, subject_tag: String) -> String:
	for record in world.subject_registry.values():
		var subject: Dictionary = record
		if String(subject.get("status", "active")) == "active" and String(subject.get("subject", "")) == subject_tag:
			return String(subject.get("overlord", ""))
	return ""


static func _trigger_country_events(world: CampaignWorldState, events: SimulationEventBus, definitions: CountryDepthDefinitions) -> void:
	var event_ids := definitions.events().keys()
	event_ids.sort()
	for tag in definitions.country_tags():
		if not world.has_country(tag) or world.get_country_provinces(tag).is_empty() or not pending_event_for_country(world, tag).is_empty():
			continue
		var runtime := world.country_runtime(tag)
		for raw_event_id in event_ids:
			var event_id := String(raw_event_id)
			var definition := definitions.event(event_id)
			if world.current_day < int((runtime.get("event_cooldowns", {}) as Dictionary).get(event_id, -1)) or not _event_trigger_passes(world, tag, definition.get("trigger", {})):
				continue
			var instance_id := "country_event_%06d" % world.take_counter("next_country_event_id")
			world.country_event_registry[instance_id] = {"instance_id": instance_id, "definition_id": event_id, "country_tag": tag, "status": "pending", "created_day": world.current_day, "expires_day": world.current_day + 90}
			events.country_event_triggered.emit(instance_id, tag, event_id)
			break


static func _expire_pending_events(world: CampaignWorldState, events: SimulationEventBus, definitions: CountryDepthDefinitions) -> void:
	var ids := world.country_event_registry.keys()
	ids.sort()
	for raw_id in ids:
		var instance: Dictionary = world.country_event_registry[raw_id]
		if String(instance.get("status", "")) != "pending" or world.current_day <= int(instance.get("expires_day", world.current_day)):
			continue
		var definition := definitions.event(String(instance.get("definition_id", "")))
		var options: Array = definition.get("options", [])
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("ai_weight", 0)) > int(b.get("ai_weight", 0)) if int(a.get("ai_weight", 0)) != int(b.get("ai_weight", 0)) else String(a.get("id", "")) < String(b.get("id", "")))
		if options.is_empty():
			instance["status"] = "expired"
			world.country_event_registry[raw_id] = instance
		else:
			choose_event_option(world, events, String(raw_id), String((options[0] as Dictionary).get("id", "")), definitions)


static func _event_trigger_passes(world: CampaignWorldState, country_tag: String, trigger: Dictionary) -> bool:
	var runtime := world.country_runtime(country_tag)
	var month_mod := int(trigger.get("month_mod", 0))
	if month_mod > 0 and (world.current_day / 30) % month_mod != 0:
		return false
	if int(runtime.get("religious_unity_bp", BASIS_POINTS)) > int(trigger.get("religious_unity_lte_bp", BASIS_POINTS)):
		return false
	if int(runtime.get("centralisation_bp", 0)) < int(trigger.get("centralisation_gte_bp", 0)):
		return false
	return true


static func _generate_technology_points(world: CampaignWorldState) -> void:
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if world.get_country_provinces(tag).is_empty():
			continue
		var runtime := world.country_runtime(tag)
		var points: Dictionary = runtime.get("technology_points", {})
		var ruler := world.character_registry.get(String(runtime.get("ruler_character_id", "")), {}) as Dictionary
		var skills: Dictionary = ruler.get("skills", {})
		points["administrative"] = int(points.get("administrative", 0)) + 8 + int(skills.get("stewardship", 5))
		points["diplomatic"] = int(points.get("diplomatic", 0)) + 8 + int(skills.get("diplomacy", 5))
		points["military"] = int(points.get("military", 0)) + 8 + int(skills.get("martial", 5))
		runtime["technology_points"] = points
		world.set_country_runtime(tag, runtime)


static func _process_country_month_start(world: CampaignWorldState, definitions: CountryDepthDefinitions) -> void:
	for raw_tag in world.global_flags.get("country_depth_simulated_countries", []):
		var tag := String(raw_tag)
		if not world.has_country(tag) or (world.country_to_provinces.get(tag, []) as Array).is_empty():
			continue
		var runtime := world.country_runtime(tag)
		var previous_modifiers: Array = runtime.get("temporary_modifiers", [])
		var retained: Array = []
		for raw_modifier in previous_modifiers:
			var modifier: Dictionary = raw_modifier
			if int(modifier.get("expires_day", -1)) < 0 or world.current_day <= int(modifier.get("expires_day", -1)):
				retained.append(modifier)
		if retained.size() != previous_modifiers.size():
			runtime["temporary_modifiers"] = retained
			world.set_country_runtime(tag, runtime)
			recalculate_country_modifiers(world, tag, definitions)
			runtime = world.country_runtime(tag)
		if not (world.country_to_provinces.get(tag, []) as Array).is_empty():
			var points: Dictionary = runtime.get("technology_points", {})
			var ruler := world.character_registry.get(String(runtime.get("ruler_character_id", "")), {}) as Dictionary
			var skills: Dictionary = ruler.get("skills", {})
			points["administrative"] = int(points.get("administrative", 0)) + 8 + int(skills.get("stewardship", 5))
			points["diplomatic"] = int(points.get("diplomatic", 0)) + 8 + int(skills.get("diplomacy", 5))
			points["military"] = int(points.get("military", 0)) + 8 + int(skills.get("martial", 5))
			runtime["technology_points"] = points
		world.set_country_runtime(tag, runtime)


static func _expire_modifiers(world: CampaignWorldState, definitions: CountryDepthDefinitions) -> void:
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var retained: Array = []
		for raw_modifier in runtime.get("temporary_modifiers", []):
			var modifier: Dictionary = raw_modifier
			if int(modifier.get("expires_day", -1)) < 0 or world.current_day <= int(modifier.get("expires_day", -1)):
				retained.append(modifier)
		if retained.size() != (runtime.get("temporary_modifiers", []) as Array).size():
			runtime["temporary_modifiers"] = retained
			world.set_country_runtime(tag, runtime)
			recalculate_country_modifiers(world, tag, definitions)


static func _reconcile_country_status(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var previous: Array = world.global_flags.get("country_depth_active_countries", [])
	var current := _current_land_country_tags(world)
	var current_lookup := {}
	for tag in current:
		current_lookup[tag] = true
		if not previous.has(tag):
			var activated_runtime := world.country_runtime(tag)
			activated_runtime["country_status"] = "active"
			world.set_country_runtime(tag, activated_runtime)
	for raw_tag in previous:
		var tag := String(raw_tag)
		if not current_lookup.has(tag):
			var runtime := world.country_runtime(tag)
			if String(runtime.get("country_status", "")) != "active":
				continue
			runtime["country_status"] = "extinct"
			runtime["extinction_day"] = world.current_day
			world.set_country_runtime(tag, runtime)
			for army_id in world.country_armies(tag):
				world.army_registry.erase(army_id)
			for raw_id in world.country_event_registry:
				var event: Dictionary = world.country_event_registry[raw_id]
				if String(event.get("country_tag", "")) == tag and String(event.get("status", "")) == "pending":
					event["status"] = "cancelled"
					world.country_event_registry[raw_id] = event
			_cleanup_extinct_country_references(world, events, tag)
			events.country_extinct.emit(tag)
	world.global_flags["country_depth_active_countries"] = current



static func _replace_country_references(world: CampaignWorldState, old_tag: String, new_tag: String) -> void:
	for raw_id in world.subject_registry:
		var subject: Dictionary = world.subject_registry[raw_id]
		if String(subject.get("overlord", "")) == old_tag:
			subject["overlord"] = new_tag
		if String(subject.get("subject", "")) == old_tag:
			subject["subject"] = new_tag
		world.subject_registry[raw_id] = subject
	for raw_id in world.war_registry:
		var war: Dictionary = world.war_registry[raw_id]
		for field in ["attackers", "defenders"]:
			var participants: Array = war.get(field, [])
			var index := participants.find(old_tag)
			if index >= 0:
				participants[index] = new_tag
			war[field] = participants
		if String(war.get("attacker_leader", "")) == old_tag:
			war["attacker_leader"] = new_tag
		if String(war.get("defender_leader", "")) == old_tag:
			war["defender_leader"] = new_tag
		world.war_registry[raw_id] = war
	var replaced_relations := {}
	for raw_key in world.diplomatic_relations:
		var relation: Dictionary = world.diplomatic_relations[raw_key]
		var countries: Array = relation.get("countries", [])
		var index := countries.find(old_tag)
		if index < 0:
			replaced_relations[raw_key] = relation
			continue
		countries[index] = new_tag
		countries.sort()
		relation["countries"] = countries
		for field in ["opinions", "military_access", "access_requests"]:
			var values: Dictionary = relation.get(field, {})
			if values.has(old_tag):
				values[new_tag] = values[old_tag]
				values.erase(old_tag)
			relation[field] = values
		var subject_data: Dictionary = relation.get("subject", {})
		if String(subject_data.get("overlord", "")) == old_tag:
			subject_data["overlord"] = new_tag
		if String(subject_data.get("subject", "")) == old_tag:
			subject_data["subject"] = new_tag
		relation["subject"] = subject_data
		replaced_relations[DiplomacySystemScript.relation_key(String(countries[0]), String(countries[1]))] = relation
	world.diplomatic_relations = replaced_relations


## Naval counterpart to the army/war cleanup below. `_reconcile_country_status`
## already hard-erases the extinct country's armies directly from
## `army_registry` before calling this function; without an equivalent sweep
## here, any army mid-transport left dangling `transport_operation_registry`
## references to that erased army, and any fleet left in `fleet_registry`
## with a stale `owner_country_id`/battle membership, would make
## `_validate_transport_data`/`_validate_naval_battle_data` reject the very
## next save - not a hygiene nicety, a load-corrupting bug for any extinction
## that catches a country mid-transport or mid-battle at sea.
static func _cleanup_extinct_country_references(world: CampaignWorldState, events: SimulationEventBus, extinct_tag: String) -> void:
	TransportSystemScript.destroy_country_operations(world, events, extinct_tag, "country_extinct")
	var touched_battles := {}
	var fleet_ids := world.country_fleets(extinct_tag)
	for fleet_id in fleet_ids:
		var fleet: Dictionary = world.get_fleet(fleet_id)
		var battle_id := String(fleet.get("battle_id", ""))
		if not battle_id.is_empty() and world.naval_battle_registry.has(battle_id):
			var battle: Dictionary = world.naval_battle_registry[battle_id]
			if String(battle.get("status", "")) == "active":
				var attacker_fleets: Array = battle.get("attacker_fleets", [])
				var defender_fleets: Array = battle.get("defender_fleets", [])
				attacker_fleets.erase(fleet_id)
				defender_fleets.erase(fleet_id)
				battle["attacker_fleets"] = attacker_fleets
				battle["defender_fleets"] = defender_fleets
				world.naval_battle_registry[battle_id] = battle
				touched_battles[battle_id] = true
		var admiral_id := String(fleet.get("admiral_id", ""))
		if not admiral_id.is_empty() and world.character_registry.has(admiral_id):
			var admiral: Dictionary = world.character_registry[admiral_id]
			admiral["admiral_fleet_id"] = ""
			world.character_registry[admiral_id] = admiral
		for ship_id in world.fleet_ships(fleet_id):
			world.ship_registry.erase(ship_id)
		world.fleet_registry.erase(fleet_id)
		events.fleet_destroyed.emit(fleet_id, "country_extinct")
	var battle_ids := touched_battles.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle_id := String(raw_battle_id)
		var battle: Dictionary = world.naval_battle_registry[battle_id]
		var attacker_fleets: Array = battle.get("attacker_fleets", [])
		var defender_fleets: Array = battle.get("defender_fleets", [])
		if not attacker_fleets.is_empty() and not defender_fleets.is_empty():
			continue
		battle["status"] = "completed"
		battle["end_day"] = world.current_day
		battle["winner_side"] = "defender" if attacker_fleets.is_empty() else "attacker"
		world.naval_battle_registry[battle_id] = battle
		events.naval_battle_ended.emit(String(battle.get("war_id", "")), battle_id, String(battle["winner_side"]))
	var construction_ids := world.naval_construction_registry.keys()
	construction_ids.sort()
	for raw_construction_id in construction_ids:
		var construction_id := String(raw_construction_id)
		var construction: Dictionary = world.naval_construction_registry[construction_id]
		if String(construction.get("country_tag", "")) == extinct_tag:
			world.naval_construction_registry.erase(construction_id)
	# Reconcile persisted blockade transitions after the extinct fleets vanish.
	BlockadeSystemScript.process_day(world, events)
	for raw_id in world.subject_registry:
		var subject: Dictionary = world.subject_registry[raw_id]
		if String(subject.get("status", "active")) != "active":
			continue
		if String(subject.get("overlord", "")) == extinct_tag:
			subject["status"] = "released"
			subject["end_day"] = world.current_day
		elif String(subject.get("subject", "")) == extinct_tag:
			subject["status"] = "ended"
			subject["end_day"] = world.current_day
		world.subject_registry[raw_id] = subject
	for raw_id in world.war_registry:
		var war: Dictionary = world.war_registry[raw_id]
		if String(war.get("status", "")) != "active":
			continue
		var attackers: Array = war.get("attackers", [])
		var defenders: Array = war.get("defenders", [])
		attackers.erase(extinct_tag)
		defenders.erase(extinct_tag)
		war["attackers"] = attackers
		war["defenders"] = defenders
		if attackers.is_empty() or defenders.is_empty():
			war["status"] = "ended"
			war["end_day"] = world.current_day
			war["end_reason"] = "country_extinction"
		world.war_registry[raw_id] = war


static func _country_strength(world: CampaignWorldState, country_tag: String) -> int:
	var strength := 0
	for army_id in world.country_armies(country_tag):
		strength += int(world.get_army(army_id).get("strength", 0))
	return strength


static func _merge_modifiers(target: Dictionary, source_variant: Variant) -> void:
	if not source_variant is Dictionary:
		return
	var source: Dictionary = source_variant
	for key in source:
		target[key] = int(target.get(key, 0)) + int(source[key])


static func _current_land_country_tags(world: CampaignWorldState) -> Array[String]:
	var result: Array[String] = []
	for raw_tag in world.country_to_provinces:
		if not (world.country_to_provinces[raw_tag] as Array).is_empty():
			result.append(String(raw_tag))
	result.sort()
	return result


static func mark_province_dynamic(world: CampaignWorldState, province_id: int) -> void:
	if not world.has_province(province_id):
		return
	var dynamic: Array = world.global_flags.get("country_depth_dynamic_provinces", [])
	if not dynamic.has(province_id):
		dynamic.append(province_id)
		dynamic.sort()
		world.global_flags["country_depth_dynamic_provinces"] = dynamic


static func _rebuild_dynamic_province_index(world: CampaignWorldState) -> void:
	var runtime_cache := {}
	var dynamic: Array[int] = []
	var ids := world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var owner := world.get_province_owner(province_id)
		if owner.is_empty() or not world.has_country(owner):
			continue
		if not runtime_cache.has(owner):
			runtime_cache[owner] = world.country_runtime(owner)
		var economy: Dictionary = world.province_states[province_id].get("economy", {})
		if not _is_stable_province(world, owner, province_id, runtime_cache[owner], economy):
			dynamic.append(province_id)
	world.global_flags["country_depth_dynamic_provinces"] = dynamic
