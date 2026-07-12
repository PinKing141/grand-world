class_name AcceptCultureCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var culture_id := ""

func _init(p_country_tag: String, p_culture_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; culture_id = p_culture_id; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s accepts %s culture" % [country_tag, culture_id]

func command_type() -> String: return "AcceptCultureCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not CountryDepthDefinitionsScript.load_default().cultures().has(culture_id): return "The country or culture is invalid."
	var runtime := world.country_runtime(country_tag)
	if culture_id == String(runtime.get("primary_culture", "")) or (runtime.get("accepted_cultures", []) as Array).has(culture_id): return "This culture is already accepted."
	if int((runtime.get("technology", {}) as Dictionary).get("diplomatic", 0)) < 2: return "Diplomatic technology 2 is required."
	if int((runtime.get("technology_points", {}) as Dictionary).get("diplomatic", 0)) < 200: return "Accepting a culture costs 200 diplomatic points."
	var present := false
	for province_id in world.get_country_provinces(country_tag):
		if String(world.province_states[province_id].get("economy", {}).get("culture", "")) == culture_id: present = true
	if not present: return "The culture is not present in the country."
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.accept_culture(world, events, country_tag, culture_id)
