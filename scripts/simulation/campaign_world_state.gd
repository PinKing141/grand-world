class_name CampaignWorldState
extends RefCounted

const DeterministicRng = preload("res://scripts/simulation/deterministic_rng.gd")

const SAVE_SCHEMA_VERSION := 4
const DEFAULT_SCENARIO_ID := "grand_world_1444"

const ARMY_STATUS_IDLE := "idle"
const ARMY_STATUS_MOVING := "moving"
const ARMY_STATUS_BLOCKED := "blocked"
const ARMY_STATUS_BATTLE := "battle"
const ARMY_STATUS_RETREATING := "retreating"
const ARMY_STATUS_RECOVERING := "recovering"

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
var construction_registry: Dictionary = {}
var recruitment_registry: Dictionary = {}
var loan_registry: Dictionary = {}
var character_registry: Dictionary = {}
var dynasty_registry: Dictionary = {}
var title_registry: Dictionary = {}
var claim_registry: Dictionary = {}
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
	construction_registry.clear()
	recruitment_registry.clear()
	loan_registry.clear()
	character_registry.clear()
	dynasty_registry.clear()
	title_registry.clear()
	claim_registry.clear()
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
	_create_default_armies()


func _create_default_armies() -> void:
	# Phase 3 test setup: every country with territory fields one army at its
	# lowest-ID province. Deterministic: sorted tags, sorted province lists.
	army_registry.clear()
	var country_tags := country_to_provinces.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var provinces: Array = country_to_provinces[raw_tag]
		if provinces.is_empty():
			continue
		var army_id := "a_%s" % tag
		army_registry[army_id] = make_army_record(army_id, tag, int(provinces[0]))


static func make_army_record(army_id: String, owner_tag: String, province_id: int) -> Dictionary:
	return {
		"army_id": army_id,
		"owner_country_id": owner_tag,
		"current_province_id": province_id,
		"destination_province_id": -1,
		"remaining_path": [],
		"path_index": 0,
		"movement_start_day": -1,
		"next_arrival_day": -1,
		"movement_progress": 0.0,
		"movement_locked": false,
		"status": ARMY_STATUS_IDLE,
		"unit_id": "infantry_regiment",
		"regiment_count": 1,
		"strength": 1000,
		"maximum_strength": 1000,
		"morale_bp": 10000,
		"maximum_morale_bp": 10000,
		"attack": 100,
		"defence": 100,
		"commander_id": "",
		"battle_id": "",
		"retreating": false,
		"recovery_until_day": -1,
		"base_monthly_maintenance": 500,
	}


func get_army(army_id: String) -> Dictionary:
	return army_registry.get(army_id, {})


func armies_in_province(province_id: int) -> Array[String]:
	var found: Array[String] = []
	var army_ids := army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = army_registry[raw_army_id]
		if int(army.get("current_province_id", -1)) == province_id:
			found.append(String(raw_army_id))
	return found


func country_armies(country_tag: String) -> Array[String]:
	var found: Array[String] = []
	var army_ids := army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = army_registry[raw_army_id]
		if String(army.get("owner_country_id", "")) == country_tag:
			found.append(String(raw_army_id))
	return found


static func migrate_save_data(save_data: Dictionary) -> Dictionary:
	var migrated := save_data.duplicate(true)
	var schema := int(migrated.get("schema_version", -1))
	if schema == 1:
		# Phase 2 predates armies. Recreate one deterministic test army for
		# each country represented in the saved ownership.
		var owners: Dictionary = migrated.get("province_owners", {})
		var first_province := {}
		var province_keys := owners.keys()
		province_keys.sort_custom(func(a, b): return int(a) < int(b))
		for key in province_keys:
			var owner := String(owners[key])
			if owner.is_empty() or first_province.has(owner):
				continue
			first_province[owner] = int(key)
		var armies := {}
		var tags := first_province.keys()
		tags.sort()
		for raw_tag in tags:
			var tag := String(raw_tag)
			var army_id := "a_%s" % tag
			armies[army_id] = make_army_record(army_id, tag, int(first_province[raw_tag]))
		migrated["army_registry"] = armies
		schema = 2
	if schema == 2:
		# Phase 4 economy values merge onto the scenario defaults already
		# present in the target world during apply_save_dict.
		migrated["province_economy"] = {}
		migrated["construction_registry"] = {}
		migrated["recruitment_registry"] = {}
		migrated["loan_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 2))
		schema = 3
	if schema == 3:
		# Phase 7 character data is restored from scenario defaults when an old
		# campaign is loaded. New registries remain explicit in schema 4 saves.
		migrated["character_registry"] = {}
		migrated["dynasty_registry"] = {}
		migrated["title_registry"] = {}
		migrated["claim_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 3))
	if schema < 1 or schema > SAVE_SCHEMA_VERSION:
		return save_data
	migrated["schema_version"] = SAVE_SCHEMA_VERSION
	return migrated


func country_runtime(country_tag: String) -> Dictionary:
	var country: Dictionary = country_states.get(country_tag, {})
	return (country.get("runtime_values", {}) as Dictionary).duplicate(true)


func set_country_runtime(country_tag: String, runtime: Dictionary) -> void:
	var country: Dictionary = country_states[country_tag]
	country["runtime_values"] = runtime
	country_states[country_tag] = country


func take_counter(counter_name: String) -> int:
	var current := int(global_counters.get(counter_name, 1))
	global_counters[counter_name] = current + 1
	return current


func has_province(province_id: int) -> bool:
	return province_states.has(province_id)


func has_country(country_tag: String) -> bool:
	return country_states.has(country_tag)


func has_character(character_id: String) -> bool:
	return character_registry.has(character_id)


func get_character(character_id: String) -> Dictionary:
	return (character_registry.get(character_id, {}) as Dictionary).duplicate(true)


func set_character(character_id: String, record: Dictionary) -> void:
	character_registry[character_id] = record.duplicate(true)


func living_characters_in_country(country_tag: String) -> Array[String]:
	var result: Array[String] = []
	var ids := character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = character_registry[raw_id]
		if bool(record.get("alive", false)) and String(record.get("employer_country", "")) == country_tag:
			result.append(String(raw_id))
	return result


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


func set_province_controller(province_id: int, new_controller: String) -> String:
	var state: Dictionary = province_states[province_id]
	var old_controller := String(state.get("controller", ""))
	state["controller"] = new_controller
	province_states[province_id] = state
	return old_controller


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
		"construction=%s" % _canonical_variant(construction_registry),
		"recruitment=%s" % _canonical_variant(recruitment_registry),
		"loans=%s" % _canonical_variant(loan_registry),
		"characters=%s" % _canonical_variant(character_registry),
		"dynasties=%s" % _canonical_variant(dynasty_registry),
		"titles=%s" % _canonical_variant(title_registry),
		"claims=%s" % _canonical_variant(claim_registry),
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
		canonical_parts.append("province:%d=%s" % [province_id, _canonical_variant(state)])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update("\n".join(canonical_parts).to_utf8_buffer())
	return hashing.finish().hex_encode()


func to_save_dict(game_version: String) -> Dictionary:
	var owners := {}
	var controllers := {}
	var province_economy := {}
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		owners[str(province_id)] = state["owner"]
		controllers[str(province_id)] = state["controller"]
		province_economy[str(province_id)] = (state.get("economy", {}) as Dictionary).duplicate(true)
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
		"province_economy": province_economy,
		"country_runtime_values": runtime_values,
		"global_flags": global_flags.duplicate(true),
		"global_counters": global_counters.duplicate(true),
		"diplomatic_relations": diplomatic_relations.duplicate(true),
		"army_registry": army_registry.duplicate(true),
		"war_registry": war_registry.duplicate(true),
		"construction_registry": construction_registry.duplicate(true),
		"recruitment_registry": recruitment_registry.duplicate(true),
		"loan_registry": loan_registry.duplicate(true),
		"character_registry": character_registry.duplicate(true),
		"dynasty_registry": dynasty_registry.duplicate(true),
		"title_registry": title_registry.duplicate(true),
		"claim_registry": claim_registry.duplicate(true),
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
	var province_economy_variant = save_data.get("province_economy", {})
	if not province_economy_variant is Dictionary:
		return "The save contains invalid province economy state."
	var province_economy: Dictionary = province_economy_variant
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
		var existing_state: Dictionary = province_states[province_id]
		var economy := (existing_state.get("economy", {}) as Dictionary).duplicate(true)
		if province_economy.has(key):
			if not province_economy[key] is Dictionary:
				return "Province %d has invalid economy state." % province_id
			economy.merge((province_economy[key] as Dictionary).duplicate(true), true)
		var loaded_state := {"owner": owner, "controller": controller}
		if existing_state.has("economy") or not economy.is_empty():
			loaded_state["economy"] = economy
		loaded_provinces[province_id] = loaded_state

	var armies_variant = save_data.get("army_registry", {})
	if not armies_variant is Dictionary:
		return "The save contains an invalid army registry."
	var loaded_armies: Dictionary = armies_variant
	for raw_army_id in loaded_armies.keys():
		if not loaded_armies[raw_army_id] is Dictionary:
			return "Army %s has invalid state." % raw_army_id
		var army: Dictionary = loaded_armies[raw_army_id]
		var army_owner := String(army.get("owner_country_id", ""))
		if not army_owner.is_empty() and not country_states.has(army_owner):
			return "Army %s belongs to unknown country %s." % [raw_army_id, army_owner]
		var army_province := int(army.get("current_province_id", -1))
		if not province_states.has(army_province):
			return "Army %s sits in unknown province %d." % [raw_army_id, army_province]

	var loaded_country_states := country_states.duplicate(true)
	var runtime_values_variant = save_data.get("country_runtime_values", {})
	if not runtime_values_variant is Dictionary:
		return "The save contains invalid country runtime values."
	var runtime_values: Dictionary = runtime_values_variant
	for raw_tag in runtime_values.keys():
		var tag := String(raw_tag)
		if not loaded_country_states.has(tag) or not runtime_values[raw_tag] is Dictionary:
			return "The save contains invalid runtime state for %s." % tag
		var merged_runtime := (loaded_country_states[tag].get("runtime_values", {}) as Dictionary).duplicate(true)
		merged_runtime.merge((runtime_values[raw_tag] as Dictionary).duplicate(true), true)
		loaded_country_states[tag]["runtime_values"] = merged_runtime

	for registry_key in ["construction_registry", "recruitment_registry", "loan_registry", "diplomatic_relations", "war_registry"]:
		if not save_data.get(registry_key, {}) is Dictionary:
			return "The save contains an invalid %s." % registry_key.replace("_", " ")
	var loaded_relations: Dictionary = save_data.get("diplomatic_relations", {})
	for raw_relation_key in loaded_relations:
		if not loaded_relations[raw_relation_key] is Dictionary:
			return "Diplomatic relationship %s has invalid state." % raw_relation_key
		var relation_countries: Array = loaded_relations[raw_relation_key].get("countries", [])
		if relation_countries.size() != 2:
			return "Diplomatic relationship %s has invalid participants." % raw_relation_key
		for raw_country in relation_countries:
			if not country_states.has(String(raw_country)):
				return "Diplomatic relationship %s references an unknown country." % raw_relation_key
	var loaded_wars: Dictionary = save_data.get("war_registry", {})
	for raw_war_id in loaded_wars:
		if not loaded_wars[raw_war_id] is Dictionary:
			return "War %s has invalid state." % raw_war_id
		var war: Dictionary = loaded_wars[raw_war_id]
		if String(war.get("status", "")) not in ["active", "ended"]:
			return "War %s has an invalid status." % raw_war_id
		var participants: Array = (war.get("attackers", []) as Array) + (war.get("defenders", []) as Array)
		if participants.size() < 2:
			return "War %s is missing participants." % raw_war_id
		var seen_participants := {}
		for raw_country in participants:
			var country := String(raw_country)
			if not country_states.has(country) or seen_participants.has(country):
				return "War %s has an unknown or duplicated participant." % raw_war_id
			seen_participants[country] = true
		var goal = war.get("war_goal", null)
		if not goal is Dictionary or not province_states.has(int((goal as Dictionary).get("province_id", -1))):
			return "War %s has an invalid war goal." % raw_war_id
		if String((goal as Dictionary).get("type", "")) == "press_claim":
			var goal_claim := String((goal as Dictionary).get("claim_id", ""))
			var goal_title := String((goal as Dictionary).get("title_id", ""))
			var goal_claimant := String((goal as Dictionary).get("claimant_id", ""))
			var save_claims = save_data.get("claim_registry", {})
			var save_titles = save_data.get("title_registry", {})
			var save_characters = save_data.get("character_registry", {})
			if not save_claims is Dictionary or not (save_claims as Dictionary).has(goal_claim) or not save_titles is Dictionary or not (save_titles as Dictionary).has(goal_title) or not save_characters is Dictionary or not (save_characters as Dictionary).has(goal_claimant):
				return "War %s has an invalid character claim war goal." % raw_war_id
		if not war.get("battles", {}) is Dictionary or not war.get("occupied_provinces", {}) is Dictionary or not war.get("peace_offers", {}) is Dictionary:
			return "War %s contains an invalid conflict registry." % raw_war_id
		for battle in (war.get("battles", {}) as Dictionary).values():
			if not battle is Dictionary or not province_states.has(int((battle as Dictionary).get("province_id", -1))):
				return "War %s contains an invalid battle." % raw_war_id
		for raw_province in (war.get("occupied_provinces", {}) as Dictionary):
			if not province_states.has(int(raw_province)):
				return "War %s contains an invalid occupation." % raw_war_id

	var loaded_characters_variant = save_data.get("character_registry", {})
	var loaded_dynasties_variant = save_data.get("dynasty_registry", {})
	var loaded_titles_variant = save_data.get("title_registry", {})
	var loaded_claims_variant = save_data.get("claim_registry", {})
	if not loaded_characters_variant is Dictionary or not loaded_dynasties_variant is Dictionary or not loaded_titles_variant is Dictionary or not loaded_claims_variant is Dictionary:
		return "The save contains invalid Phase 7 registries."
	var loaded_characters: Dictionary = loaded_characters_variant
	var loaded_dynasties: Dictionary = loaded_dynasties_variant
	var loaded_titles: Dictionary = loaded_titles_variant
	var loaded_claims: Dictionary = loaded_claims_variant
	if int(save_data.get("migrated_from_schema", SAVE_SCHEMA_VERSION)) < 4 and loaded_characters.is_empty():
		loaded_characters = character_registry.duplicate(true)
		loaded_dynasties = dynasty_registry.duplicate(true)
		loaded_titles = title_registry.duplicate(true)
		loaded_claims = claim_registry.duplicate(true)
	var character_error := _validate_character_data(loaded_characters, loaded_dynasties, loaded_titles, loaded_claims, loaded_country_states, loaded_armies)
	if not character_error.is_empty():
		return character_error

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
	construction_registry = (save_data.get("construction_registry", {}) as Dictionary).duplicate(true)
	recruitment_registry = (save_data.get("recruitment_registry", {}) as Dictionary).duplicate(true)
	loan_registry = (save_data.get("loan_registry", {}) as Dictionary).duplicate(true)
	character_registry = loaded_characters.duplicate(true)
	dynasty_registry = loaded_dynasties.duplicate(true)
	title_registry = loaded_titles.duplicate(true)
	claim_registry = loaded_claims.duplicate(true)
	_rebuild_country_index()
	return ""


func _validate_character_data(
	characters: Dictionary,
	dynasties: Dictionary,
	titles: Dictionary,
	claims: Dictionary,
	loaded_countries: Dictionary,
	loaded_armies: Dictionary
) -> String:
	for raw_id in characters:
		var character_id := String(raw_id)
		if not characters[raw_id] is Dictionary:
			return "Character %s has invalid state." % character_id
		var character: Dictionary = characters[raw_id]
		if String(character.get("character_id", character_id)) != character_id:
			return "Character %s has a mismatched stable ID." % character_id
		if not character.get("birth", {}) is Dictionary or not character.get("skills", {}) is Dictionary or not character.get("traits", []) is Array:
			return "Character %s has malformed core data." % character_id
		if not dynasties.has(String(character.get("dynasty_id", ""))):
			return "Character %s references an unknown dynasty." % character_id
		for field in ["father_id", "mother_id", "spouse_id"]:
			var reference := String(character.get(field, ""))
			if reference == character_id or (not reference.is_empty() and not characters.has(reference)):
				return "Character %s has an invalid %s reference." % [character_id, field]
		for raw_child in character.get("children", []):
			var child_id := String(raw_child)
			if not characters.has(child_id):
				return "Character %s references an unknown child." % character_id
			var child: Dictionary = characters[child_id]
			if String(child.get("father_id", "")) != character_id and String(child.get("mother_id", "")) != character_id:
				return "Character %s has a non-reciprocal child reference." % character_id
		var spouse := String(character.get("spouse_id", ""))
		if not spouse.is_empty() and String((characters[spouse] as Dictionary).get("spouse_id", "")) != character_id:
			return "Marriage references are not symmetric for %s." % character_id
		var employer := String(character.get("employer_country", ""))
		if not employer.is_empty() and not loaded_countries.has(employer):
			return "Character %s has an unknown employer." % character_id
	if _has_character_ancestry_cycle(characters):
		return "The saved character ancestry contains a cycle."
	for raw_id in dynasties:
		if not dynasties[raw_id] is Dictionary:
			return "Dynasty %s has invalid state." % String(raw_id)
		for raw_member in (dynasties[raw_id] as Dictionary).get("living_members", []):
			if not characters.has(String(raw_member)) or not bool((characters[String(raw_member)] as Dictionary).get("alive", false)):
				return "Dynasty %s has an invalid living member." % String(raw_id)
	for raw_id in titles:
		if not titles[raw_id] is Dictionary:
			return "Title %s has invalid state." % String(raw_id)
		var title: Dictionary = titles[raw_id]
		var holder := String(title.get("holder_id", ""))
		if not characters.has(holder) or not bool((characters[holder] as Dictionary).get("alive", false)):
			return "Title %s has no valid living holder." % String(raw_id)
		var country := String(title.get("country_tag", ""))
		if not country.is_empty() and not loaded_countries.has(country):
			return "Title %s references an unknown country." % String(raw_id)
		var liege := String(title.get("liege_title_id", ""))
		if not liege.is_empty() and not titles.has(liege):
			return "Title %s references an unknown liege." % String(raw_id)
	if _has_title_hierarchy_cycle(titles):
		return "The saved title hierarchy contains a cycle."
	for raw_id in claims:
		if not claims[raw_id] is Dictionary:
			return "Claim %s has invalid state." % String(raw_id)
		var claim: Dictionary = claims[raw_id]
		if not characters.has(String(claim.get("claimant_id", ""))) or not titles.has(String(claim.get("title_id", ""))):
			return "Claim %s has an invalid character or title reference." % String(raw_id)
	for raw_tag in loaded_countries:
		var runtime: Dictionary = (loaded_countries[raw_tag] as Dictionary).get("runtime_values", {})
		for field in ["ruler_character_id", "heir_character_id"]:
			var character_id := String(runtime.get(field, ""))
			if not character_id.is_empty() and (not characters.has(character_id) or not bool((characters[character_id] as Dictionary).get("alive", false))):
				return "Country %s has an invalid %s." % [String(raw_tag), field]
		var primary_title := String(runtime.get("primary_title_id", ""))
		if not primary_title.is_empty() and not titles.has(primary_title):
			return "Country %s has an invalid primary title." % String(raw_tag)
	for raw_army_id in loaded_armies:
		var commander := String((loaded_armies[raw_army_id] as Dictionary).get("commander_id", ""))
		if not commander.is_empty() and (not characters.has(commander) or not bool((characters[commander] as Dictionary).get("alive", false))):
			return "Army %s has an invalid commander." % String(raw_army_id)
	return ""


func _has_character_ancestry_cycle(characters: Dictionary) -> bool:
	var fully_visited := {}
	var ids := characters.keys()
	ids.sort()
	for raw_id in ids:
		if _visit_character_ancestry(String(raw_id), characters, {}, fully_visited):
			return true
	return false


func _visit_character_ancestry(character_id: String, characters: Dictionary, visiting: Dictionary, fully_visited: Dictionary) -> bool:
	if visiting.has(character_id):
		return true
	if fully_visited.has(character_id):
		return false
	visiting[character_id] = true
	var character: Dictionary = characters[character_id]
	for field in ["father_id", "mother_id"]:
		var parent := String(character.get(field, ""))
		if not parent.is_empty() and _visit_character_ancestry(parent, characters, visiting, fully_visited):
			return true
	visiting.erase(character_id)
	fully_visited[character_id] = true
	return false


func _has_title_hierarchy_cycle(titles: Dictionary) -> bool:
	for raw_id in titles:
		var current := String(raw_id)
		var seen := {}
		while not current.is_empty():
			if seen.has(current):
				return true
			seen[current] = true
			current = String((titles[current] as Dictionary).get("liege_title_id", ""))
	return false


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
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)
