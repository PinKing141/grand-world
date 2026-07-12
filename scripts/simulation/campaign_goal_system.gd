class_name CampaignGoalSystem
extends RefCounted

const STATUS_RUNNING := "running"
const STATUS_VICTORY := "victory"
const STATUS_DEFEAT := "defeat"
const STATUS_COMPLETED := "completed"


static func initialize_world(world: CampaignWorldState, definitions: AIDefinitions) -> void:
	world.global_flags["vertical_slice_id"] = definitions.slice_id()
	world.global_flags["vertical_slice_end_day"] = definitions.end_day()
	world.global_flags["campaign_status"] = STATUS_RUNNING
	world.global_flags["campaign_objectives"] = _objectives(definitions)
	world.global_flags["campaign_summary"] = {}


static func ensure_world(world: CampaignWorldState, definitions: AIDefinitions) -> void:
	if not world.global_flags.has("vertical_slice_id"):
		initialize_world(world, definitions)


static func process_day(world: CampaignWorldState, events: SimulationEventBus, definitions: AIDefinitions) -> void:
	ensure_world(world, definitions)
	if String(world.global_flags.get("campaign_status", STATUS_RUNNING)) != STATUS_RUNNING:
		return
	var player := world.player_country
	if not player.is_empty() and world.has_country(player) and world.get_country_provinces(player).is_empty():
		_finish(world, events, STATUS_DEFEAT, definitions)
		return
	_update_objective_progress(world, definitions)
	if world.current_day >= definitions.end_day():
		var status := STATUS_COMPLETED
		if not player.is_empty():
			status = STATUS_VICTORY if _objective_complete(world, player) else STATUS_DEFEAT
		_finish(world, events, status, definitions)


static func summary(world: CampaignWorldState, definitions: AIDefinitions) -> Dictionary:
	var countries := {}
	for tag in definitions.country_tags():
		if not world.has_country(tag):
			continue
		var runtime := world.country_runtime(tag)
		var armies := world.country_armies(tag)
		var strength := 0
		for army_id in armies:
			strength += int(world.get_army(army_id).get("strength", 0))
		countries[tag] = {
			"provinces": world.get_country_provinces(tag).size(),
			"treasury": int(runtime.get("treasury", 0)),
			"debt": int(runtime.get("debt", 0)),
			"army_strength": strength,
			"objective_complete": _objective_complete(world, tag),
		}
	var completed_wars := 0
	for war in world.war_registry.values():
		if String((war as Dictionary).get("status", "")) == "ended":
			completed_wars += 1
	return {
		"day": world.current_day,
		"status": String(world.global_flags.get("campaign_status", STATUS_RUNNING)),
		"completed_wars": completed_wars,
		"countries": countries,
	}


static func _finish(world: CampaignWorldState, events: SimulationEventBus, status: String, definitions: AIDefinitions) -> void:
	world.global_flags["campaign_status"] = status
	world.global_flags["campaign_summary"] = summary(world, definitions)
	if not world.player_country.is_empty():
		world.paused = true
		events.pause_changed.emit(true)
	events.campaign_status_changed.emit(status, (world.global_flags["campaign_summary"] as Dictionary).duplicate(true))


static func _objectives(definitions: AIDefinitions) -> Dictionary:
	var objectives := {}
	for tag in definitions.country_tags():
		objectives[tag] = {
			"text": String(definitions.profile(tag).get("objective", "Survive the regional campaign.")),
			"complete": false,
		}
	return objectives


static func _update_objective_progress(world: CampaignWorldState, definitions: AIDefinitions) -> void:
	var objectives: Dictionary = world.global_flags.get("campaign_objectives", {})
	for tag in definitions.country_tags():
		if not objectives.has(tag):
			continue
		var record: Dictionary = objectives[tag]
		record["complete"] = _objective_complete(world, tag)
		objectives[tag] = record
	world.global_flags["campaign_objectives"] = objectives


static func _objective_complete(world: CampaignWorldState, tag: String) -> bool:
	if not world.has_country(tag) or world.get_country_provinces(tag).is_empty():
		return false
	match tag:
		"CAS": return world.get_province_owner(223) == "CAS"
		"GRA": return world.get_province_owner(223) == "GRA"
		"POR": return int(world.country_runtime(tag).get("debt", 0)) == 0
		"ARA": return world.get_country_provinces(tag).size() >= 8
		"NAV": return not world.get_country_provinces(tag).is_empty()
	return true
