class_name AIDebugHUD
extends Control

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var map_hud: MapHUD
@export var notification_hud: SimulationHUD

@onready var campaign_button: Button = %CampaignButton
@onready var panel: PanelContainer = %AIPanel
@onready var close_button: Button = %CloseButton
@onready var objective_label: Label = %ObjectiveLabel
@onready var status_label: Label = %CampaignStatus
@onready var country_option: OptionButton = %CountryOption
@onready var strategy_label: Label = %StrategyLabel
@onready var plan_label: Label = %PlanLabel
@onready var resources_label: Label = %ResourcesLabel
@onready var threat_label: Label = %ThreatLabel
@onready var decision_label: Label = %DecisionLabel
@onready var schedule_label: Label = %ScheduleLabel
@onready var history_label: RichTextLabel = %HistoryLabel
@onready var objective_map_button: Button = %ObjectiveMapButton
@onready var summary_label: RichTextLabel = %SummaryLabel

var _selected_country := "CAS"


func _ready() -> void:
	panel.hide()
	campaign_button.pressed.connect(func() -> void:
		panel.visible = not panel.visible
		if panel.visible:
			_refresh_all())
	close_button.pressed.connect(panel.hide)
	country_option.item_selected.connect(_select_country)
	objective_map_button.pressed.connect(_show_objective_map)
	_populate_countries()
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, player: String) -> void:
		if simulation_controller.ai_definitions != null and simulation_controller.ai_definitions.country_tags().has(player):
			_selected_country = player
			_select_option_for_tag(player)
		_refresh_all())
	events.ai_decision_made.connect(func(tag: String, _category: String, _action: String, _score: int, _reason: String) -> void:
		if panel.visible and tag == _selected_country:
			_refresh_ai())
	events.ai_goal_changed.connect(func(tag: String, _goal: String, _posture: String) -> void:
		if panel.visible and tag == _selected_country:
			_refresh_ai())
	events.campaign_status_changed.connect(func(status: String, _summary: Dictionary) -> void:
		_notify("Regional campaign status: %s." % status.capitalize())
		_refresh_all())
	events.date_changed.connect(func(_day: int, _date: Dictionary) -> void:
		if panel.visible:
			_refresh_campaign()
			_refresh_ai())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())


func _populate_countries() -> void:
	country_option.clear()
	if simulation_controller.ai_definitions == null:
		return
	for tag in simulation_controller.ai_definitions.country_tags():
		if not simulation_controller.world.has_country(tag):
			continue
		country_option.add_item(_country_name(tag))
		country_option.set_item_metadata(country_option.item_count - 1, tag)
	_select_option_for_tag(_selected_country)


func _select_option_for_tag(tag: String) -> void:
	for index in range(country_option.item_count):
		if String(country_option.get_item_metadata(index)) == tag:
			country_option.select(index)
			return


func _select_country(index: int) -> void:
	_selected_country = String(country_option.get_item_metadata(index))
	_refresh_ai()


func _refresh_all() -> void:
	if not is_node_ready() or not simulation_controller.initialized:
		return
	_refresh_campaign()
	_refresh_ai()


func _refresh_campaign() -> void:
	var world := simulation_controller.world
	var player := world.player_country
	var objectives: Dictionary = world.global_flags.get("campaign_objectives", {})
	var objective_tag := player if objectives.has(player) else _selected_country
	var objective: Dictionary = objectives.get(objective_tag, {})
	objective_label.text = "Objective · %s\n%s" % [_country_name(objective_tag), String(objective.get("text", "Select an Iberian country to receive a campaign objective."))]
	var end_day := int(world.global_flags.get("vertical_slice_end_day", 7305))
	status_label.text = "Status: %s  ·  Day %d/%d  ·  Ends %s  ·  Objective %s" % [
		String(world.global_flags.get("campaign_status", "running")).capitalize(),
		world.current_day,
		end_day,
		SimulationDate.format_day(end_day),
		"complete" if bool(objective.get("complete", false)) else "in progress",
	]
	var summary: Dictionary = world.global_flags.get("campaign_summary", {})
	summary_label.visible = not summary.is_empty()
	if not summary.is_empty():
		summary_label.text = _format_summary(summary)


func _refresh_ai() -> void:
	var snapshot := simulation_controller.ai_debug_snapshot(_selected_country)
	if snapshot.is_empty():
		strategy_label.text = "No AI state is available for this country."
		return
	strategy_label.text = "%s · %s\nGoal: %s  ·  Posture: %s  ·  Target: %s / province %d" % [
		String(snapshot.get("government", "Unknown government")), String(snapshot.get("ruler", "Unknown ruler")),
		String(snapshot.get("goal", "none")).replace("_", " ").capitalize(),
		String(snapshot.get("posture", "none")).capitalize(),
		_country_name_or_none(String(snapshot.get("target_country", "none"))),
		int(snapshot.get("target_province_id", -1)),
	]
	var plan_text := String(snapshot.get("plan", "Observe."))
	var plan_target := String(snapshot.get("target_country", ""))
	if not plan_target.is_empty():
		plan_text = plan_text.replace(plan_target, _country_name(plan_target))
	var threat_country := String((snapshot.get("highest_threat", {}) as Dictionary).get("country", ""))
	if not threat_country.is_empty():
		plan_text = plan_text.replace(threat_country, _country_name(threat_country))
	plan_label.text = "Current plan\n%s" % plan_text
	resources_label.text = "Army %d / desired %d  ·  Treasury reserve %s" % [
		int(snapshot.get("current_army_strength", 0)),
		int(snapshot.get("desired_army_strength", 0)),
		EconomySystemScript.format_money(int(snapshot.get("reserve_target", 0))),
	]
	var threat: Dictionary = snapshot.get("highest_threat", {})
	threat_label.text = "Highest threat: %s  ·  score %d  ·  shared borders %d  ·  relative strength %d%%" % [
		_country_name_or_none(String(threat.get("country", "none"))), int(threat.get("score", 0)),
		int(threat.get("border_count", 0)), int(threat.get("relative_strength_percent", 0)),
	]
	var decision: Dictionary = snapshot.get("last_decision", {})
	var alternative_texts: Array[String] = []
	for raw_alternative in decision.get("alternatives", []):
		var alternative: Dictionary = raw_alternative
		alternative_texts.append("%s (%+d)" % [String(alternative.get("action_id", "candidate")), int(alternative.get("score", 0))])
	var rejected: Array = snapshot.get("rejected_candidates", [])
	var rejection_text := "none"
	if not rejected.is_empty():
		var last_rejection: Dictionary = rejected[-1]
		rejection_text = "%s — %s" % [String(last_rejection.get("action", "candidate")), String(last_rejection.get("reason", "rejected"))]
	decision_label.text = "Last decision: %s · score %d\n%s\nAlternatives: %s\nLast rejected candidate: %s\nDecision cost: %.2f ms" % [
		String(decision.get("action", "none")), int(decision.get("score", 0)),
		String(decision.get("reason", "No decision recorded.")), ", ".join(alternative_texts) if not alternative_texts.is_empty() else "none recorded",
		rejection_text, int(snapshot.get("decision_cost_usec", 0)) / 1000.0,
	]
	schedule_label.text = "Next reviews · economy day %d · diplomacy day %d · military day %d\nDeterministic seeds · campaign %d · country %d" % [
		int(snapshot.get("next_economy_day", 0)), int(snapshot.get("next_diplomacy_day", 0)), int(snapshot.get("next_military_day", 0)),
		int(snapshot.get("campaign_seed", 0)), int(snapshot.get("country_seed", 0)),
	]
	var lines: Array[String] = ["[b]Recent decisions[/b]"]
	for raw_record in (snapshot.get("decision_history", []) as Array).slice(-8):
		var record: Dictionary = raw_record
		lines.append("Day %d · %s · %s (%+d)" % [int(record.get("day", 0)), String(record.get("category", "")), String(record.get("action", "")), int(record.get("score", 0))])
	history_label.text = "\n".join(lines)


func _show_objective_map() -> void:
	var colors := simulation_controller.ai_objective_map_values(_selected_country)
	map_hud.set_strategy_map_overlay("ai_objectives", "AI objectives: cyan capital, gold target, purple ordered destination.", colors)


func _format_summary(summary: Dictionary) -> String:
	var lines: Array[String] = ["[b]Campaign summary[/b]", "Status: %s · completed wars: %d" % [String(summary.get("status", "")), int(summary.get("completed_wars", 0))]]
	var countries: Dictionary = summary.get("countries", {})
	var tags := countries.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var record: Dictionary = countries[raw_tag]
		lines.append("%s · provinces %d · army %d · treasury %s · debt %s · objective %s" % [
			_country_name(tag), int(record.get("provinces", 0)), int(record.get("army_strength", 0)),
			EconomySystemScript.format_money(int(record.get("treasury", 0))), EconomySystemScript.format_money(int(record.get("debt", 0))),
			"complete" if bool(record.get("objective_complete", false)) else "failed",
		])
	return "\n".join(lines)


func _country_name(tag: String) -> String:
	return String(simulation_controller.country_data.country_id_to_country_name.get(tag, "Unknown country"))


func _country_name_or_none(tag: String) -> String:
	return "none" if tag.is_empty() or tag == "none" else _country_name(tag)


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)
