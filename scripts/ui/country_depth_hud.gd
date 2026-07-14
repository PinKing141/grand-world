class_name CountryDepthHUD
extends Control

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var map_hud: MapHUD
@export var notification_hud: SimulationHUD

@onready var open_button: Button = %CountryStateButton
@onready var panel: PanelContainer = %CountryStatePanel
@onready var close_button: Button = %CloseButton
@onready var title_label: Label = %TitleLabel
@onready var overview_label: RichTextLabel = %OverviewLabel
@onready var stability_button: Button = %StabilityButton
@onready var admin_tech_button: Button = %AdminTechButton
@onready var diplomatic_tech_button: Button = %DiplomaticTechButton
@onready var military_tech_button: Button = %MilitaryTechButton
@onready var reform_option: OptionButton = %ReformOption
@onready var reform_button: Button = %ReformButton
@onready var government_option: OptionButton = %GovernmentOption
@onready var government_button: Button = %GovernmentButton
@onready var idea_option: OptionButton = %IdeaOption
@onready var idea_button: Button = %IdeaButton
@onready var ai_label: Label = %AILabel
@onready var society_label: RichTextLabel = %SocietyLabel
@onready var province_label: RichTextLabel = %ProvinceLabel
@onready var convert_religion_button: Button = %ConvertReligionButton
@onready var convert_culture_button: Button = %ConvertCultureButton
@onready var accept_culture_button: Button = %AcceptCultureButton
@onready var fabricate_claim_button: Button = %FabricateClaimButton
@onready var rebels_label: RichTextLabel = %RebelsLabel
@onready var rebel_option: OptionButton = %RebelOption
@onready var suppress_button: Button = %SuppressButton
@onready var subjects_label: RichTextLabel = %SubjectsLabel
@onready var subject_option: OptionButton = %SubjectOption
@onready var integrate_button: Button = %IntegrateButton
@onready var target_country_option: OptionButton = %TargetCountryOption
@onready var vassal_button: Button = %VassalButton
@onready var release_option: OptionButton = %ReleaseOption
@onready var release_button: Button = %ReleaseButton
@onready var event_label: RichTextLabel = %EventLabel
@onready var event_options: VBoxContainer = %EventOptions
@onready var decisions_box: VBoxContainer = %DecisionsBox

var _selected_province_id := -1
var _selected_owner := ""


func _ready() -> void:
	panel.hide()
	open_button.hide()
	open_button.pressed.connect(_toggle_panel)
	close_button.pressed.connect(panel.hide)
	stability_button.pressed.connect(func() -> void: _submit(simulation_controller.increase_stability(_player()), "Stability investment submitted."))
	admin_tech_button.pressed.connect(func() -> void: _advance_technology("administrative"))
	diplomatic_tech_button.pressed.connect(func() -> void: _advance_technology("diplomatic"))
	military_tech_button.pressed.connect(func() -> void: _advance_technology("military"))
	reform_button.pressed.connect(_enact_reform)
	government_button.pressed.connect(_change_government)
	idea_button.pressed.connect(_select_idea)
	convert_religion_button.pressed.connect(_convert_religion)
	convert_culture_button.pressed.connect(_convert_culture)
	accept_culture_button.pressed.connect(_accept_culture)
	fabricate_claim_button.pressed.connect(_fabricate_claim)
	suppress_button.pressed.connect(_suppress_rebels)
	integrate_button.pressed.connect(_integrate_subject)
	vassal_button.pressed.connect(_offer_vassalage)
	release_button.pressed.connect(_release_country)
	%UnrestMapButton.pressed.connect(func() -> void: _set_map_mode("unrest", "Unrest: green is calm; red is close to revolt."))
	%ControlMapButton.pressed.connect(func() -> void: _set_map_mode("control", "Control: green is strong state control; red is weak control."))
	%CultureMapButton.pressed.connect(func() -> void: _set_map_mode("culture", "Culture: matching colours share a province culture."))
	%ReligionMapButton.pressed.connect(func() -> void: _set_map_mode("religion", "Religion: matching colours share a province religion."))
	%TechnologyMapButton.pressed.connect(func() -> void: _set_map_mode("technology", "Technology: brighter teal countries have higher combined technology."))
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(func() -> void:
		_selected_province_id = -1
		_selected_owner = ""
		_refresh_society())
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.economy_month_processed.connect(func(_day: int) -> void: _refresh_if_open())
	events.stability_changed.connect(func(_tag: String, _value: int) -> void: _refresh_if_open())
	events.technology_advanced.connect(func(_tag: String, _track: String, _level: int) -> void: _refresh_if_open())
	events.government_changed.connect(func(_tag: String, _old: String, _new: String) -> void: _refresh_if_open())
	events.government_reformed.connect(func(_tag: String, _reform: String) -> void: _refresh_if_open())
	events.idea_group_selected.connect(func(_tag: String, _idea: String) -> void: _refresh_if_open())
	events.province_converted.connect(func(_tag: String, _province: int, _type: String, _target: String) -> void: _refresh_if_open())
	events.province_claim_created.connect(func(_tag: String, _province: int, _expiry: int) -> void: _refresh_if_open())
	events.revolt_started.connect(func(_faction: String, country: String, province: int) -> void:
		if country == _player():
			_notify("Revolt started in province %d." % province)
		_refresh_if_open())
	events.subject_created.connect(func(_id: String, _overlord: String, _subject: String, _type: String) -> void: _refresh_if_open())
	events.subject_integrated.connect(func(_id: String, _overlord: String, _subject: String) -> void: _refresh_if_open())
	events.country_event_triggered.connect(func(_id: String, country: String, _event: String) -> void:
		if country == _player():
			_notify("A country event requires your decision.")
		_refresh_if_open())
	events.country_event_resolved.connect(func(_id: String, _country: String, _option: String) -> void: _refresh_if_open())
	events.country_decision_enacted.connect(func(_country: String, _decision: String) -> void: _refresh_if_open())
	events.country_formed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.country_released.connect(func(_releaser: String, _released: String, _provinces: Array) -> void: _refresh_if_open())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())


func _toggle_panel() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh_all()


func _player() -> String:
	return simulation_controller.world.player_country if simulation_controller.initialized else ""


func _refresh_if_open() -> void:
	if panel.visible:
		_refresh_all()


func _refresh_all() -> void:
	if not is_node_ready() or not simulation_controller.initialized:
		return
	var tag := _player()
	open_button.visible = not tag.is_empty()
	if tag.is_empty():
		panel.hide()
		return
	var runtime := simulation_controller.country_depth_snapshot(tag)
	var country_name := _country_name(tag)
	title_label.text = "%s · Country & State" % country_name
	_refresh_overview(tag, runtime)
	_refresh_society()
	_refresh_subjects(tag, runtime)
	_refresh_events(tag, runtime)


func _refresh_overview(tag: String, runtime: Dictionary) -> void:
	var government_id := String(runtime.get("government_id", "feudal_monarchy"))
	var government := simulation_controller.country_depth_definition("government", government_id)
	var government_name := simulation_controller.country_depth_localize(String(government.get("name_key", government_id)))
	var ledger: Dictionary = runtime.get("ledger", {})
	var reforms: Array = runtime.get("government_reforms", [])
	var idea_id := String(runtime.get("idea_group_id", ""))
	overview_label.text = "[b]%s · %s[/b]\nStability %+d · %s %.1f%% · Centralisation %.1f%% · War exhaustion %.1f%%\nTreasury %s · Monthly balance %s · Average unrest %.1f%%\nReforms: %s\nNational direction: %s" % [
		_country_name(tag), government_name, int(runtime.get("stability", 0)), String(government.get("authority_name", "Authority")), int(runtime.get("authority_bp", 0)) / 100.0,
		int(runtime.get("centralisation_bp", 0)) / 100.0, int(runtime.get("war_exhaustion_bp", 0)) / 100.0,
		EconomySystemScript.format_money(int(runtime.get("treasury", 0))), EconomySystemScript.format_money(int(ledger.get("balance", 0))), int(runtime.get("average_unrest_bp", 0)) / 100.0,
		", ".join(reforms) if not reforms.is_empty() else "none", idea_id if not idea_id.is_empty() else "not selected",
	]
	var technology: Dictionary = runtime.get("technology", {})
	var points: Dictionary = runtime.get("technology_points", {})
	_set_tech_button(admin_tech_button, tag, "administrative", technology, points)
	_set_tech_button(diplomatic_tech_button, tag, "diplomatic", technology, points)
	_set_tech_button(military_tech_button, tag, "military", technology, points)
	stability_button.text = "Increase stability (%+d → %+d)" % [int(runtime.get("stability", 0)), mini(3, int(runtime.get("stability", 0)) + 1)]
	stability_button.disabled = int(runtime.get("stability", 0)) >= 3
	_populate_reforms(government, reforms)
	_populate_governments(government_id)
	_populate_ideas(idea_id)
	var ai := simulation_controller.country_depth_ai_snapshot(tag)
	ai_label.text = "Country AI: %s — %s" % [String(ai.get("last_action", "awaiting review")).replace("_", " "), String(ai.get("last_reason", "No monthly review recorded."))]


func _set_tech_button(button: Button, tag: String, track: String, technology: Dictionary, points: Dictionary) -> void:
	var cost := CountryDepthSystemScript.technology_cost(simulation_controller.world, tag, track, simulation_controller.country_depth_definitions)
	button.text = "%s %d · %d pts%s" % [track.capitalize(), int(technology.get(track, 0)), int(points.get(track, 0)), " · MAX" if cost < 0 else " · next %d" % cost]
	button.disabled = cost < 0 or int(points.get(track, 0)) < cost


func _populate_reforms(government: Dictionary, active: Array) -> void:
	reform_option.clear()
	var reforms: Array = government.get("reforms", [])
	reforms.sort()
	for raw_id in reforms:
		var id := String(raw_id)
		if active.has(id):
			continue
		var definition := simulation_controller.country_depth_definition("reform", id)
		reform_option.add_item(simulation_controller.country_depth_localize(String(definition.get("name_key", id))))
		reform_option.set_item_metadata(reform_option.item_count - 1, id)
	reform_button.disabled = reform_option.item_count == 0


func _populate_governments(active_id: String) -> void:
	government_option.clear()
	var catalog := simulation_controller.country_depth_catalog("governments")
	var ids := catalog.keys()
	ids.sort()
	for raw_id in ids:
		var id := String(raw_id)
		if id == active_id:
			continue
		var definition: Dictionary = catalog[id]
		government_option.add_item(simulation_controller.country_depth_localize(String(definition.get("name_key", id))))
		government_option.set_item_metadata(government_option.item_count - 1, id)
	government_button.disabled = government_option.item_count == 0


func _populate_ideas(active_id: String) -> void:
	idea_option.clear()
	var catalog := simulation_controller.country_depth_catalog("ideas")
	var ids := catalog.keys()
	ids.sort()
	for raw_id in ids:
		var id := String(raw_id)
		var definition: Dictionary = catalog[id]
		idea_option.add_item(simulation_controller.country_depth_localize(String(definition.get("name_key", id))))
		idea_option.set_item_metadata(idea_option.item_count - 1, id)
	idea_button.disabled = not active_id.is_empty() or idea_option.item_count == 0


func _refresh_society() -> void:
	if not simulation_controller.initialized or _player().is_empty():
		return
	var runtime := simulation_controller.country_depth_snapshot(_player())
	society_label.text = "[b]Culture & religion[/b]\nPrimary culture: %s · Accepted: %s\nState religion: %s · Religious unity %.1f%%\nTolerance: own %+d · heretic %+d · heathen %+d" % [
		String(runtime.get("primary_culture", "unknown")), ", ".join(runtime.get("accepted_cultures", [])) if not (runtime.get("accepted_cultures", []) as Array).is_empty() else "none",
		String(runtime.get("state_religion", "unknown")), int(runtime.get("religious_unity_bp", 0)) / 100.0,
		int(runtime.get("tolerance_own", 0)), int(runtime.get("tolerance_heretic", 0)), int(runtime.get("tolerance_heathen", 0)),
	]
	var has_province := _selected_province_id >= 0 and simulation_controller.world.has_province(_selected_province_id)
	if not has_province:
		province_label.text = "[b]Selected province[/b]\nSelect a province to inspect culture, faith, unrest sources, claims, and conversion."
		_set_province_actions_disabled(true)
	else:
		var economy := simulation_controller.province_economy(_selected_province_id)
		var sources: Dictionary = economy.get("unrest_sources", {})
		var source_lines: Array[String] = []
		var keys := sources.keys()
		keys.sort()
		for key in keys:
			source_lines.append("%s %+0.1f%%" % [String(key).replace("_", " "), int(sources[key]) / 100.0])
		province_label.text = "[b]Province %d · %s[/b]\nCulture %s · Religion %s · Control %.1f%% · Unrest %.1f%%\nCores: %s · Claims: %d\nUnrest sources: %s\nConversion: %s" % [
			_selected_province_id, _country_name(_selected_owner), String(economy.get("culture", "unknown")), String(economy.get("religion", "unknown")), int(economy.get("control_bp", 0)) / 100.0, int(economy.get("unrest_bp", 0)) / 100.0,
			_country_name_list(economy.get("cores", [])), (economy.get("claims", []) as Array).size(),
			", ".join(source_lines) if not source_lines.is_empty() else "awaiting monthly calculation", _conversion_text(economy.get("conversion", {})),
		]
		var owned := _selected_owner == _player()
		convert_religion_button.disabled = not owned or not (economy.get("conversion", {}) as Dictionary).is_empty() or String(economy.get("religion", "")) == String(runtime.get("state_religion", ""))
		convert_culture_button.disabled = not owned or not (economy.get("conversion", {}) as Dictionary).is_empty() or String(economy.get("culture", "")) == String(runtime.get("primary_culture", ""))
		accept_culture_button.disabled = not owned or String(economy.get("culture", "")) == String(runtime.get("primary_culture", "")) or (runtime.get("accepted_cultures", []) as Array).has(String(economy.get("culture", "")))
		fabricate_claim_button.disabled = owned or _selected_owner.is_empty() or CountryDepthSystemScript.has_valid_claim_or_core(simulation_controller.world, _player(), _selected_province_id)
	_refresh_rebels(runtime)


func _refresh_rebels(runtime: Dictionary) -> void:
	rebel_option.clear()
	var factions: Array = runtime.get("rebel_factions", [])
	factions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("faction_id", "")) < String(b.get("faction_id", "")))
	var lines: Array[String] = []
	for faction in factions:
		var id := String((faction as Dictionary).get("faction_id", ""))
		lines.append("%s · province %d · %.1f%% · %s" % [String(faction.get("type", "rebels")), int(faction.get("province_id", -1)), int(faction.get("progress_bp", 0)) / 100.0, String(faction.get("status", ""))])
		rebel_option.add_item("%s · %.1f%%" % [id, int(faction.get("progress_bp", 0)) / 100.0])
		rebel_option.set_item_metadata(rebel_option.item_count - 1, id)
	rebels_label.text = "[b]Rebel factions[/b]\n%s" % ("\n".join(lines) if not lines.is_empty() else "No organised rebel factions.")
	suppress_button.disabled = rebel_option.item_count == 0


func _refresh_subjects(tag: String, runtime: Dictionary) -> void:
	subject_option.clear()
	var lines: Array[String] = []
	for raw_record in runtime.get("subjects", []):
		var record: Dictionary = raw_record
		if String(record.get("status", "active")) != "active":
			continue
		var relation_text := "%s → %s · %s · liberty %.1f%% · integration %.1f%%" % [_country_name(String(record.get("overlord", ""))), _country_name(String(record.get("subject", ""))), String(record.get("type", "")), int(record.get("liberty_desire_bp", 0)) / 100.0, int(record.get("integration_progress_bp", 0)) / 100.0]
		lines.append(relation_text)
		if String(record.get("overlord", "")) == tag:
			subject_option.add_item(relation_text)
			subject_option.set_item_metadata(subject_option.item_count - 1, String(record.get("subject_id", "")))
	subjects_label.text = "[b]Subject relationships[/b]\n%s" % ("\n".join(lines) if not lines.is_empty() else "No active subject relationships.")
	integrate_button.disabled = subject_option.item_count == 0
	_populate_vassal_targets(tag)
	_populate_release_targets(tag)


func _populate_vassal_targets(tag: String) -> void:
	target_country_option.clear()
	var tags := simulation_controller.world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var target := String(raw_tag)
		if target == tag or simulation_controller.world.get_country_provinces(target).is_empty() or not CountryDepthSystemScript.overlord_of(simulation_controller.world, target).is_empty():
			continue
		target_country_option.add_item(_country_name(target))
		target_country_option.set_item_metadata(target_country_option.item_count - 1, target)
	vassal_button.disabled = target_country_option.item_count == 0


func _populate_release_targets(tag: String) -> void:
	release_option.clear()
	var candidates := {}
	for province_id in simulation_controller.world.get_country_provinces(tag):
		for raw_core in simulation_controller.province_economy(province_id).get("cores", []):
			var core := String(raw_core)
			if core != tag and simulation_controller.world.has_country(core) and simulation_controller.world.get_country_provinces(core).is_empty():
				candidates[core] = true
	var tags := candidates.keys()
	tags.sort()
	for raw_tag in tags:
		release_option.add_item(_country_name(String(raw_tag)))
		release_option.set_item_metadata(release_option.item_count - 1, String(raw_tag))
	release_button.disabled = release_option.item_count == 0


func _refresh_events(tag: String, runtime: Dictionary) -> void:
	_clear_children(event_options)
	var pending: Dictionary = runtime.get("pending_event", {})
	if pending.is_empty():
		event_label.text = "[b]Country events[/b]\nNo event currently requires a decision."
	else:
		var definition := simulation_controller.country_depth_definition("event", String(pending.get("definition_id", "")))
		event_label.text = "[b]%s[/b]\nChoose one response. Events and their outcomes are authoritative and saved." % simulation_controller.country_depth_localize(String(definition.get("title_key", "event")))
		for raw_option in definition.get("options", []):
			var option: Dictionary = raw_option
			var button := Button.new()
			button.text = simulation_controller.country_depth_localize(String(option.get("text_key", option.get("id", "Option"))))
			var instance_id := String(pending.get("instance_id", ""))
			var option_id := String(option.get("id", ""))
			button.pressed.connect(func() -> void:
				simulation_controller.choose_country_event_option(tag, instance_id, option_id)
				_notify("Event response submitted."))
			event_options.add_child(button)
	_clear_children(decisions_box)
	var decisions := simulation_controller.country_depth_decisions()
	var ids := decisions.keys()
	ids.sort()
	for raw_id in ids:
		var decision_id := String(raw_id)
		var definition: Dictionary = decisions[decision_id]
		var failure := simulation_controller.country_decision_validation(tag, decision_id)
		var button := Button.new()
		button.text = "%s%s" % [simulation_controller.country_depth_localize(String(definition.get("name_key", decision_id))), " · %s" % failure if not failure.is_empty() else ""]
		button.disabled = not failure.is_empty()
		button.tooltip_text = failure
		button.pressed.connect(func() -> void:
			simulation_controller.enact_country_decision(tag, decision_id)
			_notify("National decision submitted."))
		decisions_box.add_child(button)


func _advance_technology(track: String) -> void:
	_submit(simulation_controller.advance_technology(_player(), track), "%s technology investment submitted." % track.capitalize())


func _enact_reform() -> void:
	if reform_option.item_count > 0:
		_submit(simulation_controller.enact_government_reform(_player(), String(reform_option.get_item_metadata(reform_option.selected))), "Government reform submitted.")


func _change_government() -> void:
	if government_option.item_count > 0:
		_submit(simulation_controller.change_government(_player(), String(government_option.get_item_metadata(government_option.selected))), "Government change submitted.")


func _select_idea() -> void:
	if idea_option.item_count > 0:
		_submit(simulation_controller.select_idea_group(_player(), String(idea_option.get_item_metadata(idea_option.selected))), "National direction submitted.")


func _convert_religion() -> void:
	var target := String(simulation_controller.country_depth_snapshot(_player()).get("state_religion", "unknown"))
	_submit(simulation_controller.start_province_conversion(_player(), _selected_province_id, "religion", target), "Religious conversion submitted.")


func _convert_culture() -> void:
	var target := String(simulation_controller.country_depth_snapshot(_player()).get("primary_culture", "unknown"))
	_submit(simulation_controller.start_province_conversion(_player(), _selected_province_id, "culture", target), "Cultural conversion submitted.")


func _accept_culture() -> void:
	var culture := String(simulation_controller.province_economy(_selected_province_id).get("culture", "unknown"))
	_submit(simulation_controller.accept_culture(_player(), culture), "Culture acceptance submitted.")


func _fabricate_claim() -> void:
	_submit(simulation_controller.fabricate_province_claim(_player(), _selected_province_id), "Claim fabrication submitted.")


func _suppress_rebels() -> void:
	if rebel_option.item_count > 0:
		_submit(simulation_controller.suppress_rebels(_player(), String(rebel_option.get_item_metadata(rebel_option.selected))), "Rebel suppression submitted.")


func _integrate_subject() -> void:
	if subject_option.item_count > 0:
		_submit(simulation_controller.start_subject_integration(_player(), String(subject_option.get_item_metadata(subject_option.selected))), "Subject integration submitted.")


func _offer_vassalage() -> void:
	if target_country_option.item_count > 0:
		_submit(simulation_controller.create_subject(_player(), String(target_country_option.get_item_metadata(target_country_option.selected)), "vassal"), "Vassalage offer submitted.")


func _release_country() -> void:
	if release_option.item_count == 0:
		return
	var released := String(release_option.get_item_metadata(release_option.selected))
	var provinces: Array[int] = []
	for province_id in simulation_controller.world.get_country_provinces(_player()):
		if (simulation_controller.province_economy(province_id).get("cores", []) as Array).has(released):
			provinces.append(province_id)
	_submit(simulation_controller.release_country(_player(), released, provinces), "Country release submitted.")


func _set_map_mode(mode: String, legend: String) -> void:
	map_hud.set_strategy_map_overlay("country_%s" % mode, legend, simulation_controller.country_depth_map_colors(mode))


func _on_province_selected(info: Dictionary) -> void:
	_selected_province_id = int(info.get("province_id", -1))
	_selected_owner = String(info.get("owner_tag", ""))
	if panel.visible:
		_refresh_society()


func _conversion_text(conversion: Dictionary) -> String:
	if conversion.is_empty():
		return "none"
	return "%s → %s (%.1f%%)" % [String(conversion.get("type", "")), String(conversion.get("target", "")), int(conversion.get("progress_bp", 0)) / 100.0]


func _country_name(tag: String) -> String:
	return String(simulation_controller.country_data.country_id_to_country_name.get(tag, "Unknown country"))


func _country_name_list(tags: Array) -> String:
	if tags.is_empty():
		return "none"
	var names: Array[String] = []
	for raw_tag in tags:
		names.append(_country_name(String(raw_tag)))
	return ", ".join(names)


func _set_province_actions_disabled(disabled: bool) -> void:
	convert_religion_button.disabled = disabled
	convert_culture_button.disabled = disabled
	accept_culture_button.disabled = disabled
	fabricate_claim_button.disabled = disabled


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _submit(command_id: int, message: String) -> void:
	if command_id >= 0:
		_notify(message)


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)
