extends Control
class_name MapHUD

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const MAX_SEARCH_RESULTS := 12

const MODE_POLITICAL := 0
const MODE_TERRAIN := 1
const MODE_DEBUG := 2
const MODE_LEGENDS: Array[String] = [
	"Political: country colours over terrain. Hatched land is non-playable wasteland.",
	"Terrain: physical ground only. Ownership colours are hidden.",
	"Province IDs: debug view, red/green encode the province lookup ID.",
]

@export var province_selector: ProvinceSelector
@export var country_data: CountryData
@export var map_render: Node
@export var camera_controller: Node

@onready var tooltip: PanelContainer = %ProvinceTooltip
@onready var tooltip_title: Label = %TooltipTitle
@onready var tooltip_id: Label = %TooltipId
@onready var tooltip_owner: Label = %TooltipOwner
@onready var tooltip_terrain: Label = %TooltipTerrain
@onready var province_panel: PanelContainer = %ProvincePanel
@onready var province_title: Label = %ProvinceTitle
@onready var province_id_label: Label = %ProvinceId
@onready var owner_value: Label = %OwnerValue
@onready var controller_value: Label = %ControllerValue
@onready var terrain_value: Label = %TerrainValue
@onready var region_value: Label = %RegionValue
@onready var coastal_value: Label = %CoastalValue
@onready var capital_value: Label = %CapitalValue
@onready var culture_value: Label = %CultureValue
@onready var religion_value: Label = %ReligionValue
@onready var trade_goods_value: Label = %TradeGoodsValue
@onready var province_status: Label = %ProvinceStatus
@onready var close_button: Button = %CloseButton
@onready var open_country_button: Button = %OpenCountryButton
@onready var country_panel: PanelContainer = %CountryPanel
@onready var country_title: Label = %CountryTitle
@onready var country_swatch: ColorRect = %CountrySwatch
@onready var country_province_count: Label = %CountryProvinceCount
@onready var country_capital: Label = %CountryCapital
@onready var focus_country_button: Button = %FocusCountryButton
@onready var close_country_button: Button = %CloseCountryButton
@onready var mode_political_button: Button = %ModePolitical
@onready var mode_terrain_button: Button = %ModeTerrain
@onready var mode_debug_button: Button = %ModeDebug
@onready var mode_legend: Label = %ModeLegend
@onready var search_field: LineEdit = %SearchField
@onready var search_results: ItemList = %SearchResults
@onready var map_mode_bar: PanelContainer = $MapModeBar
@onready var search_box: VBoxContainer = $SearchBox

var _tooltip_screen_position := Vector2.ZERO
var _tooltip_province_id := -1
var _province_history_paths: Dictionary[int, String] = {}
var _province_detail_cache: Dictionary[int, Dictionary] = {}
var _province_metadata: Dictionary[int, Dictionary] = {}
var _province_names: Dictionary[int, String] = {}
var _country_province_counts: Dictionary[String, int] = {}
var _search_entries: Array[Dictionary] = []
var _current_map_mode := MODE_POLITICAL
var _external_map_mode := ""
var _panel_country_tag := ""


func _ready() -> void:
	tooltip.hide()
	province_panel.hide()
	country_panel.hide()
	search_results.hide()
	_set_mouse_filter_recursive(tooltip, Control.MOUSE_FILTER_IGNORE)
	_index_province_history_files()
	_load_province_metadata()

	province_selector.province_hovered.connect(_on_province_hovered)
	province_selector.province_hover_cleared.connect(_on_province_hover_cleared)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(_on_selection_cleared)
	close_button.pressed.connect(province_selector.clear_selection)
	open_country_button.pressed.connect(_on_open_country_pressed)
	close_country_button.pressed.connect(_close_country_panel)
	focus_country_button.pressed.connect(_on_focus_country_pressed)
	mode_political_button.pressed.connect(func() -> void: set_map_mode(MODE_POLITICAL))
	mode_terrain_button.pressed.connect(func() -> void: set_map_mode(MODE_TERRAIN))
	mode_debug_button.pressed.connect(func() -> void: set_map_mode(MODE_DEBUG))
	search_field.text_changed.connect(_on_search_text_changed)
	search_field.text_submitted.connect(_on_search_submitted)
	search_results.item_activated.connect(_on_search_result_activated)
	search_results.item_clicked.connect(func(index: int, _pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_on_search_result_activated(index))
	_apply_mode_to_buttons()


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)


# --- Map modes -------------------------------------------------------------

func set_map_mode(mode: int) -> void:
	_external_map_mode = ""
	_current_map_mode = clampi(mode, MODE_POLITICAL, MODE_DEBUG)
	if map_render != null and map_render.has_method("restore_political_map"):
		map_render.restore_political_map()
	if map_render != null and map_render.has_method("set_map_mode"):
		map_render.set_map_mode(_current_map_mode)
	_apply_mode_to_buttons()


func get_map_mode() -> int:
	return _current_map_mode


func _apply_mode_to_buttons() -> void:
	if not _external_map_mode.is_empty():
		mode_political_button.disabled = false
		mode_terrain_button.disabled = false
		mode_debug_button.disabled = false
		return
	mode_political_button.disabled = _current_map_mode == MODE_POLITICAL
	mode_terrain_button.disabled = _current_map_mode == MODE_TERRAIN
	mode_debug_button.disabled = _current_map_mode == MODE_DEBUG
	mode_legend.text = MODE_LEGENDS[_current_map_mode]


func set_economy_map_mode(mode_name: String, legend: String, values: Dictionary) -> void:
	_external_map_mode = mode_name
	if map_render != null and map_render.has_method("apply_economy_heatmap"):
		map_render.apply_economy_heatmap(values)
	mode_legend.text = legend
	_apply_mode_to_buttons()


func set_strategy_map_overlay(mode_name: String, legend: String, colors: Dictionary) -> void:
	_external_map_mode = mode_name
	if map_render != null and map_render.has_method("apply_strategy_overlay"):
		map_render.apply_strategy_overlay(colors)
	mode_legend.text = legend
	_apply_mode_to_buttons()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_1:
			set_map_mode(MODE_POLITICAL)
		KEY_2:
			set_map_mode(MODE_TERRAIN)
		KEY_3:
			set_map_mode(MODE_DEBUG)
		KEY_SLASH, KEY_F:
			if key_event.keycode == KEY_F and not key_event.ctrl_pressed:
				return
			search_field.grab_focus()
			get_viewport().set_input_as_handled()


# --- Search ----------------------------------------------------------------

func _build_search_entries() -> void:
	if not _search_entries.is_empty():
		return
	var owners_in_use := {}
	for owner_tag in country_data.province_id_to_owner.values():
		owners_in_use[owner_tag] = true
	for tag in country_data.country_id_to_country_name:
		if not owners_in_use.has(tag):
			continue
		var country_name: String = country_data.country_id_to_country_name[tag]
		_search_entries.append({
			"kind": "country",
			"label": "%s  ·  %s" % [country_name, tag],
			"needle": ("%s %s" % [country_name, tag]).to_lower(),
			"tag": tag,
		})
	_build_province_names()
	for province_id in _province_names:
		var province_name := _province_names[province_id]
		_search_entries.append({
			"kind": "province",
			"label": "%s  (province %d)" % [province_name, province_id],
			"needle": ("%s %d" % [province_name, province_id]).to_lower(),
			"province_id": province_id,
		})


func _build_province_names() -> void:
	if not _province_names.is_empty() or province_selector.map_data == null:
		return
	var map_data := province_selector.map_data
	for color in map_data.province_color_to_id:
		var province_id: int = map_data.province_color_to_id[color]
		var province_name: String = map_data.province_color_to_name.get(color, "")
		if province_id > 0 and not province_name.is_empty():
			_province_names[province_id] = province_name


func _on_search_text_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	search_results.clear()
	if query.length() < 2:
		search_results.hide()
		return
	_build_search_entries()
	var shown := 0
	for entry in _search_entries:
		if shown >= MAX_SEARCH_RESULTS:
			break
		if not (entry["needle"] as String).contains(query):
			continue
		var index := search_results.add_item(entry["label"], null, true)
		search_results.set_item_metadata(index, entry)
		shown += 1
	search_results.visible = shown > 0


func _on_search_submitted(_text: String) -> void:
	if search_results.item_count > 0:
		_on_search_result_activated(0)


func _on_search_result_activated(index: int) -> void:
	var entry: Dictionary = search_results.get_item_metadata(index)
	if entry.is_empty():
		return
	search_results.hide()
	search_field.release_focus()
	if entry["kind"] == "country":
		_focus_country(entry["tag"])
		_show_country_panel(entry["tag"])
	else:
		_focus_province(entry["province_id"])


func _focus_province(province_id: int) -> void:
	var metadata: Dictionary = _province_metadata.get(province_id, {})
	if metadata.is_empty() or camera_controller == null:
		return
	camera_controller.focus_world_position(_centroid_to_world(metadata["centroid"]))
	# Select whatever now sits at the screen centre (the searched province).
	await get_tree().process_frame
	province_selector.select_at_screen_position(get_viewport_rect().size * 0.5)


func _focus_country(tag: String) -> void:
	if camera_controller == null:
		return
	var weighted := Vector2.ZERO
	var total_pixels := 0.0
	for province_id in country_data.province_id_to_owner:
		if country_data.province_id_to_owner[province_id] != tag:
			continue
		var metadata: Dictionary = _province_metadata.get(province_id, {})
		if metadata.is_empty():
			continue
		var pixels: float = metadata["pixel_count"]
		weighted += (metadata["centroid"] as Vector2) * pixels
		total_pixels += pixels
	if total_pixels <= 0.0:
		return
	camera_controller.focus_world_position(_centroid_to_world(weighted / total_pixels))
	if map_render != null and map_render.has_method("highlight_country"):
		map_render.highlight_country(tag)


func _centroid_to_world(centroid: Vector2) -> Vector3:
	return Vector3(
		centroid.x * MAP_PIXEL_SIZE - MAP_HALF_WIDTH,
		0.0,
		centroid.y * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT
	)


# --- Country panel ----------------------------------------------------------

func _country_display_name(tag: String) -> String:
	return country_data.country_id_to_country_name.get(tag, tag)


func _count_country_provinces(tag: String) -> int:
	if _country_province_counts.is_empty():
		for province_id in country_data.province_id_to_owner:
			var owner_tag: String = country_data.province_id_to_owner[province_id]
			_country_province_counts[owner_tag] = _country_province_counts.get(owner_tag, 0) + 1
	return _country_province_counts.get(tag, 0)


func _show_country_panel(tag: String) -> void:
	if tag.is_empty() or tag in ["No Owner", "Ocean"]:
		return
	_panel_country_tag = tag
	country_title.text = "%s  ·  %s" % [_country_display_name(tag), tag]
	country_swatch.color = country_data.country_id_to_color.get(tag, Color.GRAY)
	country_province_count.text = "%d provinces" % _count_country_provinces(tag)
	country_capital.text = "Not yet classified"
	country_panel.show()


func _close_country_panel() -> void:
	_panel_country_tag = ""
	country_panel.hide()


func _on_open_country_pressed() -> void:
	var info := _last_selection_info
	if not info.is_empty() and info.get("is_playable", false):
		_show_country_panel(info["owner_tag"])


func _on_focus_country_pressed() -> void:
	if not _panel_country_tag.is_empty():
		_focus_country(_panel_country_tag)


# --- Selection and tooltip ---------------------------------------------------

var _last_selection_info: Dictionary = {}


func _owner_text(info: Dictionary) -> String:
	var owner_tag: String = info.get("owner_tag", "")
	var owner_name: String = info.get("owner_name", "")
	if owner_tag.is_empty() or owner_tag in ["No Owner", "Ocean"] or owner_name.is_empty():
		return "Non-country terrain"
	return "%s  ·  %s" % [owner_name, owner_tag]


func _terrain_text(province_id: int) -> String:
	var metadata: Dictionary = _province_metadata.get(province_id, {})
	if metadata.is_empty() or String(metadata["biome"]).is_empty():
		return "Not yet classified"
	var text: String = metadata["biome"]
	if metadata["coastal"]:
		text += "  ·  Coastal"
	return text


func _on_province_hovered(info: Dictionary, screen_position: Vector2) -> void:
	_tooltip_screen_position = screen_position
	var province_id: int = info["province_id"]
	if province_id != _tooltip_province_id:
		_tooltip_province_id = province_id
		tooltip_title.text = info["province_name"]
		tooltip_id.text = "Province %d" % province_id
		tooltip_owner.text = _owner_text(info)
		tooltip_terrain.text = _terrain_text(province_id)
	tooltip.show()


func _on_province_hover_cleared() -> void:
	_tooltip_province_id = -1
	tooltip.hide()


func _on_province_selected(info: Dictionary) -> void:
	tooltip.hide()
	_tooltip_province_id = -1
	_last_selection_info = info
	var province_id: int = info["province_id"]
	var details := _get_province_details(province_id)
	var metadata: Dictionary = _province_metadata.get(province_id, {})
	province_title.text = info["province_name"]
	province_id_label.text = "Province ID  %d" % province_id
	owner_value.text = _owner_text(info)
	# Controllers diverge from owners once the military simulation exists.
	controller_value.text = _owner_text(info)
	terrain_value.text = _terrain_text(province_id)
	region_value.text = "Not yet classified"
	coastal_value.text = "Coastal" if not metadata.is_empty() and metadata["coastal"] else "Landlocked"
	capital_value.text = _display_value(details.get("capital", ""))
	culture_value.text = _display_value(details.get("culture", ""))
	religion_value.text = _display_value(details.get("religion", ""))
	trade_goods_value.text = _display_value(details.get("trade_goods", ""))
	province_status.text = "PLAYABLE COUNTRY PROVINCE" if info.get("is_playable", false) else "NON-COUNTRY TERRAIN"
	province_status.modulate = Color("87d9a0") if info.get("is_playable", false) else Color("d3b77c")
	open_country_button.visible = info.get("is_playable", false)
	province_panel.show()
	if info.get("is_playable", false) and country_panel.visible:
		_show_country_panel(info["owner_tag"])


func _on_selection_cleared() -> void:
	_last_selection_info = {}
	province_panel.hide()
	_close_country_panel()


func refresh_authoritative_ownership(changed_province_id: int) -> void:
	# CountryData is a presentation mirror in Phase 2; WorldState owns mutation.
	_country_province_counts.clear()
	if _last_selection_info.is_empty():
		return
	var selected_province_id := int(_last_selection_info.get("province_id", -1))
	if changed_province_id >= 0 and selected_province_id != changed_province_id:
		if country_panel.visible and not _panel_country_tag.is_empty():
			_show_country_panel(_panel_country_tag)
		return
	var owner_tag: String = country_data.province_id_to_owner.get(selected_province_id, "No Owner")
	_last_selection_info["owner_tag"] = owner_tag
	_last_selection_info["owner_name"] = country_data.country_id_to_country_name.get(owner_tag, "")
	_last_selection_info["is_playable"] = not owner_tag.is_empty() and owner_tag not in ["No Owner", "Ocean"]
	_on_province_selected(_last_selection_info)


func _process(_delta: float) -> void:
	if not tooltip.visible:
		return
	var viewport_size := get_viewport_rect().size
	var desired_position := _tooltip_screen_position + Vector2(18.0, 20.0)
	var maximum_position := viewport_size - tooltip.size - Vector2(10.0, 10.0)
	var resolved_position := Vector2(
		clampf(desired_position.x, 10.0, maxf(10.0, maximum_position.x)),
		clampf(desired_position.y, 10.0, maxf(10.0, maximum_position.y))
	)
	var top_blockers: Array[Control] = [map_mode_bar, search_box]
	var simulation_top_bar := get_node_or_null("../SimulationHUD/TopBar") as Control
	if simulation_top_bar != null:
		top_blockers.append(simulation_top_bar)
	for blocker in top_blockers:
		if not blocker.visible:
			continue
		var tooltip_rect := Rect2(resolved_position, tooltip.size)
		if tooltip_rect.intersects(blocker.get_global_rect()):
			resolved_position.y = blocker.get_global_rect().end.y + 10.0
	resolved_position.y = clampf(resolved_position.y, 10.0, maxf(10.0, maximum_position.y))
	tooltip.position = resolved_position


# --- Data loading ------------------------------------------------------------

func _load_province_metadata() -> void:
	var file := FileAccess.open("res://assets/province_metadata.csv", FileAccess.READ)
	if file == null:
		push_warning("Province metadata is missing; terrain, coastal, and search focus degrade to placeholders.")
		return
	var header := file.get_csv_line()
	var columns := {}
	for index in header.size():
		columns[header[index]] = index
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size() or row[0].is_empty():
			continue
		var province_id := int(row[columns["province_id"]])
		_province_metadata[province_id] = {
			"centroid": Vector2(float(row[columns["centroid_x"]]), float(row[columns["centroid_y"]])),
			"pixel_count": float(row[columns["pixel_count"]]),
			"biome": row[columns["biome"]],
			"coastal": row[columns["coastal"]] == "1",
		}


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
