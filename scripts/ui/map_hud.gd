extends Control
class_name MapHUD

@export var province_selector: ProvinceSelector
@export var country_data: CountryData

@onready var tooltip: PanelContainer = %ProvinceTooltip
@onready var tooltip_title: Label = %TooltipTitle
@onready var tooltip_id: Label = %TooltipId
@onready var tooltip_owner: Label = %TooltipOwner
@onready var province_panel: PanelContainer = %ProvincePanel
@onready var province_title: Label = %ProvinceTitle
@onready var province_id_label: Label = %ProvinceId
@onready var owner_value: Label = %OwnerValue
@onready var capital_value: Label = %CapitalValue
@onready var culture_value: Label = %CultureValue
@onready var religion_value: Label = %ReligionValue
@onready var trade_goods_value: Label = %TradeGoodsValue
@onready var province_status: Label = %ProvinceStatus
@onready var close_button: Button = %CloseButton

var _tooltip_screen_position := Vector2.ZERO
var _tooltip_province_id := -1
var _province_history_paths: Dictionary[int, String] = {}
var _province_detail_cache: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	tooltip.hide()
	province_panel.hide()
	_set_mouse_filter_recursive(tooltip, Control.MOUSE_FILTER_IGNORE)
	_index_province_history_files()

	province_selector.province_hovered.connect(_on_province_hovered)
	province_selector.province_hover_cleared.connect(_on_province_hover_cleared)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(_on_selection_cleared)
	close_button.pressed.connect(province_selector.clear_selection)


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)


func _owner_text(info: Dictionary) -> String:
	var owner_tag: String = info.get("owner_tag", "")
	var owner_name: String = info.get("owner_name", "")
	if owner_tag.is_empty() or owner_tag in ["No Owner", "Ocean"] or owner_name.is_empty():
		return "Non-country terrain"
	return "%s  ·  %s" % [owner_name, owner_tag]


func _on_province_hovered(info: Dictionary, screen_position: Vector2) -> void:
	_tooltip_screen_position = screen_position
	var province_id: int = info["province_id"]
	if province_id != _tooltip_province_id:
		_tooltip_province_id = province_id
		tooltip_title.text = info["province_name"]
		tooltip_id.text = "Province %d" % province_id
		tooltip_owner.text = _owner_text(info)
	tooltip.show()


func _on_province_hover_cleared() -> void:
	_tooltip_province_id = -1
	tooltip.hide()


func _on_province_selected(info: Dictionary) -> void:
	var province_id: int = info["province_id"]
	var details := _get_province_details(province_id)
	province_title.text = info["province_name"]
	province_id_label.text = "Province ID  %d" % province_id
	owner_value.text = _owner_text(info)
	capital_value.text = _display_value(details.get("capital", ""))
	culture_value.text = _display_value(details.get("culture", ""))
	religion_value.text = _display_value(details.get("religion", ""))
	trade_goods_value.text = _display_value(details.get("trade_goods", ""))
	province_status.text = "PLAYABLE COUNTRY PROVINCE" if info.get("is_playable", false) else "NON-COUNTRY TERRAIN"
	province_status.modulate = Color("87d9a0") if info.get("is_playable", false) else Color("d3b77c")
	province_panel.show()


func _on_selection_cleared() -> void:
	province_panel.hide()


func _process(_delta: float) -> void:
	if not tooltip.visible:
		return
	var viewport_size := get_viewport_rect().size
	var desired_position := _tooltip_screen_position + Vector2(18.0, 20.0)
	var maximum_position := viewport_size - tooltip.size - Vector2(10.0, 10.0)
	tooltip.position = Vector2(
		clampf(desired_position.x, 10.0, maxf(10.0, maximum_position.x)),
		clampf(desired_position.y, 10.0, maxf(10.0, maximum_position.y))
	)


func _index_province_history_files() -> void:
	var directory := DirAccess.open("res://assets/provinces")
	if directory == null:
		push_warning("Province history folder is unavailable; the panel will show placeholders.")
		return
	for filename in directory.get_files():
		if not filename.to_lower().ends_with(".txt"):
			continue
		var province_id := filename.to_int()
		if province_id > 0:
			_province_history_paths[province_id] = "res://assets/provinces/%s" % filename


func _get_province_details(province_id: int) -> Dictionary:
	if _province_detail_cache.has(province_id):
		return _province_detail_cache[province_id]
	var details := {
		"capital": "",
		"culture": "",
		"religion": "",
		"trade_goods": "",
	}
	var path: String = _province_history_paths.get(province_id, "")
	if path.is_empty():
		_province_detail_cache[province_id] = details
		return details

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_province_detail_cache[province_id] = details
		return details
	var content := file.get_buffer(file.get_length()).get_string_from_ascii()
	for raw_line in content.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#") or not line.contains("="):
			continue
		if line[0].is_valid_int() and line.contains("."):
			break
		var key := line.get_slice("=", 0).strip_edges()
		if not details.has(key) or not String(details[key]).is_empty():
			continue
		var value := line.get_slice("=", 1).get_slice("#", 0).strip_edges()
		value = value.trim_prefix("\"").trim_suffix("\"").strip_edges()
		details[key] = value

	_province_detail_cache[province_id] = details
	return details


func _display_value(value: String) -> String:
	if value.is_empty() or value == "unknown":
		return "Not yet classified"
	return value.replace("_", " ").capitalize()
