class_name IncreaseStabilityCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var country_tag := ""

func _init(p_country_tag: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s invests in national stability" % country_tag

func command_type() -> String: return "IncreaseStabilityCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag): return "The country does not exist."
	var runtime := world.country_runtime(country_tag)
	if int(runtime.get("stability", 0)) >= 3: return "Stability is already at its maximum."
	var modifiers: Dictionary = runtime.get("country_depth_modifiers", {})
	var cost := 200 * (10000 + int(modifiers.get("stability_cost_modifier_bp", 0))) / 10000
	if int((runtime.get("technology_points", {}) as Dictionary).get("administrative", 0)) < cost: return "Insufficient administrative technology points."
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var runtime := world.country_runtime(country_tag)
	var modifiers: Dictionary = runtime.get("country_depth_modifiers", {})
	var cost := 200 * (10000 + int(modifiers.get("stability_cost_modifier_bp", 0))) / 10000
	var points: Dictionary = runtime.get("technology_points", {})
	points["administrative"] = int(points.get("administrative", 0)) - cost
	runtime["technology_points"] = points
	runtime["stability"] = int(runtime.get("stability", 0)) + 1
	world.set_country_runtime(country_tag, runtime)
	events.stability_changed.emit(country_tag, int(runtime["stability"]))
