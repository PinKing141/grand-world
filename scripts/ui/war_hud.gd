class_name WarHUD
extends Control

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var map_hud: MapHUD
@export var notification_hud: SimulationHUD
@export var show_legacy_open_button := false

@onready var diplomacy_button: Button = %DiplomacyButton
@onready var diplomacy_panel: PanelContainer = %DiplomacyPanel
@onready var close_button: Button = %CloseButton
@onready var target_title: Label = %TargetTitle
@onready var relation_summary: Label = %RelationSummary
@onready var improve_button: Button = %ImproveButton
@onready var alliance_button: Button = %AllianceButton
@onready var access_button: Button = %AccessButton
@onready var declare_war_button: Button = %DeclareWarButton
@onready var war_option: OptionButton = %WarOption
@onready var war_summary: Label = %WarSummary
@onready var relations_map_button: Button = %RelationsMapButton
@onready var access_map_button: Button = %AccessMapButton
@onready var war_map_button: Button = %WarMapButton
@onready var white_peace_button: Button = %WhitePeaceButton
@onready var demand_goal_button: Button = %DemandGoalButton
@onready var accept_offer_button: Button = %AcceptOfferButton
@onready var details_label: Label = %DetailsLabel

var _target_country := ""
var _target_province_id := -1
var _current_war_id := ""
var _inspected_foreign_war_id := ""
var _focused_marker_context: Dictionary = {}


func _ready() -> void:
	diplomacy_panel.hide()
	diplomacy_button.pressed.connect(func() -> void:
		diplomacy_panel.visible = not diplomacy_panel.visible
		_refresh_all())
	close_button.pressed.connect(diplomacy_panel.hide)
	improve_button.pressed.connect(_improve_relations)
	alliance_button.pressed.connect(_toggle_alliance)
	access_button.pressed.connect(_handle_access)
	declare_war_button.pressed.connect(_declare_war)
	war_option.item_selected.connect(_select_war)
	relations_map_button.pressed.connect(_show_relations_map)
	access_map_button.pressed.connect(_show_access_map)
	war_map_button.pressed.connect(_show_war_map)
	white_peace_button.pressed.connect(_offer_white_peace)
	demand_goal_button.pressed.connect(_offer_war_goal)
	accept_offer_button.pressed.connect(_accept_incoming_offer)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(func() -> void:
		_target_country = ""
		_target_province_id = -1
		_refresh_target())
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.relations_changed.connect(func(_a: String, _b: String, _value: int) -> void: _refresh_all())
	events.alliance_changed.connect(func(_a: String, _b: String, _value: bool) -> void: _refresh_all())
	events.military_access_changed.connect(func(_a: String, _b: String, _value: bool) -> void: _refresh_all())
	events.military_access_requested.connect(func(_a: String, _b: String) -> void: _refresh_all())
	events.war_declared.connect(func(war_id: String, attacker: String, defender: String, _goal: int) -> void:
		_current_war_id = war_id
		_notify("%s declared war on %s." % [_country_name(attacker), _country_name(defender)])
		_refresh_all())
	events.battle_started.connect(func(_war: String, _battle: String, province_id: int) -> void:
		_notify("Battle started in province %d." % province_id)
		_refresh_all())
	events.battle_ended.connect(func(_war: String, _battle: String, winner: String) -> void:
		_notify("Battle ended · %s side won." % winner.capitalize())
		_refresh_all())
	events.occupation_changed.connect(func(_war: String, province_id: int, controller: String) -> void:
		_notify("Province %d occupied by %s." % [province_id, _country_name(controller)])
		_refresh_all())
	events.war_score_changed.connect(func(_war: String, _score: int) -> void:
		if diplomacy_panel.visible:
			_refresh_war())
	events.peace_offered.connect(func(_war: String, _offer: String, offerer: String, receiver: String) -> void:
		_notify("%s sent a peace offer to %s." % [_country_name(offerer), _country_name(receiver)])
		_refresh_all())
	events.peace_signed.connect(func(_war: String, attacker: String, defender: String, truce_day: int) -> void:
		_notify("Peace signed between %s and %s · truce until %s." % [_country_name(attacker), _country_name(defender), SimulationDate.format_day(truce_day)])
		_refresh_all())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())


func _player_country() -> String:
	return simulation_controller.world.player_country if simulation_controller.initialized else ""


func _country_name(tag: String) -> String:
	return String(simulation_controller.country_data.country_id_to_country_name.get(tag, "Unknown country"))


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)


func _on_province_selected(info: Dictionary) -> void:
	_target_province_id = int(info.get("province_id", -1))
	_target_country = String(info.get("owner_tag", ""))
	_refresh_target()


func focus_conflict_marker(marker: Dictionary) -> void:
	var war_id := String(marker.get("war_id", ""))
	if war_id.is_empty() or not simulation_controller.world.war_registry.has(war_id):
		return
	_current_war_id = war_id
	_inspected_foreign_war_id = war_id
	_focused_marker_context = marker.duplicate(true)
	_target_province_id = int(marker.get("province_id", -1))
	_target_country = simulation_controller.world.get_province_owner(_target_province_id)
	diplomacy_panel.show()
	_refresh_all()


func open_diplomacy_panel() -> void:
	diplomacy_panel.show()
	_refresh_all()


func _refresh_all() -> void:
	var player := _player_country()
	diplomacy_button.visible = show_legacy_open_button and not player.is_empty()
	_refresh_target()
	_refresh_war_list()
	_refresh_war()


func _refresh_target() -> void:
	if not is_node_ready():
		return
	var player := _player_country()
	var valid := not player.is_empty() and not _target_country.is_empty() and _target_country != player and simulation_controller.world.has_country(_target_country)
	if not valid:
		target_title.text = "Select another country's province"
		relation_summary.text = "Diplomatic actions use the country that legally owns the selected province."
		for button in [improve_button, alliance_button, access_button, declare_war_button]:
			button.disabled = true
		return
	var relationship := simulation_controller.relationship(player, _target_country)
	var opinion := int((relationship.get("opinions", {}) as Dictionary).get(player, 0))
	var truce_day := int(relationship.get("truce_until_day", -1))
	var truce_text := SimulationDate.format_day(truce_day) if truce_day > simulation_controller.world.current_day else "none"
	target_title.text = _country_name(_target_country)
	relation_summary.text = "Opinion %+d  ·  Alliance %s  ·  Access %s  ·  Truce %s" % [
		opinion,
		"yes" if bool(relationship.get("alliance", false)) else "no",
		"yes" if DiplomacySystemScript.has_access(simulation_controller.world, player, _target_country) else "no",
		truce_text,
	]
	improve_button.disabled = DiplomacySystemScript.are_at_war(simulation_controller.world, player, _target_country)
	alliance_button.disabled = DiplomacySystemScript.are_at_war(simulation_controller.world, player, _target_country)
	alliance_button.text = "Break alliance" if bool(relationship.get("alliance", false)) else "Form alliance"
	var requests: Dictionary = relationship.get("access_requests", {})
	var incoming_request := bool(requests.get(_target_country, false))
	var outgoing_request := bool(requests.get(player, false))
	access_button.text = "Grant access" if incoming_request else ("Access requested" if outgoing_request else "Request access")
	access_button.disabled = outgoing_request or DiplomacySystemScript.are_at_war(simulation_controller.world, player, _target_country) or DiplomacySystemScript.has_access(simulation_controller.world, player, _target_country)
	var needs_justification := bool(simulation_controller.world.global_flags.get("country_depth_enabled", false)) and not CountryDepthSystemScript.has_valid_claim_or_core(simulation_controller.world, player, _target_province_id)
	declare_war_button.disabled = DiplomacySystemScript.are_at_war(simulation_controller.world, player, _target_country) or _target_province_id < 0 or needs_justification
	declare_war_button.text = "Claim required · use Country & State" if needs_justification else "Declare conquest war for province %d" % _target_province_id
	declare_war_button.tooltip_text = "Fabricate a claim from Country & State → Society before declaring war." if needs_justification else "Declare a justified conquest war for this province."


func _refresh_war_list() -> void:
	var previous := _current_war_id
	war_option.clear()
	var wars: Array = simulation_controller.country_wars(_player_country())
	if not _inspected_foreign_war_id.is_empty() and simulation_controller.world.war_registry.has(_inspected_foreign_war_id):
		var inspected: Dictionary = simulation_controller.world.war_registry[_inspected_foreign_war_id]
		if String(inspected.get("status", "active")) == "active" and not wars.has(_inspected_foreign_war_id):
			wars.append(_inspected_foreign_war_id)
	wars.sort()
	for war_id in wars:
		var war: Dictionary = simulation_controller.world.war_registry[war_id]
		war_option.add_item(_war_display_name(war))
		war_option.set_item_metadata(war_option.item_count - 1, war_id)
	if wars.is_empty():
		_current_war_id = ""
		war_option.add_item("No active wars")
		war_option.disabled = true
	else:
		war_option.disabled = false
		_current_war_id = previous if wars.has(previous) else wars[0]
		for index in range(war_option.item_count):
			if String(war_option.get_item_metadata(index)) == _current_war_id:
				war_option.select(index)
				break


func _war_display_name(war: Dictionary) -> String:
	var attacker := _country_name(String(war.get("attacker_leader", "")))
	var defender := _country_name(String(war.get("defender_leader", "")))
	var goal: Dictionary = war.get("war_goal", {})
	if String(goal.get("type", "")) == "press_claim":
		var title: Dictionary = simulation_controller.world.title_registry.get(String(goal.get("title_id", "")), {})
		return "%s claim on %s" % [attacker, String(title.get("name", "a title"))]
	return "%s conquest against %s" % [attacker, defender]


func _refresh_war() -> void:
	var valid := not _current_war_id.is_empty() and simulation_controller.world.war_registry.has(_current_war_id)
	for button in [war_map_button, white_peace_button, demand_goal_button, accept_offer_button]:
		button.disabled = not valid
	if not valid:
		war_summary.text = "No active war."
		details_label.text = "Declare a conquest war to begin the Phase 5 conflict loop."
		return
	var war: Dictionary = simulation_controller.world.war_registry[_current_war_id]
	var goal: Dictionary = war.get("war_goal", {})
	var goal_text := "Province %d" % int(goal.get("province_id", -1))
	if String(goal.get("type", "")) == "press_claim":
		var title: Dictionary = simulation_controller.world.title_registry.get(String(goal.get("title_id", "")), {})
		var claimant: Dictionary = simulation_controller.world.character_registry.get(String(goal.get("claimant_id", "")), {})
		goal_text = "Press %s's claim on %s" % [String(claimant.get("name", "claimant")), String(title.get("name", goal.get("title_id", "title")))]
	war_summary.text = "%s vs %s  ·  War score %+d (blockade %+d)  ·  %s" % [
		_country_name(String(war["attacker_leader"])),
		_country_name(String(war["defender_leader"])),
		int(war.get("total_war_score", 0)),
		int(war.get("blockade_score_attacker", 0)),
		goal_text,
	]
	demand_goal_button.text = "Enforce claim" if String(goal.get("type", "")) == "press_claim" else "Demand war goal"
	if String(goal.get("type", "")) == "press_claim" and DiplomacySystemScript.side_in_war(war, _player_country()) < 0:
		demand_goal_button.disabled = true
	var active_battles := 0
	for battle in (war.get("battles", {}) as Dictionary).values():
		if String((battle as Dictionary).get("status", "")) == "active":
			active_battles += 1
	var offers: Dictionary = war.get("peace_offers", {})
	var incoming := _incoming_offer_id(war)
	accept_offer_button.disabled = incoming.is_empty()
	var result_text := ""
	var battle_ids := (war.get("battles", {}) as Dictionary).keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle: Dictionary = war["battles"][raw_battle_id]
		if String(battle.get("status", "")) == "completed":
			result_text = "\nLatest result: %s won · losses %d/%d · %s" % [
				String(battle.get("winner_side", "unknown")).capitalize(),
				int(battle.get("attacker_casualties", 0)),
				int(battle.get("defender_casualties", 0)),
				String(battle.get("terrain", "plains")).capitalize(),
			]
	details_label.text = ("Battles %d active / %d recorded  ·  Sieges %d  ·  Occupations %d  ·  Peace offers %d" % [
		active_battles,
		(war.get("battles", {}) as Dictionary).size(),
		(war.get("sieges", {}) as Dictionary).size(),
		(war.get("occupied_provinces", {}) as Dictionary).size(),
		offers.size(),
	]) + result_text
	if String(_focused_marker_context.get("war_id", "")) == _current_war_id:
		details_label.text += "\nFocused %s · province %d · marker %d of %d in cluster" % [
			String(_focused_marker_context.get("marker_type", "conflict")).capitalize(),
			int(_focused_marker_context.get("province_id", -1)),
			int(_focused_marker_context.get("cluster_member_index", 0)) + 1,
			int(_focused_marker_context.get("cluster_size", 1)),
		]


func _select_war(index: int) -> void:
	_current_war_id = String(war_option.get_item_metadata(index))
	_refresh_war()


func _improve_relations() -> void:
	simulation_controller.improve_relations(_player_country(), _target_country)


func _toggle_alliance() -> void:
	if DiplomacySystemScript.are_allied(simulation_controller.world, _player_country(), _target_country):
		simulation_controller.break_alliance(_player_country(), _target_country)
	else:
		simulation_controller.form_alliance(_player_country(), _target_country)


func _handle_access() -> void:
	var relationship := simulation_controller.relationship(_player_country(), _target_country)
	if bool((relationship.get("access_requests", {}) as Dictionary).get(_target_country, false)):
		simulation_controller.grant_military_access(_player_country(), _target_country)
	else:
		simulation_controller.request_military_access(_player_country(), _target_country)


func _declare_war() -> void:
	simulation_controller.declare_war(_player_country(), _target_country, _target_province_id)


func _opposing_leader(war: Dictionary) -> String:
	return String(war["defender_leader"]) if (war.get("attackers", []) as Array).has(_player_country()) else String(war["attacker_leader"])


func _offer_white_peace() -> void:
	var war: Dictionary = simulation_controller.world.war_registry[_current_war_id]
	simulation_controller.offer_peace(_current_war_id, _player_country(), _opposing_leader(war), [{"type": "white_peace"}])


func _offer_war_goal() -> void:
	var war: Dictionary = simulation_controller.world.war_registry[_current_war_id]
	var goal: Dictionary = war.get("war_goal", {})
	var terms: Array = []
	if String(goal.get("type", "")) == "press_claim":
		terms = [{"type": "press_claim", "claim_id": String(goal.get("claim_id", ""))}]
	else:
		terms = [{"type": "transfer_province", "province_id": int(goal.get("province_id", -1)), "to": _player_country()}]
	simulation_controller.offer_peace(_current_war_id, _player_country(), _opposing_leader(war), terms)


func _incoming_offer_id(war: Dictionary) -> String:
	var ids := (war.get("peace_offers", {}) as Dictionary).keys()
	ids.sort()
	for raw_id in ids:
		var offer: Dictionary = war["peace_offers"][raw_id]
		if String(offer.get("receiver", "")) == _player_country() and simulation_controller.world.current_day <= int(offer.get("expires_day", -1)):
			return String(raw_id)
	return ""


func _accept_incoming_offer() -> void:
	var war: Dictionary = simulation_controller.world.war_registry[_current_war_id]
	var offer_id := _incoming_offer_id(war)
	if not offer_id.is_empty():
		simulation_controller.accept_peace(_current_war_id, offer_id, _player_country())


func _show_relations_map() -> void:
	var player := _player_country()
	var colors := {}
	var ids := simulation_controller.world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var owner := simulation_controller.world.get_province_owner(province_id)
		if owner == player:
			colors[province_id] = Color(0.18, 0.48, 0.9)
		elif owner.is_empty():
			colors[province_id] = Color(0.18, 0.19, 0.21)
		else:
			var value := DiplomacySystemScript.opinion(simulation_controller.world, player, owner)
			colors[province_id] = Color(0.72, 0.2, 0.18).lerp(Color(0.2, 0.7, 0.35), clampf((value + 200.0) / 400.0, 0.0, 1.0))
	map_hud.set_strategy_map_overlay("relations", "Relations: blue is your country; red hostile opinion; green friendly opinion.", colors)


func _show_war_map() -> void:
	if _current_war_id.is_empty():
		return
	var war: Dictionary = simulation_controller.world.war_registry[_current_war_id]
	var colors := {}
	var ids := simulation_controller.world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var owner := simulation_controller.world.get_province_owner(province_id)
		var side := DiplomacySystemScript.side_in_war(war, owner)
		colors[province_id] = Color(0.18, 0.2, 0.23) if side == 0 else (Color(0.15, 0.45, 0.88) if side > 0 else Color(0.8, 0.18, 0.16))
	for raw_key in (war.get("occupied_provinces", {}) as Dictionary):
		var occupation: Dictionary = war["occupied_provinces"][raw_key]
		colors[int(raw_key)] = Color(0.68, 0.28, 0.78) if int(occupation.get("side", 0)) > 0 else Color(0.95, 0.46, 0.18)
	var goal_id := int((war.get("war_goal", {}) as Dictionary).get("province_id", -1))
	map_hud.set_strategy_map_overlay("war", "War: blue attackers, red defenders, purple/orange occupation, gold double border is the war goal.", colors, goal_id)


func _show_access_map() -> void:
	var player := _player_country()
	var colors := {}
	var ids := simulation_controller.world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var owner := simulation_controller.world.get_province_owner(province_id)
		if owner == player:
			colors[province_id] = Color(0.18, 0.48, 0.9)
		elif owner.is_empty():
			colors[province_id] = Color(0.18, 0.19, 0.21)
		elif DiplomacySystemScript.are_at_war(simulation_controller.world, player, owner):
			colors[province_id] = Color(0.82, 0.18, 0.15)
		elif DiplomacySystemScript.are_allied(simulation_controller.world, player, owner) or DiplomacySystemScript.has_access(simulation_controller.world, player, owner):
			colors[province_id] = Color(0.2, 0.72, 0.38)
		else:
			colors[province_id] = Color(0.25, 0.27, 0.3)
	map_hud.set_strategy_map_overlay("access", "Military access: blue yours, green accessible, red enemy, grey permission required.", colors)
