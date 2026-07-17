class_name CharacterSystem
extends RefCounted

const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

const BASIS_POINTS := 10000
const ADULT_AGE := 16
const MAX_CHILDREN := 8
const BIRTH_COOLDOWN_DAYS := 300
const SHORT_REIGN_DAYS := 1826
const VALID_TRAITS := ["ambitious", "brave", "cautious", "diligent", "just", "lazy", "patient", "scholar", "zealous"]


static func initialize_world(world: CampaignWorldState, definitions: CharacterDefinitions) -> void:
	world.character_registry.clear()
	world.dynasty_registry.clear()
	world.title_registry.clear()
	world.claim_registry.clear()
	var source_characters := definitions.characters()
	var character_ids := source_characters.keys()
	character_ids.sort()
	for raw_id in character_ids:
		var character_id := String(raw_id)
		var record: Dictionary = source_characters[raw_id]
		record.merge({
			"character_id": character_id, "alive": true, "death_day": -1,
			"death_cause": "", "father_id": "", "mother_id": "", "spouse_id": "",
			"former_spouses": [], "children": [], "titles": [], "claims": [],
			"health_bp": 8000, "fertility_bp": 5000, "stress_bp": 0,
			"event_cooldowns": {}, "last_birth_day": -9999, "commander_army_id": "", "admiral_fleet_id": "",
			"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
		}, false)
		var traits: Array = record.get("traits", [])
		traits.sort()
		record["traits"] = traits
		world.character_registry[character_id] = record
	var source_dynasties := definitions.dynasties()
	var dynasty_ids := source_dynasties.keys()
	for raw_id in dynasty_ids:
		var dynasty_id := String(raw_id)
		var record: Dictionary = source_dynasties[raw_id]
		record["dynasty_id"] = dynasty_id
		record["living_members"] = []
		record["player_dynasty"] = false
		world.dynasty_registry[dynasty_id] = record
	var source_titles := definitions.titles()
	var title_ids := source_titles.keys()
	title_ids.sort()
	for raw_id in title_ids:
		var title_id := String(raw_id)
		var record: Dictionary = source_titles[raw_id]
		record.merge({"title_id": title_id, "liege_title_id": "", "de_jure_parent_id": "", "de_jure_vassal_ids": [], "claims": []}, false)
		world.title_registry[title_id] = record
		var holder_id := String(record.get("holder_id", ""))
		if world.character_registry.has(holder_id):
			var holder: Dictionary = world.character_registry[holder_id]
			var held_titles: Array = holder.get("titles", [])
			held_titles.append(title_id)
			held_titles.sort()
			holder["titles"] = held_titles
			world.character_registry[holder_id] = holder
	var source_claims := definitions.claims()
	var claim_ids := source_claims.keys()
	claim_ids.sort()
	for raw_id in claim_ids:
		var claim_id := String(raw_id)
		var record: Dictionary = source_claims[raw_id]
		record.merge({"claim_id": claim_id, "created_day": world.current_day, "expires_day": -1, "pressed": false}, false)
		world.claim_registry[claim_id] = record
		_link_claim(world, claim_id, record)
	_rebuild_dynasty_indexes(world)
	var assignments := definitions.country_rulers()
	var tags := assignments.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if not world.has_country(tag):
			continue
		var assignment: Dictionary = assignments[raw_tag]
		var runtime := world.country_runtime(tag)
		runtime["ruler_character_id"] = String(assignment.get("ruler_id", ""))
		runtime["heir_character_id"] = String(assignment.get("heir_id", ""))
		runtime["primary_title_id"] = String(assignment.get("primary_title_id", ""))
		runtime["legitimacy_bp"] = 8000
		runtime["reign_start_day"] = world.current_day
		runtime["short_reign_until_day"] = -1
		runtime["personal_union_senior"] = ""
		runtime["offices"] = {"advisors": [], "commanders": []}
		world.set_country_runtime(tag, runtime)
		recalculate_ruler_modifiers(world, tag)
	world.global_flags["character_system_version"] = 1
	world.global_flags["character_slice_enabled"] = true
	world.global_counters["next_generated_character_id"] = maxi(int(world.global_counters.get("next_generated_character_id", 1)), 1)


static func ensure_world(world: CampaignWorldState, definitions: CharacterDefinitions) -> void:
	if world.character_registry.is_empty() or int(world.global_flags.get("character_system_version", 0)) != 1:
		initialize_world(world, definitions)


static func age_years(world: CampaignWorldState, character_id: String) -> int:
	if not world.character_registry.has(character_id):
		return -1
	var character: Dictionary = world.character_registry[character_id]
	var birth: Dictionary = character.get("birth", {})
	var current := SimulationDateScript.day_to_date(int(character.get("death_day", world.current_day)) if not bool(character.get("alive", true)) else world.current_day)
	var age := int(current["year"]) - int(birth.get("year", current["year"]))
	if int(current["month"]) < int(birth.get("month", 1)) or (int(current["month"]) == int(birth.get("month", 1)) and int(current["day"]) < int(birth.get("day", 1))):
		age -= 1
	return maxi(age, 0)


static func ruler_id(world: CampaignWorldState, country_tag: String) -> String:
	return String(world.country_runtime(country_tag).get("ruler_character_id", "")) if world.has_country(country_tag) else ""


static func heir_id(world: CampaignWorldState, country_tag: String) -> String:
	return String(world.country_runtime(country_tag).get("heir_character_id", "")) if world.has_country(country_tag) else ""


static func family(world: CampaignWorldState, character_id: String) -> Dictionary:
	if not world.character_registry.has(character_id):
		return {}
	var character: Dictionary = world.character_registry[character_id]
	return {
		"father_id": String(character.get("father_id", "")),
		"mother_id": String(character.get("mother_id", "")),
		"spouse_id": String(character.get("spouse_id", "")),
		"former_spouses": (character.get("former_spouses", []) as Array).duplicate(),
		"children": (character.get("children", []) as Array).duplicate(),
	}


static func can_marry(world: CampaignWorldState, first_id: String, second_id: String) -> String:
	if first_id == second_id or not world.character_registry.has(first_id) or not world.character_registry.has(second_id):
		return "A marriage requires two different existing characters."
	var first: Dictionary = world.character_registry[first_id]
	var second: Dictionary = world.character_registry[second_id]
	if not bool(first.get("alive", false)) or not bool(second.get("alive", false)):
		return "Dead characters cannot marry."
	if age_years(world, first_id) < ADULT_AGE or age_years(world, second_id) < ADULT_AGE:
		return "Both characters must be at least %d." % ADULT_AGE
	if not String(first.get("spouse_id", "")).is_empty() or not String(second.get("spouse_id", "")).is_empty():
		return "One of these characters is already married."
	if String(first.get("sex", "")) == String(second.get("sex", "")):
		return "The initial dynastic marriage model requires opposite-sex partners."
	if _close_family(first, second, first_id, second_id):
		return "Close relatives cannot marry."
	return ""


static func arrange_marriage(world: CampaignWorldState, events: SimulationEventBus, first_id: String, second_id: String) -> void:
	var first: Dictionary = world.character_registry[first_id]
	var second: Dictionary = world.character_registry[second_id]
	first["spouse_id"] = second_id
	second["spouse_id"] = first_id
	world.character_registry[first_id] = first
	world.character_registry[second_id] = second
	var first_country := String(first.get("employer_country", ""))
	var second_country := String(second.get("employer_country", ""))
	if not first_country.is_empty() and not second_country.is_empty() and first_country != second_country:
		var relation := DiplomacySystemScript.relation(world, first_country, second_country)
		var opinions: Dictionary = relation.get("opinions", {})
		opinions[first_country] = clampi(int(opinions.get(first_country, 0)) + 10, -200, 200)
		opinions[second_country] = clampi(int(opinions.get(second_country, 0)) + 10, -200, 200)
		relation["opinions"] = opinions
		relation["marriage_ties"] = int(relation.get("marriage_ties", 0)) + 1
		DiplomacySystemScript.set_relation(world, first_country, second_country, relation)
	events.character_married.emit(first_id, second_id)
	_record_character_event(world, "marriage", {"first_id": first_id, "second_id": second_id})


static func valid_commanders(world: CampaignWorldState, country_tag: String) -> Array[String]:
	var candidates: Array[String] = []
	for character_id in world.living_characters_in_country(country_tag):
		if age_years(world, character_id) >= ADULT_AGE:
			candidates.append(character_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var martial_a := int(((world.character_registry[a] as Dictionary).get("skills", {}) as Dictionary).get("martial", 0))
		var martial_b := int(((world.character_registry[b] as Dictionary).get("skills", {}) as Dictionary).get("martial", 0))
		return martial_a > martial_b if martial_a != martial_b else a < b)
	return candidates


static func assign_commander(world: CampaignWorldState, events: SimulationEventBus, army_id: String, character_id: String) -> void:
	var army: Dictionary = world.army_registry[army_id]
	var previous := String(army.get("commander_id", ""))
	if not previous.is_empty() and world.character_registry.has(previous):
		var old_character: Dictionary = world.character_registry[previous]
		old_character["commander_army_id"] = ""
		world.character_registry[previous] = old_character
	army["commander_id"] = character_id
	world.army_registry[army_id] = army
	var character: Dictionary = world.character_registry[character_id]
	character["commander_army_id"] = army_id
	world.character_registry[character_id] = character
	events.commander_assigned.emit(army_id, character_id)


## Mirrors assign_commander exactly, for fleets instead of armies. A
## character cannot command an army and a fleet at once (00_SCOPE /
## 02_N2_FLEET_LOGISTICS "Admirals"); AssignAdmiralCommand.validate() is what
## enforces that exclusivity, this function only performs the atomic swap.
static func assign_admiral(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String, character_id: String) -> void:
	var fleet: Dictionary = world.fleet_registry[fleet_id]
	var previous := String(fleet.get("admiral_id", ""))
	if not previous.is_empty() and world.character_registry.has(previous):
		var old_character: Dictionary = world.character_registry[previous]
		old_character["admiral_fleet_id"] = ""
		world.character_registry[previous] = old_character
	fleet["admiral_id"] = character_id
	world.fleet_registry[fleet_id] = fleet
	var character: Dictionary = world.character_registry[character_id]
	character["admiral_fleet_id"] = fleet_id
	world.character_registry[character_id] = character
	events.admiral_assigned.emit(fleet_id, character_id)


static func grant_title(world: CampaignWorldState, events: SimulationEventBus, title_id: String, new_holder_id: String) -> void:
	var title: Dictionary = world.title_registry[title_id]
	var old_holder := String(title.get("holder_id", ""))
	if world.character_registry.has(old_holder):
		var old_record: Dictionary = world.character_registry[old_holder]
		var old_titles: Array = old_record.get("titles", [])
		old_titles.erase(title_id)
		old_record["titles"] = old_titles
		world.character_registry[old_holder] = old_record
	var new_record: Dictionary = world.character_registry[new_holder_id]
	if not old_holder.is_empty() and old_holder != new_holder_id and world.character_registry.has(old_holder) and bool((world.character_registry[old_holder] as Dictionary).get("alive", false)):
		var opinion_modifiers: Array = new_record.get("opinion_modifiers", [])
		opinion_modifiers.append({"target_id": old_holder, "label": "Granted a title", "value": 20, "expires_day": world.current_day + 3650})
		new_record["opinion_modifiers"] = opinion_modifiers
	var new_titles: Array = new_record.get("titles", [])
	if not new_titles.has(title_id):
		new_titles.append(title_id)
		new_titles.sort()
	new_record["titles"] = new_titles
	world.character_registry[new_holder_id] = new_record
	title["holder_id"] = new_holder_id
	world.title_registry[title_id] = title
	events.title_holder_changed.emit(title_id, old_holder, new_holder_id)


static func process_month(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ids := world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var character_id := String(raw_id)
		if not world.character_registry.has(character_id):
			continue
		var character: Dictionary = world.character_registry[character_id]
		if not bool(character.get("alive", false)):
			continue
		_process_coming_of_age(world, events, character_id, character)
		character = world.character_registry[character_id]
		_process_health_events(world, events, character_id, character)
		character = world.character_registry[character_id]
		if _monthly_death_roll(world, character_id, character):
			kill_character(world, events, character_id, "natural causes")
	_process_births(world, events)
	if world.current_day % 365 < 31:
		_ensure_court_demographics(world, events)
	_refresh_all_heirs(world)


static func kill_character(world: CampaignWorldState, events: SimulationEventBus, character_id: String, cause := "scripted") -> String:
	if not world.character_registry.has(character_id):
		return "The character does not exist."
	var character: Dictionary = world.character_registry[character_id]
	if not bool(character.get("alive", false)):
		return "The character is already dead."
	character["alive"] = false
	character["death_day"] = world.current_day
	character["death_cause"] = cause
	var spouse_id := String(character.get("spouse_id", ""))
	if not spouse_id.is_empty() and world.character_registry.has(spouse_id):
		var spouse: Dictionary = world.character_registry[spouse_id]
		var spouse_former: Array = spouse.get("former_spouses", [])
		if not spouse_former.has(character_id):
			spouse_former.append(character_id)
		spouse["former_spouses"] = spouse_former
		spouse["spouse_id"] = ""
		world.character_registry[spouse_id] = spouse
		var former: Array = character.get("former_spouses", [])
		if not former.has(spouse_id):
			former.append(spouse_id)
		character["former_spouses"] = former
		character["spouse_id"] = ""
	var commander_army := String(character.get("commander_army_id", ""))
	if world.army_registry.has(commander_army):
		var army: Dictionary = world.army_registry[commander_army]
		army["commander_id"] = ""
		world.army_registry[commander_army] = army
	character["commander_army_id"] = ""
	var admiral_fleet := String(character.get("admiral_fleet_id", ""))
	if world.fleet_registry.has(admiral_fleet):
		var fleet: Dictionary = world.fleet_registry[admiral_fleet]
		fleet["admiral_id"] = ""
		world.fleet_registry[admiral_fleet] = fleet
	character["admiral_fleet_id"] = ""
	world.character_registry[character_id] = character
	_remove_living_dynasty_member(world, character_id, String(character.get("dynasty_id", "")))
	events.character_died.emit(character_id, cause, world.current_day)
	_record_character_event(world, "death", {"character_id": character_id, "cause": cause})
	var ruled_countries: Array[String] = []
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if ruler_id(world, tag) == character_id:
			ruled_countries.append(tag)
	for country_tag in ruled_countries:
		_resolve_country_succession(world, events, country_tag, character_id)
	var held_titles: Array = character.get("titles", [])
	for raw_title_id in held_titles.duplicate():
		var title_id := String(raw_title_id)
		if not world.title_registry.has(title_id):
			continue
		var title_country := String((world.title_registry[title_id] as Dictionary).get("country_tag", ""))
		var successor := ruler_id(world, title_country)
		if successor.is_empty() or not bool((world.character_registry.get(successor, {}) as Dictionary).get("alive", false)):
			successor = _select_or_create_successor(world, character_id, title_country, title_id)
		grant_title(world, events, title_id, successor)
	_inherit_claims(world, character_id)
	return ""


static func eligible_heirs(world: CampaignWorldState, ruler_character_id: String, title_id := "") -> Array[String]:
	if not world.character_registry.has(ruler_character_id):
		return []
	var ruler: Dictionary = world.character_registry[ruler_character_id]
	var candidates: Array[String] = []
	for raw_child in ruler.get("children", []):
		var child_id := String(raw_child)
		if world.character_registry.has(child_id) and bool((world.character_registry[child_id] as Dictionary).get("alive", false)):
			candidates.append(child_id)
	if candidates.is_empty():
		var dynasty_id := String(ruler.get("dynasty_id", ""))
		for raw_member in (world.dynasty_registry.get(dynasty_id, {}) as Dictionary).get("living_members", []):
			var member_id := String(raw_member)
			if member_id != ruler_character_id and age_years(world, member_id) >= 0:
				candidates.append(member_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var birth_a := _birth_sort_key(world.character_registry[a])
		var birth_b := _birth_sort_key(world.character_registry[b])
		return birth_a < birth_b if birth_a != birth_b else a < b)
	return candidates


static func opinion_breakdown(world: CampaignWorldState, source_id: String, target_id: String) -> Dictionary:
	if not world.character_registry.has(source_id) or not world.character_registry.has(target_id):
		return {"total": 0, "sources": []}
	var source: Dictionary = world.character_registry[source_id]
	var target: Dictionary = world.character_registry[target_id]
	var sources: Array[Dictionary] = [{"label": "Base", "value": 0}]
	if String(source.get("spouse_id", "")) == target_id:
		sources.append({"label": "Spouse", "value": 40})
	if String(source.get("dynasty_id", "")) == String(target.get("dynasty_id", "")):
		sources.append({"label": "Same dynasty", "value": 20})
	if String(source.get("religion", "")) == String(target.get("religion", "")):
		sources.append({"label": "Same religion", "value": 10})
	else:
		sources.append({"label": "Different religion", "value": -15})
	if String(source.get("culture", "")) == String(target.get("culture", "")):
		sources.append({"label": "Same culture", "value": 5})
	if _has_claim_on_holder(world, source_id, target_id):
		sources.append({"label": "Claim on titles", "value": -20})
	var source_traits: Array = source.get("traits", [])
	var target_traits: Array = target.get("traits", [])
	if source_traits.has("just") and target_traits.has("just"):
		sources.append({"label": "Both just", "value": 8})
	if source_traits.has("ambitious") and target_traits.has("ambitious"):
		sources.append({"label": "Competing ambition", "value": -8})
	for raw_modifier in source.get("opinion_modifiers", []):
		var modifier: Dictionary = raw_modifier
		if String(modifier.get("target_id", "")) == target_id and (int(modifier.get("expires_day", -1)) < 0 or world.current_day <= int(modifier.get("expires_day", -1))):
			sources.append({"label": String(modifier.get("label", "Recent action")), "value": int(modifier.get("value", 0))})
	var target_country := String(target.get("employer_country", ""))
	if not target_country.is_empty() and ruler_id(world, target_country) == target_id and world.current_day <= int(world.country_runtime(target_country).get("short_reign_until_day", -1)):
		sources.append({"label": "Short reign", "value": -10})
	var total := 0
	for entry in sources:
		total += int(entry["value"])
	return {"total": clampi(total, -100, 100), "sources": sources}


static func recalculate_ruler_modifiers(world: CampaignWorldState, country_tag: String) -> void:
	if not world.has_country(country_tag):
		return
	var runtime := world.country_runtime(country_tag)
	var character_id := String(runtime.get("ruler_character_id", ""))
	var modifiers := {"tax_modifier_bp": 0, "production_modifier_bp": 0, "manpower_modifier_bp": 0, "diplomacy_bonus": 0}
	if world.character_registry.has(character_id):
		var character: Dictionary = world.character_registry[character_id]
		var skills: Dictionary = character.get("skills", {})
		modifiers["tax_modifier_bp"] = (int(skills.get("stewardship", 5)) - 5) * 100
		modifiers["production_modifier_bp"] = (int(skills.get("stewardship", 5)) - 5) * 50
		modifiers["manpower_modifier_bp"] = (int(skills.get("martial", 5)) - 5) * 100
		modifiers["diplomacy_bonus"] = int(skills.get("diplomacy", 5)) - 5
		var traits: Array = character.get("traits", [])
		if traits.has("diligent"):
			modifiers["tax_modifier_bp"] = int(modifiers["tax_modifier_bp"]) + 200
		if traits.has("lazy"):
			modifiers["tax_modifier_bp"] = int(modifiers["tax_modifier_bp"]) - 200
		if traits.has("brave"):
			modifiers["manpower_modifier_bp"] = int(modifiers["manpower_modifier_bp"]) + 100
	runtime["ruler_modifiers"] = modifiers
	world.set_country_runtime(country_tag, runtime)


static func character_summary(world: CampaignWorldState, character_id: String) -> Dictionary:
	if not world.character_registry.has(character_id):
		return {}
	var character: Dictionary = world.character_registry[character_id]
	var dynasty: Dictionary = world.dynasty_registry.get(String(character.get("dynasty_id", "")), {})
	return {
		"character_id": character_id, "name": String(character.get("name", character_id)),
		"age": age_years(world, character_id), "alive": bool(character.get("alive", false)),
		"sex": String(character.get("sex", "")), "culture": String(character.get("culture", "")),
		"religion": String(character.get("religion", "")), "dynasty_id": String(character.get("dynasty_id", "")), "dynasty": String(dynasty.get("name", "No dynasty")),
		"skills": (character.get("skills", {}) as Dictionary).duplicate(true),
		"traits": (character.get("traits", []) as Array).duplicate(), "health_bp": int(character.get("health_bp", 0)),
		"fertility_bp": int(character.get("fertility_bp", 0)), "stress_bp": int(character.get("stress_bp", 0)),
		"titles": (character.get("titles", []) as Array).duplicate(), "claims": (character.get("claims", []) as Array).duplicate(),
		"family": family(world, character_id), "employer_country": String(character.get("employer_country", "")),
	}


static func dynasty_summary(world: CampaignWorldState, dynasty_id: String) -> Dictionary:
	if not world.dynasty_registry.has(dynasty_id):
		return {}
	var dynasty: Dictionary = world.dynasty_registry[dynasty_id]
	return {
		"dynasty_id": dynasty_id, "name": String(dynasty.get("name", dynasty_id)),
		"founder_id": String(dynasty.get("founder_id", "")), "renown": int(dynasty.get("renown", 0)),
		"living_members": (dynasty.get("living_members", []) as Array).duplicate(),
		"player_dynasty": bool(dynasty.get("player_dynasty", false)),
	}


static func mark_player_dynasty(world: CampaignWorldState, country_tag: String) -> void:
	for raw_id in world.dynasty_registry:
		var dynasty: Dictionary = world.dynasty_registry[raw_id]
		dynasty["player_dynasty"] = false
		world.dynasty_registry[raw_id] = dynasty
	var ruler := ruler_id(world, country_tag)
	if not world.character_registry.has(ruler):
		return
	var dynasty_id := String((world.character_registry[ruler] as Dictionary).get("dynasty_id", ""))
	if world.dynasty_registry.has(dynasty_id):
		var dynasty: Dictionary = world.dynasty_registry[dynasty_id]
		dynasty["player_dynasty"] = true
		world.dynasty_registry[dynasty_id] = dynasty


static func refresh_country_heir(world: CampaignWorldState, country_tag: String) -> void:
	_refresh_heir(world, country_tag)


static func _process_coming_of_age(world: CampaignWorldState, events: SimulationEventBus, character_id: String, character: Dictionary) -> void:
	if age_years(world, character_id) != ADULT_AGE or bool(character.get("came_of_age", false)):
		return
	var skills: Dictionary = character.get("skills", {})
	for skill in ["diplomacy", "martial", "stewardship", "intrigue", "learning"]:
		if int(skills.get(skill, 0)) <= 1:
			skills[skill] = 3 + int(world.next_random_u32("character_education:%s:%s" % [character_id, skill]) % 6)
	character["skills"] = skills
	character["fertility_bp"] = maxi(int(character.get("fertility_bp", 0)), 5500)
	character["came_of_age"] = true
	world.character_registry[character_id] = character
	events.character_came_of_age.emit(character_id)
	_record_character_event(world, "coming_of_age", {"character_id": character_id})


static func _monthly_death_roll(world: CampaignWorldState, character_id: String, character: Dictionary) -> bool:
	var age := age_years(world, character_id)
	var mortality_per_100k := 10
	if age >= 80:
		mortality_per_100k = 8000
	elif age >= 70:
		mortality_per_100k = 2500
	elif age >= 55:
		mortality_per_100k = 500
	elif age >= 40:
		mortality_per_100k = 100
	elif age < 5:
		mortality_per_100k = 120
	var health := clampi(int(character.get("health_bp", 8000)), 1000, BASIS_POINTS)
	if not String(character.get("illness", "")).is_empty():
		health = maxi(1000, health - 2500)
	mortality_per_100k = mortality_per_100k * BASIS_POINTS / health
	return int(world.next_random_u32("character_health:%s" % character_id) % 100000) < mortality_per_100k


static func _process_health_events(world: CampaignWorldState, events: SimulationEventBus, character_id: String, character: Dictionary) -> void:
	var illness_until := int(character.get("illness_until_day", -1))
	if not String(character.get("illness", "")).is_empty() and world.current_day > illness_until:
		character["illness"] = ""
		character["illness_until_day"] = -1
		world.character_registry[character_id] = character
		_record_character_event(world, "recovery", {"character_id": character_id})
		return
	if String(character.get("illness", "")).is_empty() and int(world.next_random_u32("character_illness:%s" % character_id) % 10000) < 45:
		character["illness"] = "seasonal illness"
		character["illness_until_day"] = world.current_day + 90
		world.character_registry[character_id] = character
		events.character_became_ill.emit(character_id, "seasonal illness", world.current_day + 90)
		_record_character_event(world, "illness", {"character_id": character_id, "illness": "seasonal illness"})
	if world.current_day % 365 < 31:
		var traits: Array = character.get("traits", [])
		if traits.has("cautious"):
			character["stress_bp"] = maxi(0, int(character.get("stress_bp", 0)) - 200)
		elif traits.has("ambitious") and (character.get("titles", []) as Array).is_empty():
			character["stress_bp"] = mini(BASIS_POINTS, int(character.get("stress_bp", 0)) + 200)
		world.character_registry[character_id] = character


static func _process_births(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ids := world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var first_id := String(raw_id)
		var first: Dictionary = world.character_registry[first_id]
		var spouse_id := String(first.get("spouse_id", ""))
		if spouse_id.is_empty() or first_id > spouse_id or not world.character_registry.has(spouse_id):
			continue
		var second: Dictionary = world.character_registry[spouse_id]
		if not bool(first.get("alive", false)) or not bool(second.get("alive", false)):
			continue
		var mother_id := first_id if String(first.get("sex", "")) == "female" else spouse_id
		var father_id := spouse_id if mother_id == first_id else first_id
		var mother: Dictionary = world.character_registry[mother_id]
		if age_years(world, mother_id) < ADULT_AGE or age_years(world, mother_id) > 45:
			continue
		if world.current_day - int(mother.get("last_birth_day", -9999)) < BIRTH_COOLDOWN_DAYS:
			continue
		if (mother.get("children", []) as Array).size() >= MAX_CHILDREN:
			continue
		var chance := int(mother.get("fertility_bp", 0)) * int((world.character_registry[father_id] as Dictionary).get("fertility_bp", 0)) / BASIS_POINTS / 10
		if int(world.next_random_u32("character_fertility:%s" % mother_id) % BASIS_POINTS) >= chance:
			continue
		_create_child(world, events, mother_id, father_id)


static func _create_child(world: CampaignWorldState, events: SimulationEventBus, mother_id: String, father_id: String) -> String:
	var serial := world.take_counter("next_generated_character_id")
	var child_id := "ch_generated_%06d" % serial
	var father: Dictionary = world.character_registry[father_id]
	var mother: Dictionary = world.character_registry[mother_id]
	var current := SimulationDateScript.day_to_date(world.current_day)
	var sex := "male" if world.next_random_u32("character_birth_sex:%s" % child_id) % 2 == 0 else "female"
	var name := ("Child %d" % serial)
	var record := {
		"character_id": child_id, "name": name, "sex": sex,
		"birth": current.duplicate(true), "alive": true, "death_day": -1, "death_cause": "",
		"culture": String(father.get("culture", mother.get("culture", "Unknown"))),
		"religion": String(father.get("religion", mother.get("religion", "Unknown"))),
		"dynasty_id": String(father.get("dynasty_id", mother.get("dynasty_id", ""))),
		"father_id": father_id, "mother_id": mother_id, "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": String(father.get("employer_country", mother.get("employer_country", ""))),
		"skills": {"diplomacy": 1, "martial": 1, "stewardship": 1, "intrigue": 1, "learning": 1},
		"traits": [], "health_bp": 7500 + int(world.next_random_u32("character_birth_health:%s" % child_id) % 2001),
		"fertility_bp": 0, "stress_bp": 0, "titles": [], "claims": [], "event_cooldowns": {},
		"last_birth_day": -9999, "commander_army_id": "", "admiral_fleet_id": "", "came_of_age": false,
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
	}
	world.character_registry[child_id] = record
	for parent_id in [mother_id, father_id]:
		var parent: Dictionary = world.character_registry[parent_id]
		var children: Array = parent.get("children", [])
		if not children.has(child_id):
			children.append(child_id)
			children.sort()
		parent["children"] = children
		if parent_id == mother_id:
			parent["last_birth_day"] = world.current_day
		world.character_registry[parent_id] = parent
	_add_living_dynasty_member(world, child_id, String(record["dynasty_id"]))
	events.character_born.emit(child_id, mother_id, father_id)
	_record_character_event(world, "birth", {"character_id": child_id, "mother_id": mother_id, "father_id": father_id})
	return child_id


static func _ensure_court_demographics(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var country_tag := String(raw_tag)
		if ruler_id(world, country_tag).is_empty() or world.get_country_provinces(country_tag).is_empty():
			continue
		var adult_by_sex := {"male": 0, "female": 0}
		for character_id in world.living_characters_in_country(country_tag):
			if age_years(world, character_id) >= ADULT_AGE:
				var sex := String((world.character_registry[character_id] as Dictionary).get("sex", ""))
				adult_by_sex[sex] = int(adult_by_sex.get(sex, 0)) + 1
		for sex in ["male", "female"]:
			if int(adult_by_sex.get(sex, 0)) == 0:
				_create_courtier(world, events, country_tag, sex)


static func _create_courtier(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, sex: String) -> String:
	var serial := world.take_counter("next_generated_character_id")
	var character_id := "ch_generated_%06d" % serial
	var dynasty_id := "d_court_%06d" % serial
	var current := SimulationDateScript.day_to_date(world.current_day)
	var age := 18 + int(world.next_random_u32("courtier_age:%s" % character_id) % 11)
	var selected_trait: String = VALID_TRAITS[int(world.next_random_u32("courtier_trait:%s" % character_id) % VALID_TRAITS.size())]
	world.dynasty_registry[dynasty_id] = {"dynasty_id": dynasty_id, "name": "Court House %d" % serial, "founder_id": character_id, "renown": 5, "living_members": [character_id], "player_dynasty": false}
	world.character_registry[character_id] = {
		"character_id": character_id, "name": "Courtier %d" % serial, "sex": sex,
		"birth": {"year": int(current["year"]) - age, "month": int(current["month"]), "day": int(current["day"])},
		"alive": true, "death_day": -1, "death_cause": "", "culture": "Court culture", "religion": "Court faith",
		"dynasty_id": dynasty_id, "father_id": "", "mother_id": "", "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": country_tag,
		"skills": {"diplomacy": 3 + int(world.next_random_u32("courtier_dip:%s" % character_id) % 6), "martial": 3 + int(world.next_random_u32("courtier_mar:%s" % character_id) % 6), "stewardship": 3 + int(world.next_random_u32("courtier_ste:%s" % character_id) % 6), "intrigue": 3 + int(world.next_random_u32("courtier_int:%s" % character_id) % 6), "learning": 3 + int(world.next_random_u32("courtier_lea:%s" % character_id) % 6)},
		"traits": [selected_trait], "health_bp": 8200, "fertility_bp": 7000, "stress_bp": 0,
		"titles": [], "claims": [], "event_cooldowns": {}, "last_birth_day": -9999, "commander_army_id": "", "admiral_fleet_id": "", "came_of_age": true,
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
	}
	events.character_arrived_at_court.emit(character_id, country_tag)
	_record_character_event(world, "court_arrival", {"character_id": character_id, "country_tag": country_tag})
	return character_id


static func _resolve_country_succession(world: CampaignWorldState, events: SimulationEventBus, country_tag: String, old_ruler_id: String) -> void:
	var runtime := world.country_runtime(country_tag)
	var title_id := String(runtime.get("primary_title_id", ""))
	var successor := _select_or_create_successor(world, old_ruler_id, country_tag, title_id)
	runtime["ruler_character_id"] = successor
	runtime["reign_start_day"] = world.current_day
	runtime["short_reign_until_day"] = world.current_day + SHORT_REIGN_DAYS
	runtime["legitimacy_bp"] = maxi(2500, int(runtime.get("legitimacy_bp", 8000)) - 1500)
	world.set_country_runtime(country_tag, runtime)
	if world.title_registry.has(title_id) and String((world.title_registry[title_id] as Dictionary).get("holder_id", "")) != successor:
		grant_title(world, events, title_id, successor)
	_refresh_heir(world, country_tag)
	recalculate_ruler_modifiers(world, country_tag)
	events.succession_resolved.emit(country_tag, old_ruler_id, successor, heir_id(world, country_tag))
	_record_character_event(world, "succession", {"country_tag": country_tag, "old_ruler_id": old_ruler_id, "new_ruler_id": successor})


static func _select_or_create_successor(world: CampaignWorldState, old_ruler_id: String, country_tag: String, title_id: String) -> String:
	var candidates := eligible_heirs(world, old_ruler_id, title_id)
	if not candidates.is_empty():
		return candidates[0]
	return _create_emergency_successor(world, old_ruler_id, country_tag)


static func _create_emergency_successor(world: CampaignWorldState, old_ruler_id: String, country_tag: String) -> String:
	var serial := world.take_counter("next_generated_character_id")
	var character_id := "ch_generated_%06d" % serial
	var current := SimulationDateScript.day_to_date(world.current_day)
	var dynasty_id := "d_cadet_%06d" % serial
	world.dynasty_registry[dynasty_id] = {"dynasty_id": dynasty_id, "name": "Cadet House %d" % serial, "founder_id": character_id, "renown": 10, "living_members": [character_id], "player_dynasty": false}
	world.character_registry[character_id] = {
		"character_id": character_id, "name": "Successor %d" % serial, "sex": "male",
		"birth": {"year": int(current["year"]) - 25, "month": int(current["month"]), "day": int(current["day"])},
		"alive": true, "death_day": -1, "death_cause": "", "culture": "Court culture", "religion": "Court faith",
		"dynasty_id": dynasty_id, "father_id": "", "mother_id": "", "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": country_tag, "skills": {"diplomacy": 5, "martial": 5, "stewardship": 5, "intrigue": 5, "learning": 5},
		"traits": ["patient"], "health_bp": 8500, "fertility_bp": 6500, "stress_bp": 0, "titles": [], "claims": [],
		"event_cooldowns": {}, "last_birth_day": -9999, "commander_army_id": "", "admiral_fleet_id": "", "came_of_age": true,
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
	}
	return character_id


static func _refresh_all_heirs(world: CampaignWorldState) -> void:
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		if not ruler_id(world, String(raw_tag)).is_empty():
			_refresh_heir(world, String(raw_tag))


static func _refresh_heir(world: CampaignWorldState, country_tag: String) -> void:
	var runtime := world.country_runtime(country_tag)
	var ruler := String(runtime.get("ruler_character_id", ""))
	var title := String(runtime.get("primary_title_id", ""))
	var candidates := eligible_heirs(world, ruler, title)
	runtime["heir_character_id"] = candidates[0] if not candidates.is_empty() else ""
	world.set_country_runtime(country_tag, runtime)


static func _inherit_claims(world: CampaignWorldState, deceased_id: String) -> void:
	var deceased: Dictionary = world.character_registry[deceased_id]
	var heirs := eligible_heirs(world, deceased_id)
	if heirs.is_empty():
		return
	var heir := heirs[0]
	for raw_claim_id in deceased.get("claims", []):
		var claim_id := String(raw_claim_id)
		if not world.claim_registry.has(claim_id):
			continue
		var source: Dictionary = world.claim_registry[claim_id]
		if not bool(source.get("inheritable", false)):
			continue
		var inherited_id := "%s_inherited_%d" % [claim_id, world.take_counter("next_claim_id")]
		var inherited := source.duplicate(true)
		inherited["claim_id"] = inherited_id
		inherited["claimant_id"] = heir
		inherited["created_day"] = world.current_day
		inherited["pressed"] = false
		world.claim_registry[inherited_id] = inherited
		_link_claim(world, inherited_id, inherited)


static func _link_claim(world: CampaignWorldState, claim_id: String, claim: Dictionary) -> void:
	var claimant := String(claim.get("claimant_id", ""))
	var title_id := String(claim.get("title_id", ""))
	if world.character_registry.has(claimant):
		var character: Dictionary = world.character_registry[claimant]
		var claims: Array = character.get("claims", [])
		if not claims.has(claim_id):
			claims.append(claim_id)
			claims.sort()
		character["claims"] = claims
		world.character_registry[claimant] = character
	if world.title_registry.has(title_id):
		var title: Dictionary = world.title_registry[title_id]
		var claims: Array = title.get("claims", [])
		if not claims.has(claim_id):
			claims.append(claim_id)
			claims.sort()
		title["claims"] = claims
		world.title_registry[title_id] = title


static func _rebuild_dynasty_indexes(world: CampaignWorldState) -> void:
	for raw_id in world.dynasty_registry:
		var record: Dictionary = world.dynasty_registry[raw_id]
		record["living_members"] = []
		world.dynasty_registry[raw_id] = record
	var ids := world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var character: Dictionary = world.character_registry[raw_id]
		if bool(character.get("alive", false)):
			_add_living_dynasty_member(world, String(raw_id), String(character.get("dynasty_id", "")))


static func _add_living_dynasty_member(world: CampaignWorldState, character_id: String, dynasty_id: String) -> void:
	if not world.dynasty_registry.has(dynasty_id):
		return
	var dynasty: Dictionary = world.dynasty_registry[dynasty_id]
	var members: Array = dynasty.get("living_members", [])
	if not members.has(character_id):
		members.append(character_id)
		members.sort()
	dynasty["living_members"] = members
	world.dynasty_registry[dynasty_id] = dynasty


static func _remove_living_dynasty_member(world: CampaignWorldState, character_id: String, dynasty_id: String) -> void:
	if not world.dynasty_registry.has(dynasty_id):
		return
	var dynasty: Dictionary = world.dynasty_registry[dynasty_id]
	var members: Array = dynasty.get("living_members", [])
	members.erase(character_id)
	dynasty["living_members"] = members
	world.dynasty_registry[dynasty_id] = dynasty


static func _record_character_event(world: CampaignWorldState, type: String, data: Dictionary) -> void:
	var history: Array = world.global_flags.get("character_event_history", [])
	var record := data.duplicate(true)
	record["type"] = type
	record["day"] = world.current_day
	history.append(record)
	while history.size() > 128:
		history.pop_front()
	world.global_flags["character_event_history"] = history


static func _close_family(first: Dictionary, second: Dictionary, first_id: String, second_id: String) -> bool:
	if [String(first.get("father_id", "")), String(first.get("mother_id", ""))].has(second_id):
		return true
	if [String(second.get("father_id", "")), String(second.get("mother_id", ""))].has(first_id):
		return true
	if (first.get("children", []) as Array).has(second_id) or (second.get("children", []) as Array).has(first_id):
		return true
	var first_parents := [String(first.get("father_id", "")), String(first.get("mother_id", ""))]
	var second_parents := [String(second.get("father_id", "")), String(second.get("mother_id", ""))]
	for parent in first_parents:
		if not parent.is_empty() and second_parents.has(parent):
			return true
	return false


static func _birth_sort_key(character: Dictionary) -> int:
	var birth: Dictionary = character.get("birth", {})
	return int(birth.get("year", 0)) * 10000 + int(birth.get("month", 0)) * 100 + int(birth.get("day", 0))


static func _has_claim_on_holder(world: CampaignWorldState, source_id: String, target_id: String) -> bool:
	for raw_claim_id in (world.character_registry[source_id] as Dictionary).get("claims", []):
		var claim: Dictionary = world.claim_registry.get(String(raw_claim_id), {})
		var title: Dictionary = world.title_registry.get(String(claim.get("title_id", "")), {})
		if String(title.get("holder_id", "")) == target_id:
			return true
	return false
