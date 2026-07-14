class_name CharacterHUD
extends Control

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var notification_hud: SimulationHUD

@onready var court_button: Button = %CourtButton
@onready var panel: PanelContainer = %CharacterPanel
@onready var close_button: Button = %CloseButton
@onready var country_option: OptionButton = %CountryOption
@onready var portrait_label: Label = %PortraitLabel
@onready var ruler_label: RichTextLabel = %RulerLabel
@onready var succession_label: RichTextLabel = %SuccessionLabel
@onready var character_option: OptionButton = %CharacterOption
@onready var identity_label: RichTextLabel = %IdentityLabel
@onready var skills_label: RichTextLabel = %SkillsLabel
@onready var family_label: RichTextLabel = %FamilyLabel
@onready var titles_label: RichTextLabel = %TitlesLabel
@onready var ai_label: Label = %AILabel
@onready var marriage_option: OptionButton = %MarriageOption
@onready var marriage_button: Button = %MarriageButton
@onready var opinion_option: OptionButton = %OpinionOption
@onready var opinion_label: RichTextLabel = %OpinionLabel
@onready var claim_button: Button = %ClaimButton

var _country_tag := "CAS"
var _character_id := ""


func _ready() -> void:
	panel.hide()
	court_button.pressed.connect(func() -> void:
		panel.visible = not panel.visible
		if panel.visible:
			_refresh_all())
	close_button.pressed.connect(panel.hide)
	country_option.item_selected.connect(_select_country)
	character_option.item_selected.connect(_select_character)
	marriage_option.item_selected.connect(func(_index: int) -> void: _refresh_marriage_button())
	marriage_button.pressed.connect(_arrange_marriage)
	opinion_option.item_selected.connect(func(_index: int) -> void: _refresh_opinion())
	claim_button.pressed.connect(_press_claim)
	_connect_events()
	_populate_countries()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, player: String) -> void:
		if not CharacterSystemScript.ruler_id(simulation_controller.world, player).is_empty():
			_country_tag = player
			_select_country_option(player)
		_refresh_all())
	events.character_born.connect(func(character_id: String, _mother: String, _father: String) -> void:
		if _character_belongs_to_country(character_id, _country_tag):
			_notify("A child has been born: %s." % _name(character_id))
			_refresh_all())
	events.character_married.connect(func(first_id: String, second_id: String) -> void:
		if _character_belongs_to_country(first_id, _country_tag) or _character_belongs_to_country(second_id, _country_tag):
			_notify("%s and %s are now married." % [_name(first_id), _name(second_id)])
			_refresh_all())
	events.character_died.connect(func(character_id: String, cause: String, _day: int) -> void:
		if panel.visible or _character_belongs_to_country(character_id, simulation_controller.world.player_country):
			_notify("%s has died from %s." % [_name(character_id), cause])
			_refresh_all())
	events.succession_resolved.connect(func(country: String, _old: String, new_ruler: String, _heir: String) -> void:
		if country == simulation_controller.world.player_country or panel.visible:
			_notify("Succession in %s: %s now rules." % [_country_name(country), _name(new_ruler)])
			_refresh_all())
	events.commander_assigned.connect(func(_army: String, _character: String) -> void: _refresh_all())
	events.claim_pressed.connect(func(_claim: String, _title: String, _holder: String) -> void: _refresh_all())
	events.character_ai_decision.connect(func(country: String, _action: String, _reason: String) -> void:
		if panel.visible and country == _country_tag:
			_refresh_country())
	events.world_reloaded.connect(func(_checksum: String) -> void:
		_populate_countries()
		_refresh_all())


func _populate_countries() -> void:
	country_option.clear()
	var tags := simulation_controller.world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if CharacterSystemScript.ruler_id(simulation_controller.world, tag).is_empty():
			continue
		country_option.add_item(_country_name(tag))
		country_option.set_item_metadata(country_option.item_count - 1, tag)
	_select_country_option(_country_tag)


func _select_country_option(tag: String) -> void:
	for index in range(country_option.item_count):
		if String(country_option.get_item_metadata(index)) == tag:
			country_option.select(index)
			return


func _select_country(index: int) -> void:
	_country_tag = String(country_option.get_item_metadata(index))
	_character_id = CharacterSystemScript.ruler_id(simulation_controller.world, _country_tag)
	_refresh_all()


func _select_character(index: int) -> void:
	_character_id = String(character_option.get_item_metadata(index))
	_refresh_character()


func _refresh_all() -> void:
	if not is_node_ready() or not simulation_controller.initialized:
		return
	if CharacterSystemScript.ruler_id(simulation_controller.world, _country_tag).is_empty() and country_option.item_count > 0:
		_country_tag = String(country_option.get_item_metadata(0))
	if _character_id.is_empty() or not simulation_controller.world.character_registry.has(_character_id):
		_character_id = CharacterSystemScript.ruler_id(simulation_controller.world, _country_tag)
	_refresh_country()
	_populate_characters()
	_refresh_character()


func _refresh_country() -> void:
	var world := simulation_controller.world
	var ruler_id := CharacterSystemScript.ruler_id(world, _country_tag)
	var heir_id := CharacterSystemScript.heir_id(world, _country_tag)
	var ruler := CharacterSystemScript.character_summary(world, ruler_id)
	var heir := CharacterSystemScript.character_summary(world, heir_id)
	portrait_label.text = _initials(String(ruler.get("name", "?")))
	ruler_label.text = "[b]%s · %s[/b]\nRuler: %s, age %d · %s\nHeir: %s, age %d\nLegitimacy: %.0f%%" % [
		_country_name(_country_tag), _title_name(String(world.country_runtime(_country_tag).get("primary_title_id", ""))),
		String(ruler.get("name", "No ruler")), int(ruler.get("age", -1)), String(ruler.get("dynasty", "")),
		String(heir.get("name", "No recognised heir")), int(heir.get("age", -1)),
		int(world.country_runtime(_country_tag).get("legitimacy_bp", 0)) / 100.0,
	]
	var order := CharacterSystemScript.eligible_heirs(world, ruler_id, String(world.country_runtime(_country_tag).get("primary_title_id", "")))
	var order_names: Array[String] = []
	for candidate_id in order.slice(0, mini(6, order.size())):
		order_names.append("%d. %s (age %d)" % [order_names.size() + 1, _name(String(candidate_id)), CharacterSystemScript.age_years(world, String(candidate_id))])
	succession_label.text = "[b]Succession · absolute primogeniture[/b]\n%s" % ("\n".join(order_names) if not order_names.is_empty() else "No eligible heir — a cadet successor will be generated to preserve country continuity.")
	var ai := simulation_controller.character_ai_snapshot(_country_tag)
	ai_label.text = "Character AI: %s — %s" % [String(ai.get("last_action", "awaiting review")).replace("_", " "), String(ai.get("last_reason", "No review recorded."))]


func _populate_characters() -> void:
	character_option.clear()
	var ids := simulation_controller.world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var character_id := String(raw_id)
		var character: Dictionary = simulation_controller.world.character_registry[character_id]
		if String(character.get("employer_country", "")) != _country_tag:
			continue
		character_option.add_item("%s%s" % [String(character.get("name", character_id)), " †" if not bool(character.get("alive", false)) else ""])
		character_option.set_item_metadata(character_option.item_count - 1, character_id)
		if character_id == _character_id:
			character_option.select(character_option.item_count - 1)


func _refresh_character() -> void:
	var world := simulation_controller.world
	var summary := CharacterSystemScript.character_summary(world, _character_id)
	if summary.is_empty():
		identity_label.text = "No character selected."
		return
	identity_label.text = "[b]%s[/b] · age %d · %s\n%s · %s · Health %.0f%% · Stress %.0f%%" % [
		String(summary.get("name", "")), int(summary.get("age", 0)), "living" if bool(summary.get("alive", false)) else "deceased",
		String(summary.get("culture", "")), String(summary.get("religion", "")), int(summary.get("health_bp", 0)) / 100.0, int(summary.get("stress_bp", 0)) / 100.0,
	]
	var skills: Dictionary = summary.get("skills", {})
	skills_label.text = "[b]Skills[/b]  Diplomacy %d · Martial %d · Stewardship %d · Intrigue %d · Learning %d\n[b]Traits[/b]  %s" % [
		int(skills.get("diplomacy", 0)), int(skills.get("martial", 0)), int(skills.get("stewardship", 0)), int(skills.get("intrigue", 0)), int(skills.get("learning", 0)),
		", ".join(summary.get("traits", [])) if not (summary.get("traits", []) as Array).is_empty() else "none",
	]
	var family: Dictionary = summary.get("family", {})
	var dynasty: Dictionary = simulation_controller.dynasty_summary(String(summary.get("dynasty_id", "")))
	var child_names: Array[String] = []
	for raw_child in family.get("children", []):
		child_names.append(_name(String(raw_child)))
	family_label.text = "[b]Family tree[/b] · %s · living members %d · renown %d\nFather: %s · Mother: %s\nSpouse: %s\nChildren: %s" % [
		String(dynasty.get("name", "No dynasty")), (dynasty.get("living_members", []) as Array).size(), int(dynasty.get("renown", 0)),
		_name_or_none(String(family.get("father_id", ""))), _name_or_none(String(family.get("mother_id", ""))),
		_name_or_none(String(family.get("spouse_id", ""))), ", ".join(child_names) if not child_names.is_empty() else "none",
	]
	var title_lines: Array[String] = []
	for raw_title in summary.get("titles", []):
		var title_id := String(raw_title)
		title_lines.append("%s · %s" % [_title_name(title_id), title_id])
	var claim_lines: Array[String] = []
	for raw_claim in summary.get("claims", []):
		var claim: Dictionary = world.claim_registry.get(String(raw_claim), {})
		claim_lines.append("%s claim on %s%s" % [String(claim.get("type", "")), _title_name(String(claim.get("title_id", ""))), " · pressed" if bool(claim.get("pressed", false)) else ""])
	titles_label.text = "[b]Titles[/b]\n%s\n[b]Claims[/b]\n%s" % ["\n".join(title_lines) if not title_lines.is_empty() else "none", "\n".join(claim_lines) if not claim_lines.is_empty() else "none"]
	_populate_marriage_candidates()
	_populate_opinion_targets()
	_refresh_claim_button()


func _populate_marriage_candidates() -> void:
	marriage_option.clear()
	var ids := simulation_controller.world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var candidate_id := String(raw_id)
		if CharacterSystemScript.can_marry(simulation_controller.world, _character_id, candidate_id).is_empty():
			var employer := String((simulation_controller.world.character_registry[candidate_id] as Dictionary).get("employer_country", ""))
			marriage_option.add_item("%s · %s" % [_name(candidate_id), _country_name(employer)])
			marriage_option.set_item_metadata(marriage_option.item_count - 1, candidate_id)
	_refresh_marriage_button()


func _refresh_marriage_button() -> void:
	marriage_button.disabled = marriage_option.item_count == 0 or simulation_controller.world.player_country != _country_tag
	marriage_button.text = "Arrange marriage" if marriage_option.item_count > 0 else "No valid marriage candidates"


func _arrange_marriage() -> void:
	if marriage_option.item_count == 0:
		return
	var candidate := String(marriage_option.get_item_metadata(marriage_option.selected))
	simulation_controller.arrange_marriage(_character_id, candidate, _country_tag)
	_notify("Marriage proposal submitted.")


func _populate_opinion_targets() -> void:
	opinion_option.clear()
	var ids := simulation_controller.world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var target_id := String(raw_id)
		if target_id == _character_id or not bool((simulation_controller.world.character_registry[target_id] as Dictionary).get("alive", false)):
			continue
		opinion_option.add_item(_name(target_id))
		opinion_option.set_item_metadata(opinion_option.item_count - 1, target_id)
	_refresh_opinion()


func _refresh_opinion() -> void:
	if opinion_option.item_count == 0:
		opinion_label.text = "No opinion target."
		return
	var target_id := String(opinion_option.get_item_metadata(opinion_option.selected))
	var breakdown := CharacterSystemScript.opinion_breakdown(simulation_controller.world, _character_id, target_id)
	var lines: Array[String] = ["[b]Opinion of %s: %+d[/b]" % [_name(target_id), int(breakdown.get("total", 0))]]
	for raw_source in breakdown.get("sources", []):
		var source: Dictionary = raw_source
		lines.append("%+d  %s" % [int(source.get("value", 0)), String(source.get("label", ""))])
	opinion_label.text = "\n".join(lines)


func _refresh_claim_button() -> void:
	claim_button.disabled = true
	claim_button.text = "No pressable claim"
	if simulation_controller.world.player_country != _country_tag or not simulation_controller.world.character_registry.has(_character_id):
		return
	for raw_claim_id in (simulation_controller.world.character_registry[_character_id] as Dictionary).get("claims", []):
		var claim_id := String(raw_claim_id)
		var claim: Dictionary = simulation_controller.world.claim_registry.get(claim_id, {})
		var title: Dictionary = simulation_controller.world.title_registry.get(String(claim.get("title_id", "")), {})
		var target := String(title.get("country_tag", ""))
		if target.is_empty() or target == _country_tag or bool(claim.get("pressed", false)):
			continue
		claim_button.disabled = false
		claim_button.text = "Press claim on %s" % _title_name(String(claim.get("title_id", "")))
		claim_button.set_meta("claim_id", claim_id)
		claim_button.set_meta("target_country", target)
		return


func _press_claim() -> void:
	simulation_controller.declare_claim_war(_country_tag, String(claim_button.get_meta("target_country", "")), String(claim_button.get_meta("claim_id", "")))
	_notify("Claim-war declaration submitted.")


func _name(character_id: String) -> String:
	return String((simulation_controller.world.character_registry.get(character_id, {}) as Dictionary).get("name", character_id))


func _name_or_none(character_id: String) -> String:
	return _name(character_id) if not character_id.is_empty() else "none"


func _title_name(title_id: String) -> String:
	return String((simulation_controller.world.title_registry.get(title_id, {}) as Dictionary).get("name", title_id if not title_id.is_empty() else "No title"))


func _country_name(tag: String) -> String:
	return String(simulation_controller.country_data.country_id_to_country_name.get(tag, "Unknown country"))


func _initials(name: String) -> String:
	var result := ""
	for word in name.split(" "):
		if not word.is_empty():
			result += word.left(1)
	return result.left(3).to_upper()


func _character_belongs_to_country(character_id: String, country_tag: String) -> bool:
	return not country_tag.is_empty() and String((simulation_controller.world.character_registry.get(character_id, {}) as Dictionary).get("employer_country", "")) == country_tag


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)
