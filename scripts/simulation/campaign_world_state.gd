class_name CampaignWorldState
extends RefCounted

const DeterministicRng = preload("res://scripts/simulation/deterministic_rng.gd")

const SAVE_SCHEMA_VERSION := 1
const DEFAULT_SCENARIO_ID := "grand_world_1444"

var scenario_id := DEFAULT_SCENARIO_ID
var current_day := 0
var player_country := ""
var paused := true
var game_speed := 1
var campaign_seed := 14441111

var province_states: Dictionary = {}
var country_states: Dictionary = {}
var country_to_provinces: Dictionary = {}
var diplomatic_relations: Dictionary = {}
var army_registry: Dictionary = {}
var war_registry: Dictionary = {}
var global_flags: Dictionary = {}
var global_counters: Dictionary = {}
var rng_stream_states: Dictionary = {}


func initialize(
	province_owners: Dictionary,
	country_names: Dictionary,
	p_scenario_id := DEFAULT_SCENARIO_ID,
	p_campaign_seed := 14441111
) -> void:
	scenario_id = p_scenario_id
	campaign_seed = p_campaign_seed
	current_day = 0
	player_country = ""
	paused = true
	game_speed = 1
	province_states.clear()
	country_states.clear()
	diplomatic_relations.clear()
	army_registry.clear()
	war_registry.clear()
	global_flags.clear()
	global_counters.clear()
	rng_stream_states.clear()

	var country_tags := country_names.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		country_states[tag] = {
			"runtime_values": {},
		}

	var province_ids := province_owners.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var imported_owner := String(province_owners[raw_province_id])
		var owner := imported_owner if country_states.has(imported_owner) else ""
		province_states[province_id] = {
			"owner": owner,
			"controller": owner,
		}
	_rebuild_country_index()


func has_province(province_id: int) -> bool:
	return province_states.has(province_id)


func has_country(country_tag: String) -> bool:
	return country_states.has(country_tag)


func get_province_owner(province_id: int) -> String:
	var state: Dictionary = province_states.get(province_id, {})
	return String(state.get("owner", ""))


func get_province_controller(province_id: int) -> String:
	var state: Dictionary = province_states.get(province_id, {})
	return String(state.get("controller", ""))


func set_province_owner(province_id: int, new_owner: String) -> String:
	var state: Dictionary = province_states[province_id]
	var old_owner := String(state["owner"])
	if old_owner == new_owner:
		return old_owner
	state["owner"] = new_owner
	province_states[province_id] = state
	if not old_owner.is_empty():
		var old_provinces: Array = country_to_provinces.get(old_owner, [])
		old_provinces.erase(province_id)
	if not new_owner.is_empty():
		var new_provinces: Array = country_to_provinces.get(new_owner, [])
		new_provinces.append(province_id)
		new_provinces.sort()
		country_to_provinces[new_owner] = new_provinces
	return old_owner


func get_country_provinces(country_tag: String) -> Array:
	return (country_to_provinces.get(country_tag, []) as Array).duplicate()


func next_random_u32(stream_name: String) -> int:
	var state := int(rng_stream_states.get(stream_name, DeterministicRng.stream_seed(campaign_seed, stream_name)))
	state = DeterministicRng.advance(state)
	rng_stream_states[stream_name] = state
	return state


func checksum() -> String:
	var canonical_parts: Array[String] = [
		"schema=%d" % SAVE_SCHEMA_VERSION,
		"scenario=%s" % scenario_id,
		"day=%d" % current_day,
		"player=%s" % player_country,
		"paused=%s" % str(paused),
		"speed=%d" % game_speed,
		"seed=%d" % campaign_seed,
		"flags=%s" % _canonical_variant(global_flags),
		"counters=%s" % _canonical_variant(global_counters),
		"relations=%s" % _canonical_variant(diplomatic_relations),
		"armies=%s" % _canonical_variant(army_registry),
		"wars=%s" % _canonical_variant(war_registry),
	]
	var stream_names := rng_stream_states.keys()
	stream_names.sort()
	for raw_stream_name in stream_names:
		var stream_name := String(raw_stream_name)
		canonical_parts.append("rng:%s=%d" % [stream_name, int(rng_stream_states[raw_stream_name])])
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var country: Dictionary = country_states[raw_tag]
		canonical_parts.append("country:%s=%s" % [tag, _canonical_variant(country.get("runtime_values", {}))])
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		canonical_parts.append("province:%d=%s/%s" % [province_id, state["owner"], state["controller"]])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update("\n".join(canonical_parts).to_utf8_buffer())
	return hashing.finish().hex_encode()


func to_save_dict(game_version: String) -> Dictionary:
	var owners := {}
	var controllers := {}
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		owners[str(province_id)] = state["owner"]
		controllers[str(province_id)] = state["controller"]
	var runtime_values := {}
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var country: Dictionary = country_states[raw_tag]
		runtime_values[tag] = (country.get("runtime_values", {}) as Dictionary).duplicate(true)
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"game_version": game_version,
		"scenario_id": scenario_id,
		"current_day": current_day,
		"player_country": player_country,
		"paused": paused,
		"game_speed": game_speed,
		"campaign_seed": campaign_seed,
		"rng_stream_states": rng_stream_states.duplicate(true),
		"province_owners": owners,
		"province_controllers": controllers,
		"country_runtime_values": runtime_values,
		"global_flags": global_flags.duplicate(true),
		"global_counters": global_counters.duplicate(true),
		"diplomatic_relations": diplomatic_relations.duplicate(true),
		"army_registry": army_registry.duplicate(true),
		"war_registry": war_registry.duplicate(true),
		"checksum": checksum(),
	}


func apply_save_dict(save_data: Dictionary) -> String:
	if int(save_data.get("schema_version", -1)) != SAVE_SCHEMA_VERSION:
		return "Unsupported save schema version."
	if String(save_data.get("scenario_id", "")) != scenario_id:
		return "The save belongs to a different scenario."
	var loaded_day := int(save_data.get("current_day", -1))
	if loaded_day < 0:
		return "The save contains an invalid campaign day."
	var loaded_speed := int(save_data.get("game_speed", 1))
	if loaded_speed < 1 or loaded_speed > 5:
		return "The save contains an invalid game speed."
	var loaded_player := String(save_data.get("player_country", ""))
	if not loaded_player.is_empty() and not country_states.has(loaded_player):
		return "The saved player country is not present in this scenario."
	var owners_variant = save_data.get("province_owners", null)
	var controllers_variant = save_data.get("province_controllers", null)
	if not owners_variant is Dictionary or not controllers_variant is Dictionary:
		return "The save is missing province state."
	var owners: Dictionary = owners_variant
	var controllers: Dictionary = controllers_variant
	if owners.size() != province_states.size() or controllers.size() != province_states.size():
		return "The save has a different province set."

	var loaded_provinces := {}
	for raw_province_id in province_states.keys():
		var province_id := int(raw_province_id)
		var key := str(province_id)
		if not owners.has(key) or not controllers.has(key):
			return "The save is missing province %d." % province_id
		var owner := String(owners[key])
		var controller := String(controllers[key])
		if not owner.is_empty() and not country_states.has(owner):
			return "Province %d has an unknown owner %s." % [province_id, owner]
		if not controller.is_empty() and not country_states.has(controller):
			return "Province %d has an unknown controller %s." % [province_id, controller]
		loaded_provinces[province_id] = {"owner": owner, "controller": controller}

	var loaded_country_states := country_states.duplicate(true)
	var runtime_values_variant = save_data.get("country_runtime_values", {})
	if not runtime_values_variant is Dictionary:
		return "The save contains invalid country runtime values."
	var runtime_values: Dictionary = runtime_values_variant
	for raw_tag in runtime_values.keys():
		var tag := String(raw_tag)
		if not loaded_country_states.has(tag) or not runtime_values[raw_tag] is Dictionary:
			return "The save contains invalid runtime state for %s." % tag
		loaded_country_states[tag]["runtime_values"] = (runtime_values[raw_tag] as Dictionary).duplicate(true)

	province_states = loaded_provinces
	country_states = loaded_country_states
	current_day = loaded_day
	player_country = loaded_player
	paused = bool(save_data.get("paused", true))
	game_speed = loaded_speed
	campaign_seed = int(save_data.get("campaign_seed", campaign_seed))
	rng_stream_states = (save_data.get("rng_stream_states", {}) as Dictionary).duplicate(true)
	global_flags = (save_data.get("global_flags", {}) as Dictionary).duplicate(true)
	global_counters = (save_data.get("global_counters", {}) as Dictionary).duplicate(true)
	diplomatic_relations = (save_data.get("diplomatic_relations", {}) as Dictionary).duplicate(true)
	army_registry = (save_data.get("army_registry", {}) as Dictionary).duplicate(true)
	war_registry = (save_data.get("war_registry", {}) as Dictionary).duplicate(true)
	_rebuild_country_index()
	return ""


func _rebuild_country_index() -> void:
	country_to_provinces.clear()
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		country_to_provinces[String(raw_tag)] = []
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var owner := get_province_owner(province_id)
		if owner.is_empty() or not country_to_provinces.has(owner):
			continue
		(country_to_provinces[owner] as Array).append(province_id)


func _canonical_variant(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var keys := dictionary.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [str(key), _canonical_variant(dictionary[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_canonical_variant(item))
		return "[%s]" % ",".join(parts)
	return str(value)
