class_name DiplomacySystem
extends RefCounted

## Canonical, deterministic relationship and war-query helpers. Relationship
## records use a sorted pair key so A/B and B/A can never diverge.

const DEFAULT_TRUCE_DAYS := 365 * 5


static func relation_key(country_a: String, country_b: String) -> String:
	var tags := [country_a, country_b]
	tags.sort()
	return "%s|%s" % tags


static func relation(world: CampaignWorldState, country_a: String, country_b: String) -> Dictionary:
	var key := relation_key(country_a, country_b)
	var stored: Dictionary = world.diplomatic_relations.get(key, {})
	var tags := [country_a, country_b]
	tags.sort()
	return {
		"countries": tags,
		"opinions": (stored.get("opinions", {}) as Dictionary).duplicate(true),
		"alliance": bool(stored.get("alliance", false)),
		"rivalry": bool(stored.get("rivalry", false)),
		"military_access": (stored.get("military_access", {}) as Dictionary).duplicate(true),
		"access_requests": (stored.get("access_requests", {}) as Dictionary).duplicate(true),
		"truce_until_day": int(stored.get("truce_until_day", -1)),
		"subject": (stored.get("subject", {}) as Dictionary).duplicate(true),
	}


static func set_relation(world: CampaignWorldState, country_a: String, country_b: String, value: Dictionary) -> void:
	world.diplomatic_relations[relation_key(country_a, country_b)] = value.duplicate(true)


static func opinion(world: CampaignWorldState, observer: String, target: String) -> int:
	return int((relation(world, observer, target)["opinions"] as Dictionary).get(observer, 0))


static func improve_relations(world: CampaignWorldState, observer: String, target: String, amount := 10) -> int:
	var record := relation(world, observer, target)
	var opinions: Dictionary = record["opinions"]
	var updated := clampi(int(opinions.get(observer, 0)) + amount, -200, 200)
	opinions[observer] = updated
	record["opinions"] = opinions
	set_relation(world, observer, target, record)
	return updated


static func are_allied(world: CampaignWorldState, country_a: String, country_b: String) -> bool:
	return bool(relation(world, country_a, country_b).get("alliance", false))


static func has_access(world: CampaignWorldState, moving_country: String, host_country: String) -> bool:
	if moving_country == host_country or host_country.is_empty():
		return true
	var access: Dictionary = relation(world, moving_country, host_country).get("military_access", {})
	return bool(access.get(moving_country, false))


static func active_war_between(world: CampaignWorldState, country_a: String, country_b: String) -> String:
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var attackers: Array = war.get("attackers", [])
		var defenders: Array = war.get("defenders", [])
		if (attackers.has(country_a) and defenders.has(country_b)) or (attackers.has(country_b) and defenders.has(country_a)):
			return String(raw_war_id)
	return ""


static func are_at_war(world: CampaignWorldState, country_a: String, country_b: String) -> bool:
	return not active_war_between(world, country_a, country_b).is_empty()


static func country_wars(world: CampaignWorldState, country_tag: String) -> Array[String]:
	var found: Array[String] = []
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) == "active" and ((war.get("attackers", []) as Array).has(country_tag) or (war.get("defenders", []) as Array).has(country_tag)):
			found.append(String(raw_war_id))
	return found


static func side_in_war(war: Dictionary, country_tag: String) -> int:
	if (war.get("attackers", []) as Array).has(country_tag):
		return 1
	if (war.get("defenders", []) as Array).has(country_tag):
		return -1
	return 0


static func has_active_truce(world: CampaignWorldState, country_a: String, country_b: String) -> bool:
	return int(relation(world, country_a, country_b).get("truce_until_day", -1)) > world.current_day


static func create_truce(world: CampaignWorldState, country_a: String, country_b: String, duration_days := DEFAULT_TRUCE_DAYS) -> int:
	var record := relation(world, country_a, country_b)
	var end_day := world.current_day + maxi(duration_days, 1)
	record["truce_until_day"] = end_day
	record["alliance"] = false
	set_relation(world, country_a, country_b, record)
	return end_day
